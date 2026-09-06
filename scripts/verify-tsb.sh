#!/bin/sh
set -eu

die() {
  echo "verify-tsb: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command missing: $1"
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel) || die "unable to locate repository root"
app_root="$repo_root/apps/macos/TSB"

for tool in git xcodegen xcodebuild xcrun swift python3 ffmpeg rg mktemp find curl tar shasum awk; do
  require_command "$tool"
done

[ "$(xcodegen --version)" = "Version: 2.46.0" ] || die "XcodeGen 2.46.0 is required"

package_lock="$app_root/Package.resolved"
[ -f "$package_lock" ] || die "app Package.resolved is required: $package_lock"

funasr_source="$app_root/TSB/Core/Transcription/FunASRTranscriber.swift"
funasr_installer="$repo_root/scripts/install-funasr-runtime.sh"
if [ -e "$funasr_source" ] || [ -e "$funasr_installer" ]; then
  [ -f "$funasr_source" ] && [ -f "$funasr_installer" ] && [ -x "$funasr_installer" ] || die "Fun-ASR files must be present together"
  funasr_enabled=1
else
  funasr_enabled=0
fi

local_signer="$app_root/scripts/sign-local-app.sh"
local_sign_test="$app_root/scripts/test-local-signing.sh"
if [ -e "$local_signer" ] || [ -e "$local_sign_test" ]; then
  [ -x "$local_signer" ] && [ -x "$local_sign_test" ] || die "local signing scripts must be executable together"
  local_signing_enabled=1
else
  local_signing_enabled=0
fi

verify_tmp=$(mktemp -d "${TMPDIR:-/tmp}/verify-tsb.XXXXXX")
case "$(basename "$verify_tmp")" in
  verify-tsb.*) ;;
  *) die "refusing unexpected temporary directory: $verify_tmp" ;;
esac

cleanup() {
  find "$verify_tmp" -depth -delete
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

TMPDIR="$verify_tmp/tmp"
mkdir -p "$TMPDIR" "$verify_tmp/project"
export TMPDIR

cd "$repo_root"

git diff HEAD --check
sh -n scripts/verify-tsb.sh \
  apps/macos/TSB/scripts/settings-static-gate.sh \
  scripts/bootstrap-sensevoice-model.sh \
  scripts/bootstrap-paraformer-model.sh \
  scripts/probe-retained-audio.sh
apps/macos/TSB/scripts/settings-static-gate.sh
scripts/bootstrap-sensevoice-model.sh --self-check
scripts/bootstrap-paraformer-model.sh --self-check
scripts/probe-retained-audio.sh --self-check
python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
swift test --package-path probes/sensevoice --scratch-path "$verify_tmp/sensevoice-build"
swift test --package-path probes/paraformer --scratch-path "$verify_tmp/paraformer-build"
xcodegen generate --quiet \
  --spec "$app_root/project.yml" \
  --project "$verify_tmp/project" \
  --project-root "$app_root" \
  --cache-path "$verify_tmp/xcodegen-cache"
generated_package_dir="$verify_tmp/project/TSB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$generated_package_dir"
cp "$package_lock" "$generated_package_dir/Package.resolved"
xcodebuild -quiet \
  -project "$verify_tmp/project/TSB.xcodeproj" \
  -scheme TSB \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$verify_tmp/TestData" \
  -clonedSourcePackagesDirPath "$verify_tmp/SourcePackages" \
  -resultBundlePath "$verify_tmp/TSBTests.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" test
xcrun xcresulttool get test-results summary \
  --compact --path "$verify_tmp/TSBTests.xcresult"
xcodebuild -quiet \
  -project "$verify_tmp/project/TSB.xcodeproj" \
  -scheme TSB \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$verify_tmp/BuildData" \
  -clonedSourcePackagesDirPath "$verify_tmp/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" build

built_app="$verify_tmp/BuildData/Build/Products/Debug/TSB.app"
[ -d "$built_app" ] || die "Debug app missing: $built_app"
[ ! -e "$built_app/Contents/PlugIns/TSBTests.xctest" ] || die "Debug app must not bundle TSBTests.xctest"

if [ "$funasr_enabled" -eq 1 ]; then
  sh -n "$funasr_installer"
  "$funasr_installer" --self-check
fi

if [ "$local_signing_enabled" -eq 1 ]; then
  "$local_signer" "$built_app"
  "$local_sign_test" "$built_app"
fi

echo "TSB verification passed"

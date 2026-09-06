#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-verify-tsb.XXXXXX")
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM

repo="$test_tmp/repo"
fake_bin="$test_tmp/bin"
log="$test_tmp/verify.log"
marker="$test_tmp/built-app"
mkdir -p "$repo/scripts" "$repo/apps/macos/TSB/scripts" "$fake_bin"
cp "$script_dir/verify-tsb.sh" "$repo/scripts/verify-tsb.sh"
chmod +x "$repo/scripts/verify-tsb.sh"
printf 'name: TSB\n' >"$repo/apps/macos/TSB/project.yml"

for path in \
  "$repo/apps/macos/TSB/scripts/settings-static-gate.sh" \
  "$repo/scripts/bootstrap-sensevoice-model.sh" \
  "$repo/scripts/bootstrap-paraformer-model.sh" \
  "$repo/scripts/probe-retained-audio.sh"
do
  cat >"$path" <<'EOF'
#!/bin/sh
name=$(basename "$0" .sh)
printf '%s' "$name" >>"$TSB_VERIFY_LOG"
for argument in "$@"; do
  printf ' %s' "$argument" >>"$TSB_VERIFY_LOG"
done
printf '\n' >>"$TSB_VERIFY_LOG"
EOF
  chmod +x "$path"
done

cat >"$fake_bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = "-C" ] && [ "$3" = "rev-parse" ] && [ "$4" = "--show-toplevel" ]; then
  printf '%s\n' "$TSB_FAKE_REPO"
  exit 0
fi
printf 'git' >>"$TSB_VERIFY_LOG"
for argument in "$@"; do
  printf ' %s' "$argument" >>"$TSB_VERIFY_LOG"
done
printf '\n' >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/xcodegen" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'Version: %s\n' "${TSB_FAKE_XCODEGEN_VERSION:-2.46.0}"
  exit 0
fi
printf 'xcodegen generate\n' >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/xcodebuild" <<'EOF'
#!/bin/sh
operation=
derived_data=
previous=
for argument in "$@"; do
  if [ "$previous" = "-derivedDataPath" ]; then
    derived_data=$argument
  fi
  case "$argument" in
    test|build) operation=$argument ;;
  esac
  previous=$argument
done
printf 'xcodebuild %s\n' "$operation" >>"$TSB_VERIFY_LOG"
if [ "$operation" = "build" ]; then
  app="$derived_data/Build/Products/Debug/TSB.app"
  mkdir -p "$app"
  : >"$TSB_VERIFY_APP_MARKER"
  if [ "${TSB_FAKE_INJECT_TEST:-0}" = "1" ]; then
    mkdir -p "$app/Contents/PlugIns"
    : >"$app/Contents/PlugIns/TSBTests.xctest"
  fi
fi
EOF

cat >"$fake_bin/xcrun" <<'EOF'
#!/bin/sh
printf 'xcrun xcresulttool get test-results summary\n' >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/swift" <<'EOF'
#!/bin/sh
printf 'swift test --package-path %s\n' "$3" >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/python3" <<'EOF'
#!/bin/sh
printf 'python3 -m unittest scripts/tests/test_prepare_g0_corpus.py\n' >>"$TSB_VERIFY_LOG"
EOF

chmod +x "$fake_bin/git" "$fake_bin/xcodegen" "$fake_bin/xcodebuild" "$fake_bin/xcrun" "$fake_bin/swift" "$fake_bin/python3"

expected="$test_tmp/expected.log"
cat >"$expected" <<'EOF'
git diff HEAD --check
settings-static-gate
bootstrap-sensevoice-model --self-check
bootstrap-paraformer-model --self-check
probe-retained-audio --self-check
python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
swift test --package-path probes/sensevoice
swift test --package-path probes/paraformer
xcodegen generate
xcodebuild test
xcrun xcresulttool get test-results summary
xcodebuild build
EOF

PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null
diff -u "$expected" "$log"
[ -f "$marker" ] || {
  echo "self-check expected build-created app" >&2
  exit 1
}

: >"$log"
if PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" TSB_FAKE_INJECT_TEST=1 /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null 2>&1; then
  echo "self-check expected bundled TSBTests.xctest to fail" >&2
  exit 1
fi

: >"$log"
if PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" TSB_FAKE_XCODEGEN_VERSION=2.45.0 /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null 2>&1; then
  echo "self-check expected old XcodeGen to fail" >&2
  exit 1
fi
[ ! -s "$log" ] || {
  echo "self-check expected XcodeGen version check before repository gates" >&2
  exit 1
}

echo "verify-tsb self-check passed"

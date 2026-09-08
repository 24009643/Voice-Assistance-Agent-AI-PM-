#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-verify-tsb.XXXXXX")
case "$(basename "$test_tmp")" in
  test-verify-tsb.*) ;;
  *)
    echo "test-verify-tsb: refusing unexpected temporary directory: $test_tmp" >&2
    exit 1
    ;;
esac

cleanup() {
  find "$test_tmp" -depth -delete
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

repo="$test_tmp/repo"
fake_bin="$test_tmp/bin"
log="$test_tmp/verify.log"
marker="$test_tmp/built-app"
TSB_REAL_GIT=$(command -v git)
TSB_REAL_PYTHON=$(command -v python3)
export TSB_REAL_GIT TSB_REAL_PYTHON
mkdir -p "$repo/scripts/tests" "$repo/apps/macos/TSB/scripts" "$fake_bin"
cp "$script_dir/verify-tsb.sh" "$repo/scripts/verify-tsb.sh"
cp "$script_dir/prepare_g0_corpus.py" "$repo/scripts/prepare_g0_corpus.py"
cp "$script_dir/tests/test_prepare_g0_corpus.py" "$repo/scripts/tests/test_prepare_g0_corpus.py"
chmod +x "$repo/scripts/verify-tsb.sh"
printf 'name: TSB\n' >"$repo/apps/macos/TSB/project.yml"
printf '{"fake":"app lock"}\n' >"$repo/apps/macos/TSB/Package.resolved"

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
  exec "$TSB_REAL_GIT" "$@"
fi
if [ "${TSB_FAKE_SEND_INT:-0}" = "1" ]; then
  kill -INT "$PPID"
fi
if [ "$1" = "diff" ]; then
  if [ "$2" = "HEAD" ]; then
    printf 'git diff HEAD --check\n' >>"$TSB_VERIFY_LOG"
  else
    printf 'git committed diff --check\n' >>"$TSB_VERIFY_LOG"
  fi
fi
exec "$TSB_REAL_GIT" "$@"
EOF

cat >"$fake_bin/xcodegen" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'Version: %s\n' "${TSB_FAKE_XCODEGEN_VERSION:-2.46.0}"
  exit 0
fi
project=
previous=
for argument in "$@"; do
  if [ "$previous" = "--project" ]; then
    project=$argument
  fi
  previous=$argument
done
[ -d "$project" ] || exit 1
mkdir -p "$project/TSB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
printf 'xcodegen generate\n' >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/xcodebuild" <<'EOF'
#!/bin/sh
operation=
derived_data=
project=
only_resolved=0
automatic_disabled=0
previous=
for argument in "$@"; do
  if [ "$previous" = "-derivedDataPath" ]; then
    derived_data=$argument
  fi
  if [ "$previous" = "-project" ]; then
    project=$argument
  fi
  case "$argument" in
    test|build) operation=$argument ;;
    -onlyUsePackageVersionsFromResolvedFile) only_resolved=1 ;;
    -disableAutomaticPackageResolution) automatic_disabled=1 ;;
  esac
  previous=$argument
done
[ "$only_resolved" -eq 1 ] || {
  echo "xcodebuild $operation missing -onlyUsePackageVersionsFromResolvedFile" >&2
  exit 1
}
[ "$automatic_disabled" -eq 1 ] || {
  echo "xcodebuild $operation missing -disableAutomaticPackageResolution" >&2
  exit 1
}
copied_lock="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cmp -s "$TSB_FAKE_REPO/apps/macos/TSB/Package.resolved" "$copied_lock" || {
  echo "xcodebuild $operation missing matching app Package.resolved" >&2
  exit 1
}
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
case " $* " in
  *' --force-resolved-versions '*) ;;
  *) echo "swift test missing --force-resolved-versions" >&2; exit 1 ;;
esac
printf 'swift test --package-path %s\n' "$3" >>"$TSB_VERIFY_LOG"
EOF

cat >"$fake_bin/python3" <<'EOF'
#!/bin/sh
printf 'python3 -m unittest scripts/tests/test_prepare_g0_corpus.py\n' >>"$TSB_VERIFY_LOG"
exec "$TSB_REAL_PYTHON" "$@"
EOF

chmod +x "$fake_bin/git" "$fake_bin/xcodegen" "$fake_bin/xcodebuild" "$fake_bin/xcrun" "$fake_bin/swift" "$fake_bin/python3"

expected="$test_tmp/expected.log"
cat >"$expected" <<'EOF'
git diff HEAD --check
git committed diff --check
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

# Keep Git and Python real: committed whitespace and bytecode are side effects
# that command-only fakes cannot detect. All data remains in this test directory.
git -C "$repo" init --quiet
git -C "$repo" config user.name "TSB Verification Test"
git -C "$repo" config user.email "tsb-test@example.invalid"
git -C "$repo" config commit.gpgsign false
git -C "$repo" config core.hooksPath /dev/null
git -C "$repo" config core.whitespace trailing-space
git -C "$repo" add .
git -C "$repo" commit --quiet -m "test fixture"
git -C "$repo" update-ref refs/remotes/origin/main HEAD
# A caller's real CI base must not leak into the isolated fixture repository.
unset TSB_VERIFY_BASE
unset PYTHONDONTWRITEBYTECODE PYTHONPYCACHEPREFIX

PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null
diff -u "$expected" "$log"
[ -f "$marker" ] || {
  echo "self-check expected build-created app" >&2
  exit 1
}
[ -z "$(find "$repo" -name __pycache__ -print)" ] || {
  echo "self-check expected Python tests not to leave bytecode caches" >&2
  exit 1
}

expect_verification_failure() {
  : >"$log"
  if PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" /bin/sh "$repo/scripts/verify-tsb.sh" >"$test_tmp/failure.log" 2>&1; then
    echo "self-check expected $1 to fail verification" >&2
    exit 1
  fi
  if rg -q '^settings-static-gate$' "$log"; then
    echo "self-check expected $1 to stop before repository gates" >&2
    exit 1
  fi
}

# An early exit hides syntax errors at runtime; sh -n must catch every file.
syntax_fixture="$repo/scripts/probe-retained-audio.sh"
cp "$syntax_fixture" "$test_tmp/valid-gate.sh"
printf '\nexit 0\nif\n' >>"$syntax_fixture"
expect_verification_failure "a later shell file's syntax error"
cp "$test_tmp/valid-gate.sh" "$syntax_fixture"

printf 'committed whitespace \n' >"$repo/whitespace.txt"
git -C "$repo" add whitespace.txt
git -C "$repo" commit --quiet -m "fixture with committed whitespace"
expect_verification_failure "committed whitespace"
# A distinct explicit base must be honored even though origin/main still differs.
PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" TSB_VERIFY_BASE=HEAD /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null
git -C "$repo" update-ref refs/remotes/origin/main HEAD
printf 'uncommitted whitespace \n' >>"$repo/whitespace.txt"
expect_verification_failure "uncommitted whitespace"
git -C "$repo" show HEAD:whitespace.txt >"$repo/whitespace.txt"

for invalid_base in '' nonexistent-base; do
  TSB_VERIFY_BASE=$invalid_base
  export TSB_VERIFY_BASE
  expect_verification_failure "an empty or unknown comparison base"
done
unset TSB_VERIFY_BASE
git -C "$repo" update-ref -d refs/remotes/origin/main
expect_verification_failure "a missing default comparison base"
git -C "$repo" update-ref refs/remotes/origin/main HEAD

: >"$log"
if PATH="$fake_bin:$PATH" TSB_FAKE_REPO="$repo" TSB_VERIFY_LOG="$log" TSB_VERIFY_APP_MARKER="$marker" TSB_FAKE_SEND_INT=1 /bin/sh "$repo/scripts/verify-tsb.sh" >/dev/null 2>&1; then
  echo "self-check expected INT to fail verification" >&2
  exit 1
else
  signal_status=$?
fi
[ "$signal_status" -eq 130 ] || {
  echo "self-check expected INT exit status 130, got $signal_status" >&2
  exit 1
}
[ "$(cat "$log")" = "git diff HEAD --check" ] || {
  echo "self-check expected INT to stop after git diff" >&2
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

#!/bin/sh
set -eu

MODEL_FILES="funasr-encoder-f16.gguf qwen3-0.6b-q8_0.gguf fsmn-vad.gguf"
CLI_NAME="llama-funasr-cli"

die() {
  echo "install-funasr-runtime: $*" >&2
  exit 1
}

require_regular_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || die "required regular file missing: $1"
}

reject_symlink() {
  [ ! -L "$1" ] || die "symlink path is not allowed: $1"
}

verify_bundle() {
  directory=$1
  required_files=$2
  expected_count=$3
  [ -d "$directory" ] || die "bundle directory missing: $directory"
  require_regular_file "$directory/manifest.sha256"
  [ "$(awk 'END { print NR }' "$directory/manifest.sha256")" -eq "$expected_count" ] ||
    die "unexpected manifest entries in $directory"
  for file in $required_files; do
    require_regular_file "$directory/$file"
    awk -v file="$file" '$1 ~ /^[[:xdigit:]]{64}$/ && $2 == file { found++ } END { exit found == 1 ? 0 : 1 }' \
      "$directory/manifest.sha256" || die "manifest missing or duplicates $file"
  done
  (cd "$directory" && shasum -a 256 -c manifest.sha256 >/dev/null 2>&1) ||
    die "checksum verification failed in $directory"
}

install_assets() {
  source_cli=""
  source_models=""
  application_support="${HOME}/Library/Application Support"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source-cli) [ "$#" -ge 2 ] || die "--source-cli requires a path"; source_cli=$2; shift 2 ;;
      --source-model-dir) [ "$#" -ge 2 ] || die "--source-model-dir requires a path"; source_models=$2; shift 2 ;;
      --application-support) [ "$#" -ge 2 ] || die "--application-support requires a path"; application_support=$2; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [ -n "$source_cli" ] || die "--source-cli is required"
  [ -n "$source_models" ] || die "--source-model-dir is required"
  case "$application_support" in /*) ;; *) die "--application-support must be absolute" ;; esac
  require_regular_file "$source_cli"
  [ -x "$source_cli" ] || die "CLI is not executable: $source_cli"
  verify_bundle "$source_models" "$MODEL_FILES" 3

  models_root="$application_support/TSB/Models"
  runtimes_root="$application_support/TSB/Runtimes"
  tsb_root="$application_support/TSB"
  model_target="$models_root/funasr-nano"
  runtime_target="$runtimes_root/funasr-nano"
  reject_symlink "$application_support"
  reject_symlink "$tsb_root"
  reject_symlink "$models_root"
  reject_symlink "$runtimes_root"
  reject_symlink "$model_target"
  reject_symlink "$runtime_target"
  mkdir -p "$models_root" "$runtimes_root"

  runtime_stage=""
  model_stage=""
  runtime_committed=0
  model_committed=0
  lock_acquired=0
  install_lock="$tsb_root/.funasr-install.lock"
  cleanup_install() {
    if [ -n "$runtime_stage" ] && [ -d "$runtime_stage" ]; then rm -rf "$runtime_stage"; fi
    if [ -n "$model_stage" ] && [ -d "$model_stage" ]; then rm -rf "$model_stage"; fi
    if [ "$runtime_committed" -eq 1 ]; then
      rm -f "$runtime_target/$CLI_NAME" "$runtime_target/manifest.sha256"
      rmdir "$runtime_target" 2>/dev/null || true
    fi
    if [ "$model_committed" -eq 1 ]; then
      for file in $MODEL_FILES manifest.sha256; do rm -f "$model_target/$file"; done
      rmdir "$model_target" 2>/dev/null || true
    fi
    if [ "$lock_acquired" -eq 1 ]; then rmdir "$install_lock" 2>/dev/null || true; fi
  }
  cleanup_on_exit() {
    status=$?
    trap - EXIT HUP INT TERM
    cleanup_install
    exit "$status"
  }
  trap cleanup_on_exit EXIT
  trap 'exit 130' HUP INT TERM

  # ponytail: stale locks fail closed; add PID recovery only if installs become automated.
  mkdir "$install_lock" 2>/dev/null || die "another installation is active or a stale lock exists: $install_lock"
  lock_acquired=1

  runtime_exists=0
  model_exists=0
  if [ -e "$runtime_target" ]; then
    verify_bundle "$runtime_target" "$CLI_NAME" 1
    [ -x "$runtime_target/$CLI_NAME" ] || die "installed CLI is not executable"
    runtime_exists=1
  fi
  if [ -e "$model_target" ]; then
    verify_bundle "$model_target" "$MODEL_FILES" 3
    model_exists=1
  fi

  if [ "$runtime_exists" -eq 0 ]; then
    runtime_stage=$(mktemp -d "$runtimes_root/.funasr-nano.XXXXXX")
    cp "$source_cli" "$runtime_stage/$CLI_NAME"
    chmod 755 "$runtime_stage/$CLI_NAME"
    (cd "$runtime_stage" && shasum -a 256 "$CLI_NAME" >manifest.sha256)
    verify_bundle "$runtime_stage" "$CLI_NAME" 1
  fi
  if [ "$model_exists" -eq 0 ]; then
    model_stage=$(mktemp -d "$models_root/.funasr-nano.XXXXXX")
    for file in $MODEL_FILES manifest.sha256; do cp "$source_models/$file" "$model_stage/$file"; done
    verify_bundle "$model_stage" "$MODEL_FILES" 3
  fi

  if [ -n "$runtime_stage" ]; then
    runtime_committed=1
    mv "$runtime_stage" "$runtime_target"
    runtime_stage=""
  fi
  if [ -n "$model_stage" ]; then
    model_committed=1
    mv "$model_stage" "$model_target"
    model_stage=""
  fi
  runtime_committed=0
  model_committed=0
  cleanup_install
  lock_acquired=0
  trap - EXIT HUP INT TERM
  echo "Installed verified Fun-ASR runtime under $application_support/TSB"
}

self_check() {
  test_root=$(mktemp -d "${TMPDIR:-/tmp}/funasr-install-test.XXXXXX")
  trap 'rm -rf "$test_root"' EXIT HUP INT TERM
  source_models="$test_root/source-models"
  source_cli="$test_root/llama-funasr-cli"
  application_support="$test_root/Application Support"
  mkdir -p "$source_models"
  printf '%s\n' '#!/bin/sh' 'echo ok' >"$source_cli"
  chmod +x "$source_cli"
  for file in funasr-encoder-f16.gguf qwen3-0.6b-q8_0.gguf fsmn-vad.gguf; do
    printf '%s\n' "$file" >"$source_models/$file"
  done
  (cd "$source_models" && shasum -a 256 \
    funasr-encoder-f16.gguf qwen3-0.6b-q8_0.gguf fsmn-vad.gguf >manifest.sha256)

  sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$application_support" >/dev/null

  model_target="$application_support/TSB/Models/funasr-nano"
  runtime_target="$application_support/TSB/Runtimes/funasr-nano"
  (cd "$model_target" && shasum -a 256 -c manifest.sha256 >/dev/null)
  (cd "$runtime_target" && shasum -a 256 -c manifest.sha256 >/dev/null)
  [ -x "$runtime_target/llama-funasr-cli" ]

  printf '%s\n' tampered >"$source_models/fsmn-vad.gguf"
  if sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$test_root/invalid" >/dev/null 2>&1; then
    echo "install-funasr-runtime: self-check expected checksum failure" >&2
    exit 1
  fi
  [ ! -e "$test_root/invalid/TSB/Models/funasr-nano" ]
  printf '%s\n' fsmn-vad.gguf >"$source_models/fsmn-vad.gguf"
  (cd "$source_models" && shasum -a 256 \
    funasr-encoder-f16.gguf qwen3-0.6b-q8_0.gguf fsmn-vad.gguf >manifest.sha256)

  linked_support="$test_root/linked"
  linked_destination="$test_root/linked-destination"
  mkdir -p "$linked_support/TSB/Models" "$linked_support/TSB/Runtimes" "$linked_destination"
  ln -s "$linked_destination" "$linked_support/TSB/Models/funasr-nano"
  if sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$linked_support" >/dev/null 2>&1; then
    echo "install-funasr-runtime: self-check expected symlink target failure" >&2
    exit 1
  fi
  [ -L "$linked_support/TSB/Models/funasr-nano" ]

  partial_support="$test_root/partial"
  mkdir -p "$partial_support/TSB/Models/funasr-nano"
  printf '%s\n' broken >"$partial_support/TSB/Models/funasr-nano/manifest.sha256"
  if sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$partial_support" >/dev/null 2>&1; then
    echo "install-funasr-runtime: self-check expected invalid existing model failure" >&2
    exit 1
  fi
  [ ! -e "$partial_support/TSB/Runtimes/funasr-nano" ]

  locked_support="$test_root/locked"
  mkdir -p "$locked_support/TSB/.funasr-install.lock"
  if sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$locked_support" >/dev/null 2>&1; then
    echo "install-funasr-runtime: self-check expected concurrent lock failure" >&2
    exit 1
  fi
  [ ! -e "$locked_support/TSB/Runtimes/funasr-nano" ]

  interrupted_support="$test_root/interrupted"
  fake_bin="$test_root/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/bin/sh' 'set -eu' '/bin/mv "$@"' '/bin/kill -TERM "$PPID"' >"$fake_bin/mv"
  chmod +x "$fake_bin/mv"
  if PATH="$fake_bin:$PATH" sh "$0" --source-cli "$source_cli" --source-model-dir "$source_models" \
    --application-support "$interrupted_support" >/dev/null 2>&1; then
    echo "install-funasr-runtime: self-check expected interrupted install failure" >&2
    exit 1
  fi
  [ ! -e "$interrupted_support/TSB/Runtimes/funasr-nano" ]
  [ ! -e "$interrupted_support/TSB/Models/funasr-nano" ]
  [ ! -e "$interrupted_support/TSB/.funasr-install.lock" ]
  echo "self-check passed"
}

if [ "${1:-}" = "--self-check" ]; then
  self_check
  exit 0
fi

install_assets "$@"

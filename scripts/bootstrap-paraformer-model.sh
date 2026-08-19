#!/bin/sh
set -eu

MODEL_NAME="sherpa-onnx-streaming-paraformer-trilingual-zh-cantonese-en"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
MODEL_ARCHIVE="${MODEL_NAME}.tar.bz2"
DEFAULT_TARGET="${HOME}/Library/Application Support/TSB/Models/${MODEL_NAME}"
REQUIRED_FILES="encoder.int8.onnx decoder.int8.onnx tokens.txt LICENSE"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null) || {
  echo "bootstrap-paraformer-model: unable to locate repository root" >&2
  exit 1
}

err() {
  echo "bootstrap-paraformer-model: $*" >&2
}

die() {
  err "$*"
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/bootstrap-paraformer-model.sh [--target <dir>] [--confirm-existing]
  scripts/bootstrap-paraformer-model.sh --verify-only --target <dir>
  scripts/bootstrap-paraformer-model.sh --self-check

Downloads and verifies the pinned Streaming Paraformer model from sherpa-onnx.
Default target: $DEFAULT_TARGET
The target must be outside this Git worktree. A non-empty target requires
--confirm-existing; existing files are never removed.
EOF
}

canonical_target() {
  target=$1
  case "$target" in
    /*) ;;
    *) target="$(pwd -P)/$target" ;;
  esac
  case "/$target/" in
    */../*|*/./*) die "target must not contain . or ..: $1" ;;
  esac

  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -d "$target" ] || die "target is not a directory: $target"
    (CDPATH= cd "$target" && pwd -P)
    return
  fi

  parent=$(dirname "$target")
  leaf=$(basename "$target")
  while [ ! -d "$parent" ]; do
    next=$(dirname "$parent")
    [ "$next" != "$parent" ] || die "target has no existing parent: $target"
    leaf="$(basename "$parent")/$leaf"
    parent=$next
  done
  printf '%s/%s\n' "$(CDPATH= cd "$parent" && pwd -P)" "$leaf"
}

require_external_target() {
  ancestor=$1
  while [ ! -d "$ancestor" ]; do
    next=$(dirname "$ancestor")
    [ "$next" != "$ancestor" ] || die "target has no existing ancestor: $1"
    ancestor=$next
  done
  for location in "$ancestor" "$(dirname "$ancestor")"; do
    if [ "$(git -C "$location" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
      die "target must be outside a Git worktree: $1"
    fi
  done
}

require_regular_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || die "required regular file missing: $1"
}

require_safe_target_file() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || require_regular_file "$1"
}

validate_archive() {
  archive=$1
  members="$archive.members"
  details="$archive.details"
  tar -tjf "$archive" >"$members" || die "cannot list archive: $archive"
  tar -tvjf "$archive" >"$details" || die "cannot inspect archive: $archive"

  unsafe=0
  while IFS= read -r member || [ -n "$member" ]; do
    case "$member" in
      /*|..|../*|*/../*|*/..) unsafe=1 ;;
    esac
  done <"$members"
  while IFS= read -r detail || [ -n "$detail" ]; do
    case "$detail" in
      l*|h*) unsafe=1 ;;
    esac
  done <"$details"
  rm -f "$members" "$details"
  [ "$unsafe" -eq 0 ] || die "archive contains unsafe path or link entry"
}

verify_model() {
  dir=$1
  [ -d "$dir" ] || die "model directory missing: $dir"

  for file in $REQUIRED_FILES; do
    require_regular_file "$dir/$file"
  done
  require_regular_file "$dir/manifest.sha256"

  awk 'END { exit NR == 4 ? 0 : 1 }' "$dir/manifest.sha256" ||
    die "manifest.sha256 must contain exactly the required model files"
  for file in $REQUIRED_FILES; do
    awk -v file="$file" '$1 ~ /^[[:xdigit:]]{64}$/ && $2 == file { found = 1 } END { exit found ? 0 : 1 }' "$dir/manifest.sha256" ||
      die "manifest.sha256 missing checksum for $file"
  done
  (cd "$dir" && shasum -a 256 -c manifest.sha256 >/dev/null 2>&1) ||
    die "checksum verification failed in $dir"
}

write_manifest() {
  dir=$1
  require_safe_target_file "$dir/manifest.sha256"
  (cd "$dir" && shasum -a 256 $REQUIRED_FILES >manifest.sha256)
}

bootstrap_model() {
  target=$1
  confirm_existing=$2

  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -d "$target" ] || die "target is not a directory: $target"
    if [ "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ] && [ "$confirm_existing" -ne 1 ]; then
      die "target is non-empty; rerun with --confirm-existing: $target"
    fi
  fi
  for file in $REQUIRED_FILES manifest.sha256; do
    require_safe_target_file "$target/$file"
  done

  parent=$(dirname "$target")
  mkdir -p "$parent"
  tmp_dir=$(mktemp -d "$parent/.paraformer-bootstrap.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
  archive="$tmp_dir/$MODEL_ARCHIVE"
  stage="$tmp_dir/stage"
  mkdir -p "$stage"

  curl -fL "$MODEL_URL" -o "$archive"
  validate_archive "$archive"
  tar -xjf "$archive" -C "$stage"

  source_dir="$stage/$MODEL_NAME"
  [ -d "$source_dir" ] || die "archive did not contain expected directory: $MODEL_NAME"
  for file in $REQUIRED_FILES; do
    require_regular_file "$source_dir/$file"
  done

  write_manifest "$source_dir"
  verify_model "$source_dir"
  mkdir -p "$target"
  for file in $REQUIRED_FILES; do
    cp "$source_dir/$file" "$target/$file"
  done
  cp "$source_dir/manifest.sha256" "$target/manifest.sha256"
  verify_model "$target"
  echo "Bootstrapped Streaming Paraformer model at $target"
}

self_check() {
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/paraformer-bootstrap-test.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
  model_dir="$tmp_dir/model"
  mkdir -p "$model_dir"

  for file in $REQUIRED_FILES; do
    echo "$file" >"$model_dir/$file"
  done
  (cd "$model_dir" && shasum -a 256 $REQUIRED_FILES >manifest.sha256)
  sh "$0" --verify-only --target "$model_dir" >/dev/null

  rm "$model_dir/tokens.txt"
  if sh "$0" --verify-only --target "$model_dir" >/dev/null 2>&1; then
    die "self-check expected missing tokens.txt to fail"
  fi
  echo tokens >"$model_dir/tokens.txt"
  (cd "$model_dir" && shasum -a 256 $REQUIRED_FILES >manifest.sha256)

  echo changed >"$model_dir/encoder.int8.onnx"
  if sh "$0" --verify-only --target "$model_dir" >/dev/null 2>&1; then
    die "self-check expected checksum mismatch to fail"
  fi

  malicious_root="$tmp_dir/malicious"
  malicious_model="$malicious_root/$MODEL_NAME"
  mkdir -p "$malicious_model"
  echo encoder >"$malicious_model/encoder-target"
  ln -s encoder-target "$malicious_model/encoder.int8.onnx"
  for file in decoder.int8.onnx tokens.txt LICENSE; do
    echo "$file" >"$malicious_model/$file"
  done
  malicious_archive="$tmp_dir/malicious.tar.bz2"
  tar -cjf "$malicious_archive" -C "$malicious_root" "$MODEL_NAME"
  fake_bin="$tmp_dir/fake-bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/bin/sh' 'set -eu' 'while [ "$#" -gt 0 ]; do' '  if [ "$1" = "-o" ]; then' '    cp "$PARAFORMER_TEST_ARCHIVE" "$2"' '    exit 0' '  fi' '  shift' 'done' 'exit 2' >"$fake_bin/curl"
  chmod +x "$fake_bin/curl"
  if PARAFORMER_TEST_ARCHIVE="$malicious_archive" PATH="$fake_bin:$PATH" sh "$0" --target "$tmp_dir/malicious-target" >/dev/null 2>&1; then
    die "self-check expected malicious link archive to fail"
  fi

  other_repo="$tmp_dir/other-repo"
  git init -q "$other_repo"
  other_model="$other_repo/model"
  mkdir -p "$other_model"
  for file in $REQUIRED_FILES; do
    echo "$file" >"$other_model/$file"
  done
  (cd "$other_model" && shasum -a 256 $REQUIRED_FILES >manifest.sha256)
  if sh "$0" --verify-only --target "$other_model" >/dev/null 2>&1; then
    die "self-check expected target in another Git worktree to fail"
  fi

  safe_root="$tmp_dir/safe"
  safe_model="$safe_root/$MODEL_NAME"
  mkdir -p "$safe_model"
  for file in $REQUIRED_FILES; do
    echo "$file" >"$safe_model/$file"
  done
  safe_archive="$tmp_dir/safe.tar.bz2"
  tar -cjf "$safe_archive" -C "$safe_root" "$MODEL_NAME"
  nested_target="$other_repo/missing-parent/model"
  if PARAFORMER_TEST_ARCHIVE="$safe_archive" PATH="$fake_bin:$PATH" sh "$0" --target "$nested_target" >/dev/null 2>&1; then
    die "self-check expected nested target in another Git worktree to fail"
  fi
  [ ! -e "$other_repo/missing-parent" ] || die "self-check expected nested Git target to remain untouched"

  non_empty="$tmp_dir/non-empty"
  mkdir -p "$non_empty"
  echo stale >"$non_empty/stale"
  if sh "$0" --target "$non_empty" >/dev/null 2>&1; then
    die "self-check expected non-empty target to require confirmation"
  fi
  [ "$(cat "$non_empty/stale")" = "stale" ] || die "self-check expected existing file to remain untouched"

  if sh "$0" --target "$REPO_ROOT/probes/paraformer/disallowed" >/dev/null 2>&1; then
    die "self-check expected Git-worktree target to fail"
  fi
  [ ! -e "$REPO_ROOT/probes/paraformer/disallowed" ] || die "self-check expected Git worktree to remain untouched"

  echo "self-check passed"
}

mode="bootstrap"
target="$DEFAULT_TARGET"
confirm_existing=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --self-check)
      self_check
      exit 0
      ;;
    --verify-only)
      mode="verify"
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || die "--target requires a directory"
      target=$2
      shift 2
      ;;
    --confirm-existing)
      confirm_existing=1
      shift
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

target=$(canonical_target "$target")
require_external_target "$target"

case "$mode" in
  verify)
    verify_model "$target"
    ;;
  bootstrap)
    bootstrap_model "$target" "$confirm_existing"
    ;;
esac

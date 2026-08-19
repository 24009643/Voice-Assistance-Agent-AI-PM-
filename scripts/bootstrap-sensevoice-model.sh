#!/bin/sh
set -eu

MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
MODEL_ARCHIVE="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2"
MODEL_SOURCE_DIR="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
DEFAULT_TARGET="artifacts/models/sensevoice-2024-07-17-int8"
REQUIRED_FILES="model.int8.onnx tokens.txt LICENSE"

err() {
  echo "bootstrap-sensevoice-model: $*" >&2
}

die() {
  err "$*"
  exit 1
}

fail() {
  err "$*"
  return 1
}

usage() {
  cat <<EOF
Usage:
  scripts/bootstrap-sensevoice-model.sh [--target <dir>]
  scripts/bootstrap-sensevoice-model.sh --verify-only [--target <dir>]
  scripts/bootstrap-sensevoice-model.sh --self-check

Downloads and verifies the pinned SenseVoiceSmall int8 model.
Default target: $DEFAULT_TARGET
EOF
}

verify_model() {
  dir=$1

  [ -d "$dir" ] || {
    fail "model directory missing: $dir"
    return 1
  }

  for file in $REQUIRED_FILES; do
    [ -f "$dir/$file" ] || {
      fail "required file missing: $dir/$file"
      return 1
    }
  done

  [ -f "$dir/manifest.sha256" ] || {
    fail "manifest.sha256 missing: $dir/manifest.sha256"
    return 1
  }

  awk 'END { exit NR == 3 ? 0 : 1 }' "$dir/manifest.sha256" || {
    fail "manifest.sha256 must contain exactly model.int8.onnx, tokens.txt, and LICENSE"
    return 1
  }

  for file in $REQUIRED_FILES; do
    awk -v file="$file" '$1 ~ /^[[:xdigit:]]{64}$/ && $2 == file { found = 1 } END { exit found ? 0 : 1 }' "$dir/manifest.sha256" || {
      fail "manifest.sha256 missing checksum for $file"
      return 1
    }
  done

  (cd "$dir" && shasum -a 256 -c manifest.sha256 >/dev/null 2>&1) || {
    fail "checksum verification failed in $dir"
    return 1
  }
}

write_manifest() {
  dir=$1
  (cd "$dir" && shasum -a 256 model.int8.onnx tokens.txt LICENSE >manifest.sha256)
}

bootstrap_model() {
  target=$1

  if [ -e "$target" ] || [ -L "$target" ]; then
    if verify_model "$target"; then
      echo "Verified existing SenseVoice model at $target"
      return 0
    fi
    die "existing target is invalid; remove or repair it before bootstrapping: $target"
  fi

  models_root=$(dirname "$target")
  mkdir -p "$models_root"
  tmp_dir=$(mktemp -d "$models_root/.sensevoice-bootstrap.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

  archive="$tmp_dir/$MODEL_ARCHIVE"
  stage="$tmp_dir/stage"
  mkdir -p "$stage"

  curl -fL "$MODEL_URL" -o "$archive"
  tar -xjf "$archive" -C "$stage"

  source_dir="$stage/$MODEL_SOURCE_DIR"
  [ -d "$source_dir" ] || die "archive did not contain expected directory: $MODEL_SOURCE_DIR"

  for file in $REQUIRED_FILES; do
    [ -f "$source_dir/$file" ] || die "archive missing required file: $file"
  done

  write_manifest "$source_dir"
  verify_model "$source_dir" || die "downloaded model verification failed"
  mv "$source_dir" "$target"
  echo "Bootstrapped SenseVoice model at $target"
}

self_check() {
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/sensevoice-bootstrap-test.XXXXXX")
  trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

  model_dir="$tmp_dir/model"
  mkdir -p "$model_dir"
  echo model >"$model_dir/model.int8.onnx"
  echo tokens >"$model_dir/tokens.txt"
  echo license >"$model_dir/LICENSE"
  (cd "$model_dir" && shasum -a 256 model.int8.onnx tokens.txt LICENSE >manifest.sha256)

  sh "$0" --verify-only --target "$model_dir" >/dev/null

  rm "$model_dir/tokens.txt"
  if sh "$0" --verify-only --target "$model_dir" >/dev/null 2>&1; then
    die "self-check expected missing tokens.txt to fail"
  fi
  echo tokens >"$model_dir/tokens.txt"
  (cd "$model_dir" && shasum -a 256 model.int8.onnx tokens.txt LICENSE >manifest.sha256)

  echo changed >"$model_dir/model.int8.onnx"
  if sh "$0" --verify-only --target "$model_dir" >/dev/null 2>&1; then
    die "self-check expected checksum mismatch to fail"
  fi

  echo model >"$model_dir/model.int8.onnx"
  (cd "$model_dir" && shasum -a 256 model.int8.onnx tokens.txt >manifest.sha256)
  if sh "$0" --verify-only --target "$model_dir" >/dev/null 2>&1; then
    die "self-check expected incomplete manifest to fail"
  fi

  invalid_dir="$tmp_dir/invalid-existing"
  mkdir -p "$invalid_dir"
  echo stale >"$invalid_dir/model.int8.onnx"
  if sh "$0" --target "$invalid_dir" >/dev/null 2>&1; then
    die "self-check expected invalid existing target to fail"
  fi
  if [ "$(cat "$invalid_dir/model.int8.onnx")" != "stale" ]; then
    die "self-check expected invalid existing target to remain untouched"
  fi

  broken_link="$tmp_dir/broken-target"
  missing_target="$tmp_dir/missing-target"
  ln -s "$missing_target" "$broken_link"
  if sh "$0" --target "$broken_link" >/dev/null 2>&1; then
    die "self-check expected dangling symlink target to fail"
  fi
  if [ ! -L "$broken_link" ]; then
    die "self-check expected dangling symlink to remain a symlink"
  fi
  if [ "$(readlink "$broken_link")" != "$missing_target" ]; then
    die "self-check expected dangling symlink destination to remain untouched"
  fi

  echo "self-check passed"
}

mode="bootstrap"
target="$DEFAULT_TARGET"

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
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$mode" in
  verify)
    verify_model "$target"
    ;;
  bootstrap)
    bootstrap_model "$target"
    ;;
esac

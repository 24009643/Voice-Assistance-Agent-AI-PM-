#!/bin/sh
set -eu

write_manifest() {
  audio_path=$1
  manifest_path=$2
  python3 - "$audio_path" "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

audio = Path(sys.argv[1]).resolve(strict=True)
manifest = Path(sys.argv[2])
manifest.write_text(
    json.dumps({"id": "retained-audio", "path": str(audio), "language": "auto"}, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY
}

self_check() {
  probe_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tsb-retained-audio-check.XXXXXX")
  trap 'rm -rf "$probe_tmp_dir"' EXIT HUP INT TERM
  audio_path="$probe_tmp_dir/audio with spaces.wav"
  manifest_path="$probe_tmp_dir/manifest.jsonl"
  : >"$audio_path"
  write_manifest "$audio_path" "$manifest_path"
  python3 - "$manifest_path" "$audio_path" <<'PY'
import json
import sys
from pathlib import Path

row = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert row == {"id": "retained-audio", "path": str(Path(sys.argv[2]).resolve()), "language": "auto"}
PY
  echo "self-check passed"
}

if [ "$#" -eq 1 ] && [ "$1" = "--self-check" ]; then
  self_check
  exit 0
fi

if [ "$#" -ne 2 ]; then
  echo "Usage: scripts/probe-retained-audio.sh <wav> <model-dir>" >&2
  exit 2
fi

audio_path=$1
model_dir=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname "$script_dir")
probe_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tsb-retained-audio-probe.XXXXXX")
trap 'rm -rf "$probe_tmp_dir"' EXIT HUP INT TERM
manifest_path="$probe_tmp_dir/manifest.jsonl"
write_manifest "$audio_path" "$manifest_path"

swift run --package-path "$repo_root/probes/sensevoice" SenseVoiceProbe \
  --model-dir "$model_dir" \
  --manifest "$manifest_path"

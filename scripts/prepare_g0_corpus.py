#!/usr/bin/env python3
"""Prepare a small, reproducible, non-committed G0 speech corpus."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import itertools
import json
import os
import re
import shutil
import subprocess
import tarfile
import urllib.parse
import urllib.request
import wave
from pathlib import Path, PurePosixPath


FLEURS = {
    "mandarin": "cmn_hans_cn",
    "cantonese": "yue_hant_hk",
}
HF_RESOLVE = "https://huggingface.co/datasets/{repo}/resolve/main/{path}?download=true"
HF_ROWS = "https://datasets-server.huggingface.co/rows"


def open_url(url: str):
    return urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "TSB-G0-corpus/0.1"}),
        timeout=120,
    )


def read_text(url: str) -> str:
    with open_url(url) as response:
        return response.read().decode("utf-8")


def fleurs_references(tsv_text: str) -> dict[str, str]:
    references = {}
    for row in csv.reader(io.StringIO(tsv_text), delimiter="\t"):
        if len(row) >= 3:
            references[row[1]] = row[2]
    return references


def extract_fleurs_samples(fileobj, tsv_text: str, destination: Path, count: int) -> list[dict]:
    references = fleurs_references(tsv_text)
    destination.mkdir(parents=True, exist_ok=True)
    selected = []
    with tarfile.open(fileobj=fileobj, mode="r|gz") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if not member.isfile() or path.is_absolute() or ".." in path.parts:
                continue
            filename = path.name
            if filename not in references or Path(filename).suffix.lower() != ".wav":
                continue
            source = archive.extractfile(member)
            if source is None:
                continue
            output = destination / filename
            with output.open("wb") as target:
                shutil.copyfileobj(source, target)
            selected.append({"filename": filename, "reference": references[filename], "path": output})
            if len(selected) == count:
                break
    if len(selected) != count:
        raise RuntimeError(f"FLEURS archive yielded {len(selected)} of {count} requested samples")
    return selected


def select_ascend_mixed(rows: list[dict], count: int) -> list[dict]:
    selected = []
    for wrapped in rows:
        row = wrapped.get("row", {})
        if row.get("language") != "mixed":
            continue
        identifier = str(row.get("id", ""))
        if not re.fullmatch(r"[A-Za-z0-9._-]+", identifier):
            raise RuntimeError(f"unsafe ASCEND id: {identifier!r}")
        audio = row.get("audio")
        if not isinstance(audio, list) or not audio or not isinstance(audio[0], dict) or not audio[0].get("src"):
            raise RuntimeError("ASCEND viewer audio field changed; expected [{src: ...}]")
        selected.append(row)
        if len(selected) == count:
            break
    return selected


def download(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    with open_url(url) as response, temporary.open("wb") as target:
        shutil.copyfileobj(response, target)
    os.replace(temporary, destination)


def normalize_wav(path: Path) -> None:
    temporary = path.with_suffix(".normalized.wav")
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(path),
         "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(temporary)],
        check=True,
    )
    os.replace(temporary, path)


def wav_duration(path: Path) -> float:
    with wave.open(str(path), "rb") as audio:
        return audio.getnframes() / audio.getframerate()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare_fleurs(output: Path, kind: str, count: int) -> list[dict]:
    config = FLEURS[kind]
    base = f"data/{config}"
    tsv_url = HF_RESOLVE.format(repo="google/fleurs", path=f"{base}/dev.tsv")
    archive_url = HF_RESOLVE.format(repo="google/fleurs", path=f"{base}/audio/dev.tar.gz")
    tsv = read_text(tsv_url)
    with open_url(archive_url) as response:
        rows = extract_fleurs_samples(response, tsv, output / kind, count)
    for row in rows:
        normalize_wav(row["path"])
        row.update({
            "id": Path(row["filename"]).stem,
            "language": kind,
            "dataset": "google/fleurs",
            "split": "dev",
            "license": "CC-BY-4.0",
            "source": archive_url,
            "evaluation_scope": "accuracy_and_performance",
        })
    return rows


def ascend_page(offset: int, length: int = 100) -> dict:
    query = urllib.parse.urlencode({
        "dataset": "CAiRE/ASCEND", "config": "main", "split": "test",
        "offset": offset, "length": length,
    })
    with open_url(f"{HF_ROWS}?{query}") as response:
        return json.load(response)


def prepare_ascend(output: Path, count: int) -> list[dict]:
    selected = []
    offset = 0
    while len(selected) < count:
        page = ascend_page(offset)
        selected.extend(select_ascend_mixed(page.get("rows", []), count - len(selected)))
        offset += len(page.get("rows", []))
        if not page.get("rows") or offset >= page.get("num_rows_total", 0):
            break
    if len(selected) != count:
        raise RuntimeError(f"ASCEND yielded {len(selected)} of {count} requested mixed samples")

    rows = []
    for row in selected:
        path = output / "mixed" / f"ascend-{row['id']}.wav"
        download(row["audio"][0]["src"], path)
        normalize_wav(path)
        rows.append({
            "id": row["id"],
            "filename": path.name,
            "path": path,
            "reference": row["transcription"],
            "language": "mixed",
            "dataset": "CAiRE/ASCEND",
            "split": "test",
            "license": "CC-BY-SA-4.0",
            "source": "https://huggingface.co/datasets/CAiRE/ASCEND",
            "evaluation_scope": "accuracy_and_performance",
        })
    return rows


def create_composite(output: Path, rows: list[dict], seconds: int) -> dict:
    silence = output / "_silence-500ms.wav"
    if not silence.exists():
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
             "-i", "anullsrc=r=16000:cl=mono", "-t", "0.5", "-c:a", "pcm_s16le", str(silence)],
            check=True,
        )
    inputs = []
    duration = 0.0
    for row in itertools.cycle(rows):
        inputs.extend([row["path"], silence])
        duration += wav_duration(row["path"]) + 0.5
        if duration >= seconds + 1:
            break
    list_file = output / f"_concat-{seconds}.txt"
    list_file.write_text("".join(f"file '{path}'\n" for path in inputs), encoding="utf-8")
    target = output / "long" / f"public-composite-{seconds}s.wav"
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
         "-i", str(list_file), "-t", str(seconds), "-ar", "16000", "-ac", "1",
         "-c:a", "pcm_s16le", str(target)],
        check=True,
    )
    list_file.unlink()
    return {
        "id": f"public-composite-{seconds}s",
        "filename": target.name,
        "path": target,
        "language": "multi",
        "dataset": "derived from FLEURS and ASCEND",
        "split": "derived",
        "license": "CC-BY-SA-4.0",
        "source": "local deterministic concatenation",
        "reference": "stability/RTF only; not a natural long-dictation accuracy sample",
        "evaluation_scope": "stability_only",
        "source_datasets": sorted({row["dataset"] for row in rows}),
        "source_licenses": sorted({row["license"] for row in rows}),
    }


def serializable(row: dict) -> dict:
    result = dict(row)
    result["path"] = str(result["path"])
    result["duration_seconds"] = round(wav_duration(row["path"]), 3)
    result["sha256"] = sha256(row["path"])
    return result


def ensure_output_directory(output: Path, force: bool) -> None:
    if output.exists() and any(output.iterdir()) and not force:
        raise RuntimeError(f"output already contains files: {output}; pass --force to overwrite")
    output.mkdir(parents=True, exist_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("artifacts/corpora/g0"))
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--force", action="store_true", help="allow overwriting files inside --output")
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    if shutil.which("ffmpeg") is None:
        parser.error("ffmpeg is required")

    output = args.output.resolve()
    ensure_output_directory(output, args.force)
    rows = prepare_fleurs(output, "mandarin", args.samples)
    rows += prepare_fleurs(output, "cantonese", args.samples)
    rows += prepare_ascend(output, args.samples)
    rows += [create_composite(output, rows, seconds) for seconds in (180, 240, 300, 600)]
    manifest = output / "manifest.jsonl"
    manifest.write_text(
        "".join(json.dumps(serializable(row), ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )
    print(f"prepared {len(rows)} files; manifest: {manifest}")


if __name__ == "__main__":
    main()

import io
import sys
import tarfile
import tempfile
import unittest
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import prepare_g0_corpus as corpus


class PrepareG0CorpusTests(unittest.TestCase):
    def test_extract_fleurs_rejects_traversal_and_keeps_reference(self):
        tsv = "1\tgood.wav\t真实文本\tignored\tignored\t16000\tFEMALE\n"
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w:gz") as tar:
            for name in ("dev/good.wav", "../escape.wav"):
                data = b"RIFF-audio"
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
        archive.seek(0)

        with tempfile.TemporaryDirectory() as directory:
            rows = corpus.extract_fleurs_samples(archive, tsv, Path(directory), 1)
            self.assertEqual(rows[0]["reference"], "真实文本")
            self.assertEqual(rows[0]["filename"], "good.wav")
            self.assertFalse((Path(directory).parent / "escape.wav").exists())

    def test_select_ascend_keeps_only_actual_code_switching_rows(self):
        rows = [
            {"row": {"id": "1", "language": "zh", "transcription": "你好", "audio": [{"src": "zh.wav"}]}},
            {"row": {"id": "2", "language": "mixed", "transcription": "这个 feature", "audio": [{"src": "mixed.wav"}]}},
        ]
        self.assertEqual([row["id"] for row in corpus.select_ascend_mixed(rows, 5)], ["2"])

    def test_select_ascend_rejects_unsafe_remote_id_and_changed_audio_shape(self):
        unsafe = [{"row": {"id": "../bad", "language": "mixed", "transcription": "中 English", "audio": [{"src": "https://example.test/a.wav"}]}}]
        changed = [{"row": {"id": "3", "language": "mixed", "transcription": "中 English", "audio": {"path": "a.wav"}}}]
        with self.assertRaisesRegex(RuntimeError, "unsafe ASCEND id"):
            corpus.select_ascend_mixed(unsafe, 1)
        with self.assertRaisesRegex(RuntimeError, "audio field"):
            corpus.select_ascend_mixed(changed, 1)

    def test_composite_declares_share_alike_and_stability_only_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.wav"
            with wave.open(str(source), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(16_000)
                audio.writeframes(b"\0\0" * 16_000)
            row = {"id": "source", "path": source, "dataset": "google/fleurs", "license": "CC-BY-4.0"}
            composite = corpus.create_composite(root, [row], 1)
            self.assertEqual(composite["license"], "CC-BY-SA-4.0")
            self.assertEqual(composite["evaluation_scope"], "stability_only")
            self.assertEqual(composite["source_datasets"], ["google/fleurs"])

    def test_existing_output_requires_explicit_force(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "existing.wav").write_bytes(b"audio")
            with self.assertRaisesRegex(RuntimeError, "already contains files"):
                corpus.ensure_output_directory(output, force=False)
            corpus.ensure_output_directory(output, force=True)


if __name__ == "__main__":
    unittest.main()

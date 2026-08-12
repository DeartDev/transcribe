import os
import tempfile
import unittest
from pathlib import Path

from src.transcribir import (
    SegmentData,
    formats_to_write,
    render_srt,
    render_txt,
    render_vtt,
    safe_output_stem,
    seconds_to_hms,
    seconds_to_subtitle_time,
    validate_input,
)


class FormattingTests(unittest.TestCase):
    def test_hms_format(self):
        self.assertEqual(seconds_to_hms(4.9), "00:00:04")
        self.assertEqual(seconds_to_hms(3661.2), "01:01:01")

    def test_subtitle_format(self):
        self.assertEqual(seconds_to_subtitle_time(4.567, ","), "00:00:04,567")
        self.assertEqual(seconds_to_subtitle_time(65.001, "."), "00:01:05.001")

    def test_txt_preserves_literal_text(self):
        content = render_txt([SegmentData(4, 9, " eh... buenos días ")])
        self.assertEqual(content, "[00:00:04 - 00:00:09] eh... buenos días\n")

    def test_srt_and_vtt(self):
        segs = [SegmentData(1.2, 2.5, "hola")]
        self.assertIn("00:00:01,200 --> 00:00:02,500", render_srt(segs))
        self.assertTrue(render_vtt(segs).startswith("WEBVTT\n\n"))
        self.assertIn("00:00:01.200 --> 00:00:02.500", render_vtt(segs))

    def test_formats_all(self):
        self.assertEqual(formats_to_write("all"), ["txt", "srt", "vtt"])
        self.assertEqual(formats_to_write("txt"), ["txt"])

    def test_unicode_stem(self):
        self.assertEqual(safe_output_stem(Path("reunión número 1.mp3")), "reunión número 1")


class ValidationTests(unittest.TestCase):
    def test_accepts_regular_file_inside_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "audios"
            root.mkdir()
            audio = root / "áudio prueba.mp3"
            audio.write_bytes(b"x")
            self.assertEqual(validate_input(audio, root), audio.resolve())

    def test_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "audios"
            other = Path(tmp) / "otro.mp3"
            root.mkdir()
            other.write_bytes(b"x")
            with self.assertRaises(ValueError):
                validate_input(other, root)

    def test_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "audios"
            root.mkdir()
            target = root / "real.mp3"
            link = root / "link.mp3"
            target.write_bytes(b"x")
            link.symlink_to(target)
            with self.assertRaises(ValueError):
                validate_input(link, root)


if __name__ == "__main__":
    unittest.main()

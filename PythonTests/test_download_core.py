import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import download_core as core

def video(height=720, ident="v", **extra):
    return dict(format_id=ident, ext="mp4", url="https://media.example/video",
                protocol="https", vcodec="avc1.64001F", acodec="none",
                height=height, **extra)
def audio(rate=128, ident="a", **extra):
    return dict(format_id=ident, ext="m4a", url="https://media.example/audio",
                protocol="https", vcodec="none", acodec="mp4a.40.2", abr=rate, **extra)

class SelectionTests(unittest.TestCase):
    def test_resolution_and_audio_cap(self):
        v, a, fallback = core.select_formats({"formats": [video(1080), video(720), audio(256), audio(128)]}, 720, 128)
        self.assertEqual(v["height"], 720)
        self.assertEqual(a["abr"], 128)
        self.assertFalse(fallback)

    def test_lowest_audio_fallback(self):
        _, a, fallback = core.select_formats({"formats": [video(), audio(128), audio(48)]}, 720, 32)
        self.assertEqual(a["abr"], 48)
        self.assertTrue(fallback)

    def test_progressive_video_needs_no_second_track(self):
        v = video()
        v["acodec"] = "mp4a.40.2"
        selected, a, fallback = core.select_formats({"formats": [v]}, 720, 128)
        self.assertIs(selected, v)
        self.assertIsNone(a)

    def test_separate_track_preferred_at_same_height(self):
        v = video(720, "combined")
        v["acodec"] = "mp4a.40.2"
        selected, _, _ = core.select_formats({"formats": [v, video(720, "separate"), audio()]}, 720, 128)
        self.assertEqual(selected["format_id"], "separate")

    def test_above_cap_is_rejected(self):
        with self.assertRaises(core.FormatUnavailable):
            core.select_formats({"formats": [video(1080), audio()]}, 360, 128)

    def test_drm_format_is_rejected(self):
        with self.assertRaises(core.FormatUnavailable):
            core.select_formats({"formats": [video(has_drm=True), audio()]}, 720, 128)

    def test_fragmented_format_is_not_treated_as_direct_file(self):
        v = video()
        v["protocol"] = "m3u8_native"
        with self.assertRaises(core.FormatUnavailable):
            core.select_formats({"formats": [v, audio()]}, 720, 128)

    def test_unsupported_codec_is_rejected(self):
        v = video()
        v["vcodec"] = "vp9"
        with self.assertRaises(core.FormatUnavailable):
            core.select_formats({"formats": [v, audio()]}, 720, 128)

    def test_optional_av1_support(self):
        v = video()
        v["vcodec"] = "av01.0.08M.08"
        selected, _, _ = core.select_formats({"formats": [v, audio()]}, 720, 128, ["av01"])
        self.assertEqual(selected["vcodec"], v["vcodec"])

    def test_missing_aac_is_rejected(self):
        with self.assertRaises(core.FormatUnavailable):
            core.select_formats({"formats": [video()]}, 720, 128)

class WorkerTests(unittest.TestCase):
    def test_error_classification(self):
        self.assertEqual(core.error_code("Sign in to confirm you're not a bot"), "verification_required")
        self.assertEqual(core.error_code("Not available in your country"), "region_restricted")
        self.assertEqual(core.error_code("Other error"), "extractor_error")

    def test_cancellation_precedes_network_request(self):
        with tempfile.TemporaryDirectory() as folder:
            cancel = Path(folder) / "cancel"
            cancel.touch()
            result = json.loads(core.run_json(json.dumps({"cancel_file": str(cancel)})))
            self.assertEqual(result["error"]["code"], "cancelled")

    def test_non_youtube_input_is_rejected(self):
        result = json.loads(core.run_json(json.dumps({
            "url": "https://youtube.com.evil.example/watch?v=id", "directory": "/unused"
        })))
        self.assertFalse(result["ok"])
        self.assertIn("YouTube", result["error"]["message"])

    def test_atomic_progress_output(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "progress.json"
            core._write_progress(target, {"downloaded_bytes": 123, "stage": "video"})
            self.assertEqual(json.loads(target.read_text())["downloaded_bytes"], 123)
            self.assertFalse(target.with_suffix(".writing").exists())

    def test_downloads_selected_tracks_without_external_merger(self):
        calls = []
        class FakeDownloader:
            def __init__(self, options):
                self.params = options.copy()
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def extract_info(self, url, download):
                return {"id": "_pJQFrTU4aQ", "title": "測試", "formats": [video(360), audio(48)],
                        "requested_formats": ["must be removed"]}
            def add_progress_hook(self, hook):
                self.hook = hook
            def process_info(self, item):
                self.assert_valid(item)
                file = Path(self.params["outtmpl"]["default"])
                file.write_bytes(b"complete-track")
                self.hook({"status": "finished", "downloaded_bytes": file.stat().st_size,
                           "total_bytes": file.stat().st_size})
                calls.append(item["format_id"])
            def assert_valid(self, item):
                assert "requested_formats" not in item
                assert self.params["postprocessors"] == []
                assert self.params["fixup"] == "never"
        with tempfile.TemporaryDirectory() as folder, patch("yt_dlp.YoutubeDL", FakeDownloader):
            request = {"url": "https://youtu.be/_pJQFrTU4aQ", "directory": folder,
                       "max_height": 360, "audio_kbps": 64,
                       "progress_file": str(Path(folder) / "progress.json")}
            result = core.download(request)
            self.assertTrue(result["ok"])
            self.assertEqual(calls, ["v", "a"])
            self.assertTrue(Path(result["video"]).exists())
            self.assertTrue(Path(result["audio"]).exists())
            progress = json.loads(Path(request["progress_file"]).read_text())
            self.assertEqual(progress["part_index"], 1)
            self.assertEqual(progress["sizes"], [14, 14])

class HTTPTransferTests(unittest.TestCase):
    """Real yt-dlp HTTP downloader; only YouTube metadata is stubbed."""
    def test_real_two_track_download_and_progress(self):
        import functools
        import http.server
        import threading
        from yt_dlp import YoutubeDL
        with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as output:
            data = {"video.mp4": b"video" * 30000, "audio.m4a": b"audio" * 12000}
            for name, content in data.items():
                (Path(source) / name).write_bytes(content)
            class QuietHandler(http.server.SimpleHTTPRequestHandler):
                def log_message(self, *args):
                    pass
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
                functools.partial(QuietHandler, directory=source))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                v, a = video(360), audio(48)
                for fmt, name in ((v, "video.mp4"), (a, "audio.m4a")):
                    fmt.update(url=f"http://127.0.0.1:{server.server_port}/{name}",
                               protocol="http", filesize=len(data[name]))
                info = {"id": "test", "title": "HTTP fixture", "extractor": "youtube",
                        "extractor_key": "Youtube", "webpage_url": "https://youtu.be/_pJQFrTU4aQ",
                        "formats": [v, a]}
                request = {"url": info["webpage_url"], "directory": output,
                           "max_height": 360, "audio_kbps": 64,
                           "progress_file": str(Path(output) / "progress.json")}
                with patch.object(YoutubeDL, "extract_info", return_value=info):
                    reply = core.download(request)
                self.assertEqual(Path(reply["video"]).read_bytes(), data["video.mp4"])
                self.assertEqual(Path(reply["audio"]).read_bytes(), data["audio.m4a"])
                progress = json.loads(Path(request["progress_file"]).read_text())
                self.assertEqual(progress["sizes"], [150000, 60000])
                self.assertEqual(progress["downloaded_bytes"], 60000)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

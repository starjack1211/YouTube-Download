"""Real network acceptance tests. Failure remains failure; no skipped geo/bot cases."""
import json
import os
import tempfile
import unittest
from pathlib import Path
import download_core

@unittest.skipUnless(os.environ.get("RUN_LIVE_TESTS") == "1", "Run separately with RUN_LIVE_TESTS=1")
class LiveDownloadTests(unittest.TestCase):
    def check_video(self, video_id):
        with tempfile.TemporaryDirectory() as folder:
            reply = json.loads(download_core.run_json(json.dumps({
                "url": f"https://www.youtube.com/watch?v={video_id}",
                "directory": folder, "max_height": 360, "audio_kbps": 64,
                "progress_file": str(Path(folder) / "progress.json"),
            })))
            self.assertTrue(reply["ok"], reply.get("error"))
            self.assertGreater(Path(reply["video"]).stat().st_size, 1024)
            if reply.get("audio"):
                self.assertGreater(Path(reply["audio"]).stat().st_size, 1024)
    def test_reported_video(self):
        self.check_video("_pJQFrTU4aQ")
    def test_reference_video(self):
        self.check_video("aqz-KE-bpKQ")

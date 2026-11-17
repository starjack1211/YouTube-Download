"""Embedded yt-dlp backend. No subprocess, remote service, or ffmpeg required."""
from __future__ import annotations
import json
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

class Cancelled(Exception):
    pass

class FormatUnavailable(Exception):
    pass

def _compatible_video(fmt, allowed):
    codec = str(fmt.get("vcodec") or "").lower()
    return (fmt.get("ext") == "mp4" and codec not in ("none", "")
            and any(codec.startswith(prefix) for prefix in allowed))

def _direct(fmt):
    return (fmt.get("url") and str(fmt.get("protocol") or "https") in ("http", "https")
            and not fmt.get("has_drm"))

def select_formats(info, max_height, audio_kbps, allowed_codecs=None):
    allowed_codecs = allowed_codecs or ["avc1", "h264", "hvc1", "hev1"]
    formats = [f for f in info.get("formats", []) if _direct(f)]
    videos = [f for f in formats if _compatible_video(f, allowed_codecs)
              and 0 < (f.get("height") or 0) <= max_height]
    # Prefer a separate video track at the same resolution to honor audio settings.
    videos.sort(key=lambda f: (f.get("height") or 0,
                               f.get("acodec") in (None, "none"),
                               f.get("fps") or 0, f.get("tbr") or 0), reverse=True)
    if not videos:
        raise FormatUnavailable("找不到符合畫質上限的相容 MP4 影像。")
    video = videos[0]
    if video.get("acodec") not in (None, "none"):
        return video, None, False
    audios = [f for f in formats if f.get("vcodec") == "none"
              and str(f.get("acodec") or "").startswith(("mp4a", "aac"))
              and f.get("ext") in ("m4a", "mp4")]
    if not audios:
        raise FormatUnavailable("找不到可合併的 AAC 音軌。")
    def rate(f):
        return float(f.get("abr") or f.get("tbr") or 0)
    within = [f for f in audios if 0 < rate(f) <= audio_kbps]
    audio = max(within, key=rate) if within else min(audios, key=lambda f: rate(f) or float("inf"))
    return video, audio, not bool(within)

def error_code(message):
    lowered = message.lower()
    if "not a bot" in lowered or "confirm your age" in lowered or "sign in" in lowered:
        return "verification_required"
    if "your country" in lowered or "geo" in lowered or "not available in your region" in lowered:
        return "region_restricted"
    return "extractor_error"

def _cancelled(request):
    return bool(request.get("cancel_file") and Path(request["cancel_file"]).exists())

def _check_cancel(request):
    if _cancelled(request):
        raise Cancelled("已取消下載。")

def _write_progress(path, value):
    if not path:
        return
    target = Path(path)
    temporary = target.with_suffix(".writing")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, target)

def _register_javascript():
    try:
        import _iosjs
    except ImportError:
        return False
    import ios_jsc  # registers the in-process JavaScriptCore provider
    return True

def self_test():
    import ssl
    import certifi
    import yt_dlp.version
    import yt_dlp_ejs.yt.solver
    native = _register_javascript()
    result = {"python": sys.version.split()[0], "yt_dlp": yt_dlp.version.__version__,
              "ssl": ssl.OPENSSL_VERSION, "certificates": str(Path(certifi.where()).is_file()).lower(),
              "javascriptcore": str(native).lower()}
    if native:
        import _iosjs
        # Verify official EJS resources load in the native JS engine.
        response = json.loads(_iosjs.solve(json.dumps({
            "type": "player", "player": "(function(){var a=1;}).call(this);",
            "requests": [], "output_preprocessed": False,
        }), yt_dlp_ejs.yt.solver.lib(), yt_dlp_ejs.yt.solver.core()))
        if response.get("type") != "result":
            raise RuntimeError("Native EJS self-test failed")
        result["ejs"] = "loaded"
    return {"ok": True, "metadata": result}

def download(request):
    _check_cancel(request)
    import certifi
    from yt_dlp import YoutubeDL
    native = _register_javascript()
    link = request["url"]
    parsed = urlsplit(link)
    if parsed.scheme != "https" or parsed.hostname not in ("youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com", "music.youtube.com"):
        raise ValueError("只接受有效的 HTTPS YouTube 連結。")
    directory = Path(request["directory"]).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    progress_file = request.get("progress_file")
    warnings = []
    class Logger:
        def debug(self, message):
            pass
        def warning(self, message):
            warnings.append(str(message)[-2000:])
            del warnings[:-10]
        def error(self, message):
            warnings.append(str(message)[-2000:])
            del warnings[:-10]
    options = {
        "quiet": True, "no_warnings": True, "logger": Logger(),
        "noplaylist": True, "skip_download": True, "cachedir": False,
        "socket_timeout": 20, "retries": 2, "extractor_retries": 1,
        "ca_certs": certifi.where(), "nocheckcertificate": False,
        "fixup": "never", "postprocessors": [],
        "remote_components": [],
    }
    if not native:
        options["js_runtimes"] = {"node": {}}
    if native:
        options["js_runtimes"] = {}  # The registered provider uses JavaScriptCore, never a child process.
    _write_progress(progress_file, {"stage": "extracting", "sizes": []})
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(link, download=False)
        _check_cancel(request)
        video, audio, audio_fallback = select_formats(
            info, int(request["max_height"]), int(request["audio_kbps"]), request.get("video_codecs"))
        selected = [video] + ([audio] if audio else [])
        sizes = [int(f["filesize"]) if f.get("filesize") else None for f in selected]
        current = {"stage": "video", "part_index": 0, "part_count": len(selected),
                   "sizes": sizes, "downloaded_bytes": 0, "total_bytes": sizes[0]}
        last_written = 0.0
        def hook(event):
            nonlocal last_written
            _check_cancel(request)
            if event.get("status") not in ("downloading", "finished"):
                return
            now = time.monotonic()
            if now - last_written < 0.2 and event.get("status") != "finished":
                return
            last_written = now
            done = int(event.get("downloaded_bytes") or 0)
            expected = event.get("total_bytes")
            if expected:
                sizes[current["part_index"]] = int(expected)
            current.update(downloaded_bytes=done, total_bytes=expected,
                           speed=event.get("speed"), eta=event.get("eta"))
            _write_progress(progress_file, current)
        ydl.add_progress_hook(hook)
        ydl.params["skip_download"] = False
        paths = []
        for index, fmt in enumerate(selected):
            _check_cancel(request)
            stage = "video" if index == 0 else "audio"
            file = directory / ("video.mp4" if index == 0 else "audio.m4a")
            current.update(stage=stage, part_index=index, downloaded_bytes=0, total_bytes=sizes[index])
            _write_progress(progress_file, current)
            # process_info downloads one selected track. No requested_formats -> no external merger.
            item = {k: v for k, v in info.items() if k not in
                    ("formats", "requested_formats", "requested_downloads", "entries")}
            item.update(fmt)
            item.pop("requested_formats", None)
            item.pop("requested_downloads", None)
            ydl.params["outtmpl"] = {"default": str(file)}
            ydl.process_info(item)
            _check_cancel(request)
            if not file.is_file() or file.stat().st_size <= 0:
                raise RuntimeError("yt-dlp 未產生完整的下載檔案。")
            sizes[index] = file.stat().st_size
            current.update(downloaded_bytes=sizes[index], total_bytes=sizes[index])
            _write_progress(progress_file, current)
            paths.append(str(file))
        abr = float(audio.get("abr") or audio.get("tbr") or 0) if audio else 0
        detail = f'{int(video.get("height") or 0)}p'
        detail += f" · 音軌約 {abr:.0f} kbps" if audio else " · 影片內建音軌"
        if audio_fallback:
            detail += "（最低可用音質）"
        return {"ok": True, "video": paths[0], "audio": paths[1] if len(paths) > 1 else None,
                "detail": detail, "engine": "yt-dlp"}

def run_json(payload):
    request = json.loads(payload)
    try:
        _check_cancel(request)
        if request.get("command") == "self_test":
            result = self_test()
        else:
            result = download(request)
    except Cancelled as error:
        result = {"ok": False, "error": {"code": "cancelled", "message": str(error)}}
    except Exception as error:
        result = {"ok": False, "error": {"code": error_code(str(error)), "message": str(error)[-6000:]}}
    return json.dumps(result, ensure_ascii=False)

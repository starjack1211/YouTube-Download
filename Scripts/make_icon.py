"""Generate the app's simple download symbol without extra dependencies."""
import json
import struct
import zlib
from pathlib import Path

size = 1024
rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        stem = 458 <= x <= 566 and 225 <= y <= 560
        arrow = 480 <= y <= 700 and abs(x - 512) <= (700 - y)
        tray = ((250 <= x <= 335 or 689 <= x <= 774) and 660 <= y <= 800) or (250 <= x <= 774 and 750 <= y <= 835)
        rows.extend((255, 255, 255) if stem or arrow or tray else (222, 44, 58))

def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
png += chunk(b"IEND", b"")
folder = Path("App/Assets.xcassets/AppIcon.appiconset")
folder.mkdir(parents=True, exist_ok=True)
(folder / "AppIcon.png").write_bytes(png)
(folder / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}), encoding="utf-8")

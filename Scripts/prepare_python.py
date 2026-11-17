"""Fetch checksum-pinned CPython and pure-Python wheels for the iPhone bundle."""
import argparse
import hashlib
import io
import json
import tarfile
import urllib.request
import zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
lock = json.loads((root / "Config/python-lock.json").read_text())
parser = argparse.ArgumentParser()
parser.add_argument("--packages-only", action="store_true")
options = parser.parse_args()
cache = root / ".cache"
cache.mkdir(exist_ok=True)
def fetch(spec, name):
    path = cache / name
    if not path.exists():
        with urllib.request.urlopen(spec["url"], timeout=120) as response:
            path.write_bytes(response.read())
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != spec["sha256"]:
        raise RuntimeError(f"Checksum mismatch: {name}")
    return data
vendor = root / "Vendor"
vendor.mkdir(exist_ok=True)
if not options.packages_only:
    data = fetch(lock["runtime"], "python-ios.tar.gz")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.startswith("Python.xcframework/"):
                continue
            target = (vendor / member.name).resolve()
            if not target.is_relative_to(vendor.resolve()):
                raise RuntimeError("Invalid runtime archive path")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
packages = vendor / "python_packages"
packages.mkdir(exist_ok=True)
for name, spec in lock["packages"].items():
    data = fetch(spec, f"{name}-{spec['version']}.whl")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for member in archive.infolist():
            if member.is_dir():
                continue
            target = (packages / member.filename).resolve()
            if not target.is_relative_to(packages.resolve()):
                raise RuntimeError("Invalid wheel path")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(member))
print("Prepared verified Python runtime and yt-dlp packages")

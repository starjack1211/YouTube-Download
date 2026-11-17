"""Point the extension's Python markers at the containing app's frameworks."""
import shutil
import sys
from pathlib import Path
bundle = Path(sys.argv[1]).resolve()
if bundle.suffix != ".appex":
    raise RuntimeError("Expected a share extension bundle")
frameworks = bundle / "Frameworks"
removed = set()
for marker in (bundle / "python").rglob("*.fwork"):
    relative = marker.read_text().strip()
    if not relative.startswith("Frameworks/"):
        raise RuntimeError("Unexpected CPython framework marker")
    marker.write_text("../../" + relative + "\n")
    directory = (bundle / relative).parent.resolve()
    if not directory.is_relative_to(frameworks.resolve()):
        raise RuntimeError("Framework outside extension bundle")
    removed.add(directory)
for directory in removed:
    if directory.exists():
        shutil.rmtree(directory)

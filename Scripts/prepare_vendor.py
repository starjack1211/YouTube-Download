"""Prepare a checksum-pinned YouTubeKit with the reviewed compatibility patch."""
import hashlib
import io
import shutil
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = "7f75a2299dc329c0b7855afb25d47663a02855cb"
SHA256 = "bd7668f398afb8afc122b5b12b1f7c03cc5ac8568414af347cd4a0400b3b01b4"
archive = ROOT / "work-vendor.zip"
if archive.exists():
    data = archive.read_bytes()
else:
    with urllib.request.urlopen(f"https://codeload.github.com/alexeichhorn/YouTubeKit/zip/{REVISION}", timeout=60) as response:
        data = response.read()
if hashlib.sha256(data).hexdigest() != SHA256:
    raise RuntimeError("YouTubeKit archive checksum mismatch")
destination = ROOT / "Vendor" / "YouTubeKit"
with zipfile.ZipFile(io.BytesIO(data)) as z:
    for entry in z.infolist():
        parts = Path(entry.filename).parts[1:]
        if not parts or (parts[0] not in ("Sources", "Tests", "Package.swift", "LICENSE")) or entry.is_dir():
            continue
        target = destination.joinpath(*parts).resolve()
        if not target.is_relative_to(destination.resolve()):
            raise RuntimeError("Invalid archive path")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(entry))

def replace(path, old, new):
    file = destination / path
    text = file.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Patch anchor missing in {path}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")

youtube = "Sources/YouTubeKit/YouTube.swift"
replace(youtube,
    "let innertubeClients: [InnerTube.ClientType] = [.tvSamsung, .visionOS, .web]",
    "let innertubeClients: [InnerTube.ClientType] = [.ios, .tvSamsung, .visionOS, .web]")
replace(youtube,
    "var existingITags = Set<Int>()",
    "var existingITags = Set<Int>()\n                    var extractionErrors = [Error]()")
replace(youtube,
    """                        } catch {
                            // to force an update""",
    """                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            try Task.checkCancellation()
                            // to force an update""")
replace(youtube,
    """                    for videoInfo in videoInfos {
                        try await process(videoInfo: videoInfo)
                    }""",
    """                    for videoInfo in videoInfos {
                        try Task.checkCancellation()
                        do {
                            try await process(videoInfo: videoInfo)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            extractionErrors.append(error)
                        }
                    }""")
replace(youtube,
    """                            try await process(videoInfo: videoInfo)
                        }
                    }
                    
                    return streams""",
    """                            do {
                                try await process(videoInfo: videoInfo)
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                extractionErrors.append(error)
                            }
                        }
                    }
                    guard !streams.isEmpty else {
                        throw extractionErrors.first ?? YouTubeKitError.extractError
                    }
                    return streams""")

extraction = "Sources/YouTubeKit/Extraction.swift"
replace(extraction, "        let solver = try SignatureSolver(js: js)\n", "")
replace(extraction,
    "        // Batch solve all signatures and n-parameters",
    """        // Already-signed URLs must not depend on an unrelated player solver.
        guard !nInputs.isEmpty || !sigInputs.isEmpty else { return }
        let solver = try SignatureSolver(js: js)
        // Batch solve all signatures and n-parameters""")
solver = "Sources/YouTubeKit/SignatureSolver.swift"
replace(solver,
    """        let requests = [
            Request(type: .n, challenges: request.nInputs),
            Request(type: .sig, challenges: request.sigInputs)
        ]""",
    """        let requests = [
            Request(type: .n, challenges: Array(Set(request.nInputs))),
            Request(type: .sig, challenges: Array(Set(request.sigInputs)))
        ].filter { !$0.challenges.isEmpty }
        guard !requests.isEmpty else { return SolveResponse(nMap: [:], sigMap: [:]) }""")

# Integration tests compile the exact merger used by the iPhone app.
shutil.copyfile(ROOT / "Shared/MediaMuxer.swift", ROOT / "Integration/Tests/MediaMuxer.swift")
print("Prepared checksum-verified YouTubeKit with source fallback and signed-URL fixes")

import Foundation
import VideoToolbox

struct PythonProgress: Decodable {
    let stage: String
    let part_index: Int?
    let part_count: Int?
    let sizes: [Int64?]
    let downloaded_bytes: Int64?
    let total_bytes: Int64?
}

struct PythonReply: Decodable {
    struct Failure: Decodable { let code: String; let message: String }
    let ok: Bool
    let video: String?
    let audio: String?
    let detail: String?
    let metadata: [String: String]?
    let error: Failure?
}

struct PythonBackendFailure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? {
        switch code {
        case "verification_required": return "YouTube 要求播放驗證或登入：\(message)"
        case "region_restricted": return "這部影片在目前網路地區無法播放：\(message)"
        default: return message
        }
    }
}

@MainActor
final class PythonBackend {
    static let shared = PythonBackend()
    private let queue = DispatchQueue(label: "com.starjack1211.python", qos: .userInitiated)

    func selfTest() async throws -> [String: String] {
        let reply = try await execute(["command": "self_test"], cancelFile: nil)
        return reply.metadata ?? [:]
    }

    func download(id: String, maxHeight: Int, audioKbps: Int, directory: URL,
                  onProgress: @escaping @MainActor (PythonProgress) -> Void) async throws -> PythonReply {
        let progress = directory.appendingPathComponent("progress.json")
        let cancel = directory.appendingPathComponent("cancel.flag")
        var codecs = ["avc1", "h264", "hvc1", "hev1"]
        if VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) { codecs.append("av01") }
        let poller = Task { @MainActor in
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: progress),
                   let value = try? JSONDecoder().decode(PythonProgress.self, from: data) {
                    onProgress(value)
                }
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { break }
            }
        }
        defer { poller.cancel() }
        return try await execute([
            "command": "download", "url": "https://www.youtube.com/watch?v=\(id)",
            "max_height": maxHeight, "audio_kbps": audioKbps, "video_codecs": codecs,
            "directory": directory.path, "progress_file": progress.path, "cancel_file": cancel.path
        ], cancelFile: cancel)
    }

    private func execute(_ request: [String: Any], cancelFile: URL?) async throws -> PythonReply {
        try Task.checkCancellation()
        let data = try JSONSerialization.data(withJSONObject: request)
        let json = String(decoding: data, as: UTF8.self)
        let resources = Bundle.main.resourcePath ?? Bundle.main.bundlePath
        let output: String = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                queue.async {
                    let result = PYRunRequest(json, resources)
                    continuation.resume(returning: result)
                }
            }
        }, onCancel: {
            if let cancelFile { FileManager.default.createFile(atPath: cancelFile.path, contents: Data()) }
        })
        try Task.checkCancellation()
        let reply = try JSONDecoder().decode(PythonReply.self, from: Data(output.utf8))
        guard reply.ok else {
            if reply.error?.code == "cancelled" { throw CancellationError() }
            throw PythonBackendFailure(code: reply.error?.code ?? "runtime_error",
                                       message: reply.error?.message ?? "Python 下載失敗。")
        }
        return reply
    }
}

import Foundation
import Combine
import Photos
import AVFoundation

struct DownloadFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class Downloader: ObservableObject {
    @Published var busy = false
    @Published var status = "貼上連結，或從 YouTube 分享影片。"
    @Published var transferInfo: TransferSnapshot?
    @Published var transferPart = ""
    private var statistics: TransferStatistics?
    private var activeTransferID: UUID?
    @Published var detail = ""
    @Published var output: URL?
    @Published var saved = false
    private var job: Task<Void, Never>?

    func start(text: String, maxHeight: Int, audioKbps: Int) {
        guard !busy else { return }
        guard let id = YouTubeLink.videoID(in: text) else {
            status = "請輸入有效的 YouTube 影片連結（支援 Shorts）。"; return
        }
        busy = true; transferInfo = nil; statistics = nil; detail = ""; output = nil; saved = false
        job = Task {
            defer { busy = false; activeTransferID = nil; transferInfo = nil; job = nil }
            do {
                let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard auth == .authorized || auth == .limited else {
                    throw DownloadFailure(message: "請在 iPhone「設定 → App → 影片下載 → 照片」允許加入照片後重試。")
                }
                status = "Python 正在解析影片…"
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let identifier = UUID()
                activeTransferID = identifier
                var activePart: Int?
                let ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 500_000_000) } catch { break }
                        guard let self, self.activeTransferID == identifier else { break }
                        if self.transferInfo != nil {
                            self.transferInfo = self.statistics?.snapshot(at: ProcessInfo.processInfo.systemUptime)
                        }
                    }
                }
                defer { ticker.cancel() }
                let reply = try await PythonBackend.shared.download(
                    id: id, maxHeight: maxHeight, audioKbps: audioKbps, directory: folder
                ) { [weak self] event in
                    guard let self, self.activeTransferID == identifier else { return }
                    guard event.stage != "extracting", let part = event.part_index else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    if activePart != part {
                        activePart = part
                        self.statistics = TransferStatistics(expectedSizes: event.sizes, startedAt: now)
                        self.statistics?.beginPart(part, at: now)
                    }
                    let count = event.part_count ?? 1
                    self.transferPart = count == 1 ? "影片下載" : (part == 0 ? "影像下載（1/2）" : "音軌下載（2/2）")
                    self.status = part == 0 ? "Python 正在下載影像…" : "Python 正在下載音軌…"
                    self.statistics?.record(bytes: event.downloaded_bytes ?? 0, expectedBytes: event.total_bytes ?? -1, at: now)
                    self.transferInfo = self.statistics?.snapshot(at: now)
                }
                activeTransferID = nil
                guard let path = reply.video else { throw DownloadFailure(message: "Python 沒有回傳影片檔案。") }
                let videoURL = URL(fileURLWithPath: path)
                let audioURL = reply.audio.map { URL(fileURLWithPath: $0) }
                detail = reply.detail ?? "yt-dlp"
                try Task.checkCancellation()
                status = "下載完成，正在合併影音…"; transferInfo = nil
                let merged = folder.appendingPathComponent("merged.mp4")
                try await MediaMuxer.merge(video: videoURL, audio: audioURL, to: merged)
                try Task.checkCancellation()
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let downloads = docs.appendingPathComponent("Downloads")
                try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
                let final = downloads.appendingPathComponent("\(id)-\(UUID().uuidString.prefix(8)).mp4")
                try FileManager.default.moveItem(at: merged, to: final)
                output = final
                status = "正在儲存到相簿…"
                try await saveToPhotos(final)
                saved = true; status = "已儲存到相簿"
            } catch is CancellationError {
                status = "已取消下載。"
            } catch {
                if Task.isCancelled { status = "已取消下載。" }
                else { status = "下載未完成：\(error.localizedDescription)" }
            }
        }
    }

    func cancel() { job?.cancel() }

    func retrySave() {
        guard let output, !busy, !saved else { return }
        busy = true
        job = Task {
            defer { busy = false; job = nil }
            do {
                try await saveToPhotos(output)
                saved = true; status = "已儲存到相簿"
            } catch { status = "儲存失敗：\(error.localizedDescription)" }
        }
    }

    func removeLocalCopy() {
        guard !busy, let output else { return }
        do {
            try FileManager.default.removeItem(at: output)
            self.output = nil
            status = saved ? "已刪除 App 內副本，相簿影片仍保留。" : "已刪除 App 內副本。"
        } catch { status = error.localizedDescription }
    }

    private func saveToPhotos(_ url: URL) async throws {
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else {
            throw DownloadFailure(message: "相簿權限未開啟；影片仍保存在 App，可使用「分享檔案」匯出。")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

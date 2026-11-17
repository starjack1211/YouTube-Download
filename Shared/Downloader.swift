import Foundation
import Combine
import Photos
import AVFoundation
import YouTubeKit

struct DownloadFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class TransferProgress: NSObject, URLSessionDownloadDelegate {
    let update: @Sendable (Int64, Int64, TimeInterval) -> Void
    private var lastUpdate: TimeInterval = 0
    init(update: @escaping @Sendable (Int64, Int64, TimeInterval) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastUpdate >= 0.2 || (totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite) else { return }
        lastUpdate = now
        update(totalBytesWritten, totalBytesExpectedToWrite, now)
    }
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
                status = "正在解析影片…"
                let streams = try await YouTube(videoID: id, methods: [.local]).streams
                try Task.checkCancellation()
                let videos = streams.filter {
                    $0.includesVideoTrack && $0.isNativelyPlayable && $0.fileExtension == .mp4 &&
                    ($0.videoResolution ?? Int.max) <= maxHeight
                }.sorted {
                    if $0.videoResolution != $1.videoResolution { return ($0.videoResolution ?? 0) > ($1.videoResolution ?? 0) }
                    return !$0.includesAudioTrack && $1.includesAudioTrack
                }
                guard let video = videos.first else {
                    throw DownloadFailure(message: "找不到符合畫質上限的相容 MP4。請提高畫質上限，或改試另一部影片。")
                }
                let audios = streams.filter {
                    $0.includesAudioTrack && !$0.includesVideoTrack && $0.isNativelyPlayable &&
                    ($0.fileExtension == .m4a || $0.fileExtension == .mp4)
                }
                let withinCap = audios.filter { ($0.averageBitrate ?? $0.bitrate ?? Int.max) <= audioKbps * 1000 }
                let audio = (withinCap.isEmpty ? audios : withinCap).sorted {
                    let a = $0.averageBitrate ?? $0.bitrate ?? 0
                    let b = $1.averageBitrate ?? $1.bitrate ?? 0
                    return withinCap.isEmpty ? a < b : a > b
                }.first
                if !video.includesAudioTrack && audio == nil {
                    throw DownloadFailure(message: "這部影片沒有可合併的 AAC 音軌，無法輸出有聲影片。")
                }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                detail = "\(video.videoResolution ?? 0)p"
                if !video.includesAudioTrack, let audio {
                    let rate = (audio.averageBitrate ?? audio.bitrate ?? 0) / 1000
                    detail += rate > 0 ? " · 音軌約 \(rate) kbps" : " · 原始 AAC 音軌"
                    if withinCap.isEmpty { detail += "（最低可用音質）" }
                } else { detail += " · 影片內建音軌" }
                let needsAudio = !video.includesAudioTrack && audio != nil
                let plannedStreams = needsAudio ? [video, audio!] : [video]
                let sizes = plannedStreams.map { stream -> Int64? in
                    let value = URLComponents(url: stream.url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "clen" })?.value
                    return value.flatMap(Int64.init)
                }
                statistics = TransferStatistics(expectedSizes: sizes, startedAt: ProcessInfo.processInfo.systemUptime)
                status = "正在下載影像…"
                transferPart = needsAudio ? "影像下載（1/2）" : "影片下載"
                let videoURL = try await transfer(video, to: folder.appendingPathComponent("video.mp4"), part: 0)
                var audioURL: URL?
                if !video.includesAudioTrack, let audio {
                    status = "正在下載音軌…"
                    transferPart = "音軌下載（2/2）"
                    audioURL = try await transfer(audio, to: folder.appendingPathComponent("audio.m4a"), part: 1)
                }
                try Task.checkCancellation()
                status = "下載完成，正在合併影音…"; transferInfo = nil
                let merged = folder.appendingPathComponent("merged.mp4")
                try await mux(video: videoURL, audio: audioURL, to: merged)
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

    private func transfer(_ stream: YouTubeKit.Stream, to destination: URL, part: Int) async throws -> URL {
        transferInfo = nil
        try await stream.waitUntilAvailable()
        try Task.checkCancellation()
        let identifier = UUID()
        activeTransferID = identifier
        let now = ProcessInfo.processInfo.systemUptime
        statistics?.beginPart(part, at: now)
        transferInfo = statistics?.snapshot(at: now)
        // Refresh even without callbacks so a stalled connection never shows a stale speed.
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { break }
                guard let self, self.activeTransferID == identifier else { break }
                self.transferInfo = self.statistics?.snapshot(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        defer { ticker.cancel(); activeTransferID = nil }
        var request = URLRequest(url: stream.url)
        request.timeoutInterval = 120
        let observer = TransferProgress { [weak self] bytes, total, timestamp in
            Task { @MainActor in
                guard let self, self.activeTransferID == identifier else { return }
                self.statistics?.record(bytes: bytes, expectedBytes: total, at: timestamp)
                self.transferInfo = self.statistics?.snapshot(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (temp, response) = try await session.download(for: request, delegate: observer)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DownloadFailure(message: "媒體伺服器回傳 HTTP \(code)，請稍後重試。")
        }
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: temp.path)
        let count = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        statistics?.finishPart(bytes: count, at: ProcessInfo.processInfo.systemUptime)
        transferInfo = statistics?.snapshot(at: ProcessInfo.processInfo.systemUptime)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    private func mux(video: URL, audio: URL?, to output: URL) async throws {
        let composition = AVMutableComposition()
        let asset = AVURLAsset(url: video)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw DownloadFailure(message: "無法讀取影像軌。")
        }
        let duration = try await asset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let audioAsset = audio.map { AVURLAsset(url: $0) } ?? asset
        guard let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw DownloadFailure(message: "無法讀取音軌。")
        }
        let audioDuration = try await audioAsset.load(.duration)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: sourceAudio, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw DownloadFailure(message: "無法建立 MP4 輸出。")
        }
        exporter.outputURL = output; exporter.outputFileType = .mp4; exporter.shouldOptimizeForNetworkUse = true
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously { continuation.resume() }
            }
        }, onCancel: { exporter.cancelExport() })
        try Task.checkCancellation()
        guard exporter.status == .completed else {
            throw exporter.error ?? DownloadFailure(message: "影音合併失敗。")
        }
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

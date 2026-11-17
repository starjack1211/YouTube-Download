import Foundation
import AVFoundation

struct MediaMergeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum MediaMuxer {
    static func merge(video: URL, audio: URL?, to output: URL) async throws {
        let composition = AVMutableComposition()
        let asset = AVURLAsset(url: video)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaMergeError(message: "無法讀取影像軌。")
        }
        let duration = try await asset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let audioAsset = audio.map { AVURLAsset(url: $0) } ?? asset
        guard let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaMergeError(message: "無法讀取音軌。")
        }
        let audioDuration = try await audioAsset.load(.duration)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: sourceAudio, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaMergeError(message: "無法建立 MP4 輸出。")
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

}

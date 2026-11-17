import XCTest
import Photos
import AVFoundation
@testable import YouTubeDownload

@MainActor
final class DownloaderTests: XCTestCase {
    func testInvalidLinkDoesNotStartDownload() {
        let downloader = Downloader()
        downloader.start(text: "invalid link", maxHeight: 360, audioKbps: 64)
        XCTAssertFalse(downloader.busy)
        XCTAssertTrue(downloader.status.contains("有效"))
    }

    func testCancellationStopsPendingDownload() async throws {
        let downloader = Downloader()
        downloader.start(text: "https://youtu.be/_pJQFrTU4aQ", maxHeight: 360, audioKbps: 64)
        downloader.cancel()
        let deadline = Date().addingTimeInterval(30)
        while downloader.busy && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(downloader.busy)
        XCTAssertTrue(downloader.status.contains("取消"), downloader.status)
    }

    func testReportedVideoDownloadsWithProgressAndSavesToPhotos() async throws {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            XCTFail("Simulator must grant photos-add before this test"); return
        }
        let downloader = Downloader()
        downloader.start(text: "https://youtu.be/_pJQFrTU4aQ?feature=shared", maxHeight: 360, audioKbps: 64)
        var sawReceivedBytes = false
        let deadline = Date().addingTimeInterval(300)
        while downloader.busy && Date() < deadline {
            if let info = downloader.transferInfo, info.downloadedBytes > 0 { sawReceivedBytes = true }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if downloader.busy { downloader.cancel(); XCTFail("Download exceeded five minutes"); return }
        XCTAssertTrue(downloader.saved, downloader.status)
        XCTAssertTrue(sawReceivedBytes, "No byte progress was published")
        let output = try XCTUnwrap(downloader.output, downloader.status)
        defer { try? FileManager.default.removeItem(at: output) }
        let asset = AVURLAsset(url: output)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(video.count, 1)
        XCTAssertEqual(audio.count, 1)
        XCTAssertGreaterThan(duration, 600)
        print("IOS LIVE: reported video downloaded, byte progress observed, merged and added to Photos (\(duration)s)")
    }
}

import XCTest
import Foundation
import AVFoundation
@testable import YouTubeKit

final class LiveExtractionTests: XCTestCase {
    func testReportedVideoFullDownloadAndMerge() async throws {
        try await check("_pJQFrTU4aQ", expectedMinimumDuration: 600)
    }
    func testReferenceVideoFullDownloadAndMerge() async throws {
        try await check("aqz-KE-bpKQ", expectedMinimumDuration: 590)
    }
    private func check(_ id: String, expectedMinimumDuration: Double) async throws {
        let video = YouTube(videoID: id, methods: [.local])
        let streams = try await video.streams
        print("LIVE \(id): extracted \(streams.count) streams")
        let videoStream = try XCTUnwrap(streams.filter {
            $0.includesVideoTrack && !$0.includesAudioTrack && $0.fileExtension == .mp4 && $0.isNativelyPlayable
        }.lowestResolutionStream())
        let audioStream = try XCTUnwrap(streams.filterAudioOnly().filter {
            $0.isNativelyPlayable && ($0.fileExtension == .m4a || $0.fileExtension == .mp4)
        }.lowestAudioBitrateStream())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let videoFile = try await download(videoStream, to: folder.appendingPathComponent("video.mp4"))
        let audioFile = try await download(audioStream, to: folder.appendingPathComponent("audio.m4a"))
        let merged = folder.appendingPathComponent("merged.mp4")
        try await MediaMuxer.merge(video: videoFile, audio: audioFile, to: merged)
        let asset = AVURLAsset(url: merged)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertGreaterThan(duration, expectedMinimumDuration)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        print("LIVE \(id): full video + audio downloaded, merged MP4 playable, duration \(duration)s")
    }
    private func download(_ stream: YouTubeKit.Stream, to file: URL) async throws -> URL {
        try await stream.waitUntilAvailable()
        var request = URLRequest(url: stream.url)
        request.timeoutInterval = 90
        let (temp, response) = try await URLSession.shared.download(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue((200...299).contains(http.statusCode), "Media HTTP \(http.statusCode)")
        let bytes = try FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? NSNumber
        XCTAssertGreaterThan(bytes?.intValue ?? 0, 1024)
        print("LIVE media: HTTP \(http.statusCode), \(bytes?.intValue ?? 0) bytes")
        try FileManager.default.moveItem(at: temp, to: file)
        return file
    }
}

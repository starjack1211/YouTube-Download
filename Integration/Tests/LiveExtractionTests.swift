import XCTest
import Foundation
@testable import YouTubeKit

final class LiveExtractionTests: XCTestCase {
    func testReportedVideo() async throws {
        try await check("_pJQFrTU4aQ")
    }
    func testReferenceVideo() async throws {
        try await check("BaW_jenozKc")
    }
    private func check(_ id: String) async throws {
        let video = YouTube(videoID: id, methods: [.local])
        print("LIVE \(id): player \(try await video.jsURL)")
        let js = try await video.js
        print("LIVE \(id): player bytes \(js.utf8.count)")
        let solver = try SignatureSolver(js: js)
        let solved = try solver.batchSolve(request: .init(nInputs: ["test-challenge"], sigInputs: []))
        XCTAssertFalse(solved.nMap.isEmpty)
        let streams = try await video.streams
        print("LIVE \(id): extracted \(streams.count) streams")
        XCTAssertFalse(streams.isEmpty)
        let videoStream = try XCTUnwrap(streams.filter { $0.includesVideoTrack && $0.fileExtension == .mp4 && $0.isNativelyPlayable }.lowestResolutionStream())
        try await videoStream.waitUntilAvailable()
        var request = URLRequest(url: videoStream.url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        print("LIVE \(id): media HTTP \(http.statusCode), bytes \(data.count)")
        XCTAssertTrue((200...299).contains(http.statusCode))
        XCTAssertGreaterThan(data.count, 0)
    }
}

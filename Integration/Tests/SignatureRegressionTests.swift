import XCTest
import Foundation
@testable import YouTubeKit

final class SignatureRegressionTests: XCTestCase {
    func testAlreadySignedMediaDoesNotNeedPlayerSolver() throws {
        let json = #"""
        {"videoDetails":{"videoId":"_pJQFrTU4aQ","thumbnail":{"thumbnails":[]}},"streamingData":{"formats":[{"itag":18,"url":"https://example.com/video.mp4?sig=already-signed","mimeType":"video/mp4; codecs=\"avc1.42001E, mp4a.40.2\""}]}}
        """#
        let info = try JSONDecoder().decode(InnerTube.VideoInfo.self, from: Data(json.utf8))
        var manifest = Extraction.applyDescrambler(streamData: try XCTUnwrap(info.streamingData))
        try Extraction.applySignature(streamManifest: &manifest, videoInfo: info, js: "not valid JavaScript")
        XCTAssertEqual(manifest.count, 1)
        XCTAssertEqual(manifest[0].url, "https://example.com/video.mp4?sig=already-signed")
    }

    func testEmptyChallengesAreNotSentToSolver() throws {
        let solver = try SignatureSolver(js: "not valid JavaScript")
        let response = try solver.batchSolve(request: .init(nInputs: [], sigInputs: []))
        XCTAssertTrue(response.nMap.isEmpty)
        XCTAssertTrue(response.sigMap.isEmpty)
    }

    func testBrokenNChallengeStillFailsRatherThanReturningAnInvalidURL() throws {
        let solver = try SignatureSolver(js: "not valid JavaScript")
        XCTAssertThrowsError(try solver.batchSolve(request: .init(nInputs: ["input"], sigInputs: [])))
    }

    func testAppleJavaScriptCoreSolvesLivePlayer() async throws {
        let video = YouTube(videoID: "_pJQFrTU4aQ", methods: [.local])
        let solver = try SignatureSolver(js: await video.js)
        let response = try solver.batchSolve(request: .init(nInputs: ["test-challenge"], sigInputs: []))
        XCTAssertFalse(try XCTUnwrap(response.nMap["test-challenge"]).isEmpty)
    }
}

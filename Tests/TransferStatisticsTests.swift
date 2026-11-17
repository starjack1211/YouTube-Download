import XCTest
@testable import LinkValidation

final class TransferStatisticsTests: XCTestCase {
    func testOverallProgressUsesRealBytesAcrossBothTracks() throws {
        var stats = TransferStatistics(expectedSizes: [1000, 100], startedAt: 0)
        stats.record(bytes: 500, expectedBytes: 1000, at: 1)
        let first = stats.snapshot(at: 1)
        XCTAssertTrue(first.isOverall)
        XCTAssertEqual(try XCTUnwrap(first.fraction), 500.0 / 1100, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(first.bytesPerSecond), 500, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(first.remainingSeconds), 1.2, accuracy: 0.01)

        stats.finishPart(bytes: 1000, at: 2)
        stats.beginPart(1, at: 3)
        let switched = stats.snapshot(at: 3)
        XCTAssertEqual(switched.downloadedBytes, 1000)
        XCTAssertNil(switched.bytesPerSecond)
        XCTAssertNil(switched.remainingSeconds)
        stats.record(bytes: 50, expectedBytes: 100, at: 4)
        let second = stats.snapshot(at: 4)
        XCTAssertEqual(second.downloadedBytes, 1050)
        XCTAssertEqual(try XCTUnwrap(second.remainingSeconds), 1, accuracy: 0.01)
        stats.finishPart(bytes: 100, at: 5)
        XCTAssertEqual(stats.snapshot(at: 5).fraction, 1)
    }

    func testUnknownSizesDoNotInventPercentageOrRemainingTime() throws {
        var stats = TransferStatistics(expectedSizes: [nil, nil], startedAt: 0)
        stats.record(bytes: 100, expectedBytes: -1, at: 1)
        let unknown = stats.snapshot(at: 1)
        XCTAssertFalse(unknown.isOverall)
        XCTAssertNil(unknown.fraction)
        XCTAssertNil(unknown.remainingSeconds)
        XCTAssertEqual(unknown.bytesPerSecond, 100)
        stats.record(bytes: 200, expectedBytes: 500, at: 2)
        let currentFile = stats.snapshot(at: 2)
        XCTAssertFalse(currentFile.isOverall)
        XCTAssertEqual(try XCTUnwrap(currentFile.fraction), 0.4, accuracy: 0.001)
        stats.finishPart(bytes: 500, at: 3)
        stats.beginPart(1, at: 4)
        stats.record(bytes: 50, expectedBytes: 100, at: 5)
        XCTAssertTrue(stats.snapshot(at: 5).isOverall)
        XCTAssertEqual(stats.snapshot(at: 5).downloadedBytes, 550)
    }

    func testStallClearsSpeedAndEstimateAndResumesWithData() {
        var stats = TransferStatistics(expectedSizes: [1000], startedAt: 0)
        stats.record(bytes: 100, expectedBytes: 1000, at: 1)
        XCTAssertEqual(stats.snapshot(at: 4).bytesPerSecond, 0)
        XCTAssertNil(stats.snapshot(at: 4).remainingSeconds)
        stats.record(bytes: 200, expectedBytes: 1000, at: 5)
        XCTAssertGreaterThan(stats.snapshot(at: 5).bytesPerSecond ?? 0, 0)
        XCTAssertNotNil(stats.snapshot(at: 5).remainingSeconds)
    }

    func testLateCallbacksCannotMoveProgressBackwards() {
        var stats = TransferStatistics(expectedSizes: [1000], startedAt: 0)
        stats.record(bytes: 500, expectedBytes: 1000, at: 2)
        stats.record(bytes: 200, expectedBytes: 1000, at: 1)
        stats.record(bytes: 300, expectedBytes: 1000, at: 3)
        XCTAssertEqual(stats.snapshot(at: 3).downloadedBytes, 500)
    }

    func testRateUsesRecentWindowRatherThanWholeDownloadAverage() throws {
        var stats = TransferStatistics(expectedSizes: [10000], startedAt: 0)
        for second in 1...5 {
            stats.record(bytes: Int64(second * 100), expectedBytes: 10000, at: Double(second))
        }
        for second in 6...11 {
            stats.record(bytes: 500 + Int64((second - 5) * 1000), expectedBytes: 10000, at: Double(second))
        }
        XCTAssertEqual(try XCTUnwrap(stats.snapshot(at: 11).bytesPerSecond), 1000, accuracy: 0.01)
    }

    func testTimeFormattingAndZeroLengthFallback() {
        let info = TransferSnapshot(downloadedBytes: 100, totalBytes: 200, bytesPerSecond: 100,
                                    remainingSeconds: 61.2, isOverall: true)
        XCTAssertEqual(info.remainingText, "約 1 分 2 秒")
        var stats = TransferStatistics(expectedSizes: [0], startedAt: 0)
        stats.record(bytes: 0, expectedBytes: 0, at: 1)
        XCTAssertNil(stats.snapshot(at: 1).fraction)
        XCTAssertNil(stats.snapshot(at: 1).remainingSeconds)
    }
}

import XCTest
@testable import YouTubeDownload

@MainActor
final class PythonBackendTests: XCTestCase {
    func testEmbeddedPythonYtDlpSSLAndJavaScriptCore() async throws {
        let metadata = try await PythonBackend.shared.selfTest()
        XCTAssertTrue(metadata["python"]?.hasPrefix("3.13.") == true, "\(metadata)")
        XCTAssertEqual(metadata["yt_dlp"], "2026.10.26")
        XCTAssertEqual(metadata["certificates"], "true")
        XCTAssertEqual(metadata["javascriptcore"], "true")
        XCTAssertEqual(metadata["ejs"], "loaded")
        XCTAssertTrue(metadata["ssl"]?.contains("OpenSSL") == true)
        print("EMBEDDED PYTHON SELF TEST: \(metadata)")
    }

    func testRuntimeCanBeCalledMoreThanOnce() async throws {
        let first = try await PythonBackend.shared.selfTest()
        let second = try await PythonBackend.shared.selfTest()
        XCTAssertEqual(first["python"], second["python"])
        XCTAssertEqual(second["ejs"], "loaded")
    }
}

import XCTest
@testable import LinkValidation

final class YouTubeLinkTests: XCTestCase {
    func testSupportedShareLinks() {
        for link in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared",
            "https://youtu.be/dQw4w9WgXcQ?si=abc",
            "看看這部影片 https://m.youtube.com/shorts/dQw4w9WgXcQ",
            "https://youtube.com/live/dQw4w9WgXcQ",
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ"
        ] {
            XCTAssertEqual(YouTubeLink.videoID(in: link), "dQw4w9WgXcQ", link)
        }
    }
    func testRejectsLookalikeHostsAndInvalidIDs() {
        for link in [
            "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/playlist?list=PL123",
            "https://youtube.com/watch?v=tooShort",
            "https://youtu.be/dQw4w9WgXcQEXTRA",
            "not a link", ""
        ] {
            XCTAssertNil(YouTubeLink.videoID(in: link), link)
        }
    }
}

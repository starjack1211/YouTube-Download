import XCTest
@testable import LinkValidation

final class YouTubeLinkTests: XCTestCase {
    func testSupportedShareLinks() {
        for link in [
            "https://www.youtube.com/watch?v=dQw4w9WgXc&feature=shared",
            "https://youtu.be/dQw4w9WgXc?si=abc",
            "看看這部影片 https://m.youtube.com/shorts/dQw4w9WgXc",
            "https://youtube.com/live/dQw4w9WgXc",
            "https://music.youtube.com/watch?v=dQw4w9WgXc",
            "https://www.youtube.com/embed/dQw4w9WgXc"
        ] {
            XCTAssertEqual(YouTubeLink.videoID(in: link), "dQw4w9WgXc", link)
        }
    }
    func testRejectsLookalikeHostsAndInvalidIDs() {
        for link in [
            "https://youtube.com.evil.example/watch?v=dQw4w9WgXc",
            "https://notyoutube.com/watch?v=dQw4w9WgXc",
            "https://youtube.com/playlist?list=PL123",
            "https://youtube.com/watch?v=tooShort",
            "https://youtu.be/dQw4w9WgXcEXTRA",
            "not a link", ""
        ] {
            XCTAssertNil(YouTubeLink.videoID(in: link), link)
        }
    }
}

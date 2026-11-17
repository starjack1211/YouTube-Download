import XCTest
@testable import YouTubeDownload

final class ShareInputTests: XCTestCase {
    func testURLProvider() async {
        let item = NSExtensionItem()
        item.attachments = [NSItemProvider(object: URL(string: "https://youtu.be/_pJQFrTU4aQ?feature=shared")! as NSURL)]
        let text = await SharedLinkReader.read(items: [item])
        XCTAssertEqual(YouTubeLink.videoID(in: text), "_pJQFrTU4aQ")
    }
    func testTextProvider() async {
        let item = NSExtensionItem()
        item.attachments = [NSItemProvider(object: "影片連結 https://www.youtube.com/watch?v=_pJQFrTU4aQ" as NSString)]
        let text = await SharedLinkReader.read(items: [item])
        XCTAssertEqual(YouTubeLink.videoID(in: text), "_pJQFrTU4aQ")
    }
    func testAttributedTextFallback() async {
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "https://youtube.com/shorts/_pJQFrTU4aQ")
        let text = await SharedLinkReader.read(items: [item])
        XCTAssertEqual(YouTubeLink.videoID(in: text), "_pJQFrTU4aQ")
    }
    func testInvalidInputIsRejected() async {
        let item = NSExtensionItem()
        item.attachments = [NSItemProvider(object: "https://example.com/watch?v=_pJQFrTU4aQ" as NSString)]
        let text = await SharedLinkReader.read(items: [item])
        XCTAssertEqual(text, "")
    }
}

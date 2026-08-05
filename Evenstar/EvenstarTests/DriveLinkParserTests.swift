import XCTest
@testable import Evenstar

final class DriveLinkParserTests: XCTestCase {

    /// The forms Google's own Share dialog and address bar produce.
    func testAcceptsTheLinkFormsGoogleHandsOut() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        let cases = [
            "https://drive.google.com/drive/folders/\(id)",
            "https://drive.google.com/drive/folders/\(id)?usp=sharing",
            "https://drive.google.com/drive/folders/\(id)?usp=drive_link",
            "https://drive.google.com/drive/u/0/folders/\(id)",
            "https://drive.google.com/open?id=\(id)",
            "  https://drive.google.com/drive/folders/\(id)  ",
        ]
        for text in cases {
            XCTAssertEqual(DriveLinkParser.folderID(from: text), id, "failed on: \(text)")
        }
    }

    /// A user who pastes the ID alone should not be told their link is wrong.
    func testAcceptsABareFolderID() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        XCTAssertEqual(DriveLinkParser.folderID(from: id), id)
    }

    /// A *file* link is the most likely wrong paste, and it must be rejected —
    /// otherwise the app would query a file ID as if it were a folder and show
    /// an empty list with no explanation.
    func testRejectsAFileLink() {
        let link = "https://drive.google.com/file/d/1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv/view"
        XCTAssertNil(DriveLinkParser.folderID(from: link))
    }

    func testRejectsRubbish() {
        for text in ["", "   ", "hello", "https://example.com/drive/folders/abc",
                     "https://drive.google.com/drive/folders/"] {
            XCTAssertNil(DriveLinkParser.folderID(from: text), "should have rejected: \(text)")
        }
    }

    /// Drive IDs are URL-safe base64-ish. Anything with a slash or a query
    /// marker in it is a parsing mistake, not an ID.
    func testDoesNotReturnSomethingWithPathOrQueryInIt() {
        let link = "https://drive.google.com/drive/folders/abc/def?usp=sharing"
        let result = DriveLinkParser.folderID(from: link)
        XCTAssertEqual(result, "abc")
    }
}

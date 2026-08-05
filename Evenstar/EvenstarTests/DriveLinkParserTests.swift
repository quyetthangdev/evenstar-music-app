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

    /// Real Drive folder IDs run 28-44 characters. Pin the exact floor so
    /// it can't quietly drift downward and start accepting ordinary words
    /// (like "screenshot1" or "helloworld") as bare IDs again.
    func testRejectsBareIDsShorterThanRealDriveIDs() {
        let tooShort = String(repeating: "a", count: 27)
        let longEnough = String(repeating: "a", count: 28)
        XCTAssertNil(DriveLinkParser.folderID(from: tooShort))
        XCTAssertEqual(DriveLinkParser.folderID(from: longEnough), longEnough)
    }

    /// Drive's /uc endpoint is a direct-download link for a *file* — the
    /// commonest direct-download form Google hands out — and it never
    /// refers to a folder. It must be rejected before it reaches the id=
    /// branch, or a file ID would be queried as a folder and produce the
    /// same silent empty-list failure testRejectsAFileLink exists to
    /// prevent.
    func testRejectsUcDownloadLinks() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        for text in [
            "https://drive.google.com/uc?id=\(id)",
            "https://drive.google.com/uc?export=download&id=\(id)",
        ] {
            XCTAssertNil(DriveLinkParser.folderID(from: text), "should have rejected: \(text)")
        }
    }

    /// Unlike /uc, /open?id= is genuinely ambiguous — Google uses it for
    /// both files and folders, and no string parsing can tell them apart —
    /// so it must stay accepted. Pinned on its own so a later tightening
    /// aimed at /uc-style links cannot silently also reject this one.
    func testStillAcceptsOpenIDLinks() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        XCTAssertEqual(DriveLinkParser.folderID(from: "https://drive.google.com/open?id=\(id)"), id)
    }
}

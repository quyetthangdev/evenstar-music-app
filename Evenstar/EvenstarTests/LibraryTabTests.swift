import XCTest
@testable import Evenstar

/// `LibraryTab` — the tab bar's destinations, and nothing else.
///
/// The account used to be a fifth tab. It is now the round button at the top
/// right of the three library tabs and opens as a sheet, the Apple Music shape.
/// Pinning the cases is what keeps it from drifting back: a new tab is a
/// deliberate change to this list, not a side effect of someone adding a case.
final class LibraryTabTests: XCTestCase {

    func testTabsAreTheThreeLibraryScreensPlusSearch() {
        XCTAssertEqual(LibraryTab.allCases, [.songs, .albums, .artists, .search])
    }

    func testAccountIsNoLongerATab() {
        XCTAssertNil(LibraryTab(rawValue: "account"))
    }
}

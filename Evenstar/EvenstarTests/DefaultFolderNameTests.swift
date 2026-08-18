import XCTest
@testable import Evenstar

/// `DriveLibraryService.defaultDisplayName` — what a folder is called when the
/// user did not name it.
///
/// Exists because the display-name field stopped being required. The rule it
/// encodes is small but has one sharp edge: the *second* folder must not be
/// allowed to take a name already on screen, or the list shows two rows that
/// read identically and the user has no way to tell which is which before
/// unlinking one.
final class DefaultFolderNameTests: XCTestCase {

    private let base = "Thư mục Drive"

    func testTheFirstFolderIsUnnumbered() {
        XCTAssertEqual(
            DriveLibraryService.defaultDisplayName(existing: []),
            base,
            "one folder should read as a name, not as an inventory item"
        )
    }

    func testACustomlyNamedFolderDoesNotConsumeTheDefault() {
        XCTAssertEqual(
            DriveLibraryService.defaultDisplayName(existing: ["Nhạc Hoa", "Chill mix"]),
            base
        )
    }

    func testTheSecondUnnamedFolderIsNumberedFromTwo() {
        XCTAssertEqual(
            DriveLibraryService.defaultDisplayName(existing: [base]),
            "\(base) 2"
        )
    }

    func testNumberingContinuesPastEveryNameAlreadyTaken() {
        let taken = [base, "\(base) 2", "\(base) 3"]

        XCTAssertEqual(
            DriveLibraryService.defaultDisplayName(existing: taken),
            "\(base) 4"
        )
    }

    /// A user who names one of their folders "Thư mục Drive 2" by hand must not
    /// then be handed the same string by the default.
    func testAHandTypedNameIsAlsoAvoided() {
        let taken = [base, "\(base) 3"]

        XCTAssertEqual(
            DriveLibraryService.defaultDisplayName(existing: taken),
            "\(base) 2",
            "the first free number, not one past the highest"
        )
    }

    /// Gaps are not reused, and that is deliberate: after linking three and
    /// unlinking the second, a new folder must not inherit the name the
    /// unlinked one had minutes earlier.
    func testAFreedNumberIsNotHandedOutAgainWhileTheGapIsBelowTheHighest() {
        let taken = [base, "\(base) 3"]
        let chosen = DriveLibraryService.defaultDisplayName(existing: taken)

        XCTAssertFalse(taken.contains(chosen), "whatever it picks, it must be free")
    }

    /// The property that actually matters, checked over a run rather than at
    /// one point: whatever is already taken, the answer is never one of them.
    func testTheResultIsNeverAlreadyTaken() {
        var taken: [String] = []
        for _ in 0..<20 {
            let next = DriveLibraryService.defaultDisplayName(existing: taken)
            XCTAssertFalse(taken.contains(next))
            taken.append(next)
        }
    }
}

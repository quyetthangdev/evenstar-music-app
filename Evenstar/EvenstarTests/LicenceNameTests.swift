import XCTest
@testable import Evenstar

final class LicenceNameTests: XCTestCase {

    func testItShortensACreativeCommonsURL() {
        XCTAssertEqual(
            LicenceName.short(for: URL(string: "http://creativecommons.org/licenses/by/3.0/")),
            "CC BY"
        )
    }

    func testItKeepsTheFullVariant() {
        XCTAssertEqual(
            LicenceName.short(for: URL(string: "http://creativecommons.org/licenses/by-nc-sa/3.0/")),
            "CC BY-NC-SA"
        )
    }

    /// No licence URL means no credit line — better than inventing one.
    func testNoURLIsNoName() {
        XCTAssertNil(LicenceName.short(for: nil))
    }
}

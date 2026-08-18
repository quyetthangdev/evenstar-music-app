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

    // MARK: - I4: a non-CC licence must not be labelled "CC"

    /// The Free Art License, seen live in the catalogue (task-9-brief.md):
    /// a real licence URL, on a real host, just not `creativecommons.org`.
    /// Must not render as "CC LAL" — that asserts a Creative Commons licence
    /// the track does not carry, in one of the three places attribution is a
    /// legal requirement.
    func testANonCCLicenceIsNotLabelledCC() {
        let name = LicenceName.short(for: URL(string: "http://artlibre.org/licence/lal/"))
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.hasPrefix("CC") ?? true, "expected a non-CC label, got \(name ?? "nil")")
        XCTAssertEqual(
            name,
            String(localized: "Giấy phép khác", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        )
    }

    /// `hasSuffix("creativecommons.org")` used to admit this host too. Exact
    /// match only.
    func testALookalikeHostIsNotTreatedAsCreativeCommons() {
        let name = LicenceName.short(for: URL(string: "http://notcreativecommons.org/licenses/by/3.0/"))
        XCTAssertEqual(
            name,
            String(localized: "Giấy phép khác", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        )
    }

    /// A URL with no host at all — the shape a malformed stored string
    /// parses to — has nothing to name, and is not the same thing as "a real
    /// licence on a site that isn't creativecommons.org". `nil`, so the
    /// caller's existing fallback (artist name alone, or the localized brand
    /// name) applies, matching `NowPlayingContentCreditTests
    /// .testAStoredStringWithNoLicencePathFallsBackTheSameWay`.
    func testAHostlessURLIsNoNameNotOtherLicence() {
        XCTAssertNil(LicenceName.short(for: URL(string: "not-a-licence")))
    }
}

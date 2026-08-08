import XCTest
@testable import Evenstar

/// The one rule that protects a paid app from a licence it may not use.
///
/// Worth its own file because it is the only part of the Jamendo integration
/// where being wrong is a legal problem rather than a visual one, and because
/// it is the part a future change is most likely to break silently — a filter
/// dropped from a query still returns music.
final class JamendoLicencePolicyTests: XCTestCase {

    /// The default, and the case that matters. A missing filter here means the
    /// app offers non-commercial music to a user who may be paying for it.
    func testCommercialOnlySendsTheFilter() {
        let items = JamendoLicencePolicy.queryItems(commercialOnly: true)

        XCTAssertTrue(
            items.contains(URLQueryItem(name: "ccnc", value: "false")),
            "the restrictive setting must exclude non-commercial licences"
        )
    }

    /// Turning the setting off widens the catalogue, so the filter must be
    /// absent rather than inverted — asking for NC-only would be a third
    /// behaviour nobody chose.
    func testAllowingEverythingSendsNoLicenceFilter() {
        let items = JamendoLicencePolicy.queryItems(commercialOnly: false)

        XCTAssertNil(items.first { $0.name == "ccnc" })
    }

    /// `@AppStorage` writes this key and the client reads it; a rename on one
    /// side alone silently reverts the user's choice to the default.
    func testTheStorageKeyIsStable() {
        XCTAssertEqual(JamendoLicencePolicy.storageKey, "jamendoCommercialOnly")
    }
}

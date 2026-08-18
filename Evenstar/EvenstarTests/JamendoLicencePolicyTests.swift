import XCTest
@testable import Evenstar

/// The one rule that protects a paid app from a licence it may not use.
///
/// Worth its own file because it is the only part of the Jamendo integration
/// where being wrong is a legal problem rather than a visual one, and because
/// it is the part a future change is most likely to break silently — a filter
/// dropped from the pipeline still returns music.
///
/// The API's own `ccnc` parameter cannot do this filtering (measured live —
/// see `task-9-brief.md`), so the judgement happens here, against a decoded
/// licence URL, and `JamendoClient` applies it after decoding rather than
/// asking the server for it.
final class JamendoLicencePolicyTests: XCTestCase {

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    // MARK: - Setting on: CC licences without an NC clause pass

    func testByPassesWhenCommercialOnly() {
        XCTAssertTrue(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by/3.0/"),
            commercialOnly: true
        ))
    }

    func testBySAPassesWhenCommercialOnly() {
        XCTAssertTrue(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-sa/3.0/"),
            commercialOnly: true
        ))
    }

    func testByNDPassesWhenCommercialOnly() {
        XCTAssertTrue(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-nd/3.0/"),
            commercialOnly: true
        ))
    }

    // MARK: - Setting on: any NC clause is rejected

    func testByNCIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-nc/3.0/"),
            commercialOnly: true
        ))
    }

    /// The exact string form the live API returns for an NC track
    /// (task-9-brief.md), not a hand-simplified stand-in.
    func testByNCSAIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-nc-sa/2.0/"),
            commercialOnly: true
        ))
    }

    func testByNCNDIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-nc-nd/3.0/"),
            commercialOnly: true
        ))
    }

    // MARK: - Setting on: unreadable terms are rejected, never assumed safe

    /// A track with no licence link at all — its terms were never
    /// established, which is not the same thing as permissive.
    func testAnAbsentLicenceIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(licenceURL: nil, commercialOnly: true))
    }

    /// The Free Art License, seen live in the catalogue (task-9-brief.md) —
    /// a real licence, just not one this policy can read the clauses of.
    func testANonCCLicenceIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(
            licenceURL: url("http://artlibre.org/licence/lal"),
            commercialOnly: true
        ))
    }

    /// `hasSuffix("creativecommons.org")` used to admit this host, which is a
    /// different site entirely. Exact match only.
    func testALookalikeHostIsRejectedWhenCommercialOnly() {
        XCTAssertFalse(JamendoLicencePolicy.permits(
            licenceURL: url("http://notcreativecommons.org/licenses/by/3.0/"),
            commercialOnly: true
        ))
    }

    // MARK: - Setting off: nothing is examined

    func testEverythingPassesWhenTheSettingIsOff() {
        XCTAssertTrue(JamendoLicencePolicy.permits(licenceURL: nil, commercialOnly: false))
        XCTAssertTrue(JamendoLicencePolicy.permits(
            licenceURL: url("http://creativecommons.org/licenses/by-nc-sa/2.0/"),
            commercialOnly: false
        ))
        XCTAssertTrue(JamendoLicencePolicy.permits(
            licenceURL: url("http://artlibre.org/licence/lal"),
            commercialOnly: false
        ))
    }

    // MARK: - Stability

    /// `@AppStorage` writes this key and the client reads it; a rename on one
    /// side alone silently reverts the user's choice to the default.
    func testTheStorageKeyIsStable() {
        XCTAssertEqual(JamendoLicencePolicy.storageKey, "jamendoCommercialOnly")
    }

    /// The app intends to charge money and CC-NC forbids commercial use, so
    /// the restrictive setting must stay the one nobody had to opt into.
    func testTheDefaultIsCommercialOnly() {
        XCTAssertTrue(JamendoLicencePolicy.defaultCommercialOnly)
    }
}

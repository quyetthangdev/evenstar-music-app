import XCTest
@testable import Evenstar

/// The expanded player's Jamendo credit line — the third of the three
/// attribution sites the spec requires, and the only one that links back to
/// the track's own page. See the doc comment on `NowPlayingContent.jamendoCredit`
/// for why the `Link` around it exists only for a `JamendoTrack`.
///
/// Pulled out into its own function, and tested here, for the same reason
/// `PlayerSubtitle` was lifted out of this view: it had no test at all while
/// it was inline, and this is the one line in the whole đợt where getting the
/// licence name wrong is a legal problem, not a cosmetic one.
@MainActor
final class NowPlayingContentCreditTests: XCTestCase {

    private func track(licenceURLString: String? = nil) -> JamendoTrack {
        JamendoTrack(
            jamendoID: "1886179",
            title: "Sunrise",
            artistName: "Alpha",
            albumTitle: "Dawn",
            durationSeconds: 184,
            audioURLString: "https://prod.jamendo.com/1886179.mp3",
            licenceURLString: licenceURLString,
            shareURLString: "https://www.jamendo.com/track/1886179"
        )
    }

    func testALicencedTrackShowsTheShortLicenceName() {
        let track = track(licenceURLString: "http://creativecommons.org/licenses/by/3.0/")

        XCTAssertEqual(NowPlayingContent.creditLine(for: track), "Alpha · CC BY")
    }

    /// `LicenceName.short(for:)` returns `nil` when the catalogue omitted a
    /// licence, and the fallback is the localized brand name, not the bare
    /// literal `"Jamendo"` — a plain `String` interpolated here would not
    /// localise on its own, the bug this project has shipped twice already.
    func testALicencelessTrackFallsBackToTheLocalizedBrandName() {
        let track = track(licenceURLString: nil)

        XCTAssertEqual(
            NowPlayingContent.creditLine(for: track),
            "Alpha · " + String(
                localized: "Jamendo",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            )
        )
    }

    /// A stored string with no `/` in it — whatever it parses to as a `URL`
    /// — has no path component for `LicenceName.short(for:)` to read, so it
    /// falls back exactly as a missing licence does.
    func testAStoredStringWithNoLicencePathFallsBackTheSameWay() {
        let track = track(licenceURLString: "not-a-licence")

        XCTAssertEqual(
            NowPlayingContent.creditLine(for: track),
            "Alpha · " + String(
                localized: "Jamendo",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            )
        )
    }
}

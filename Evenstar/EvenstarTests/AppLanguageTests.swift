import XCTest
@testable import Evenstar

/// `AppLanguage` — the in-app language override.
///
/// The part worth pinning is the split between `resolvedLocale` and
/// `resolvedBundle`. It looks like redundancy and is not: a locale formats the
/// values interpolated into a string, and a **bundle** chooses which strings
/// table the string comes from. Written with only the locale, the app
/// translated its `Text` literals and left every `String(localized:)` in the
/// old language — the navigation title said "Songs" above two tabs still
/// reading "Trên máy". Nothing about that is visible in a build.
final class AppLanguageTests: XCTestCase {

    private var saved: String??

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        if let saved, let value = saved {
            UserDefaults.standard.set(value, forKey: AppLanguage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
        saved = nil
        super.tearDown()
    }

    private func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    // MARK: - The cases

    func testSystemDefersRatherThanNamingALanguage() {
        XCTAssertNil(AppLanguage.system.locale)
    }

    func testTheTwoRealLanguagesCarryTheirCodes() {
        XCTAssertEqual(AppLanguage.vietnamese.locale?.identifier, "vi")
        XCTAssertEqual(AppLanguage.english.locale?.identifier, "en")
    }

    /// `@AppStorage` persists the raw value, and these have to match the
    /// `.lproj` names in the bundle — `resolvedBundle` looks the directory up by
    /// this exact string.
    func testRawValuesMatchTheLprojNames() {
        XCTAssertEqual(AppLanguage.vietnamese.rawValue, "vi")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
    }

    func testEachLanguageNamesItselfRatherThanBeingTranslated() {
        XCTAssertEqual(AppLanguage.vietnamese.label, "Tiếng Việt")
        XCTAssertEqual(AppLanguage.english.label, "English")
    }

    func testThePickerOrderPutsSystemFirst() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .vietnamese, .english])
    }

    // MARK: - Resolution

    func testNothingChosenFallsBackToTheDevice() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)

        XCTAssertEqual(AppLanguage.resolvedLocale, .autoupdatingCurrent)
        XCTAssertEqual(AppLanguage.resolvedBundle, Bundle.main)
    }

    func testChoosingSystemAlsoFallsBackToTheDevice() {
        choose(.system)

        XCTAssertEqual(AppLanguage.resolvedLocale, .autoupdatingCurrent)
        XCTAssertEqual(AppLanguage.resolvedBundle, Bundle.main)
    }

    /// A value written by a future version, or by hand, must not resolve to a
    /// bundle that does not exist.
    func testAnUnknownStoredValueFallsBackToTheDevice() {
        UserDefaults.standard.set("klingon", forKey: AppLanguage.storageKey)

        XCTAssertEqual(AppLanguage.resolvedLocale, .autoupdatingCurrent)
        XCTAssertEqual(AppLanguage.resolvedBundle, Bundle.main)
    }

    func testChoosingALanguageResolvesItsLocale() {
        choose(.english)
        XCTAssertEqual(AppLanguage.resolvedLocale.identifier, "en")

        choose(.vietnamese)
        XCTAssertEqual(AppLanguage.resolvedLocale.identifier, "vi")
    }

    /// **The one that catches the real mistake.** A bundle equal to `.main` here
    /// would mean the strings table was never switched, which is exactly the
    /// state the first version shipped in.
    func testChoosingALanguageResolvesItsOwnBundle() {
        for language in [AppLanguage.english, .vietnamese] {
            choose(language)

            XCTAssertNotEqual(
                AppLanguage.resolvedBundle, Bundle.main,
                "\(language.rawValue) must resolve to its own .lproj, not the main bundle"
            )
            XCTAssertTrue(
                AppLanguage.resolvedBundle.bundlePath.hasSuffix("\(language.rawValue).lproj"),
                "expected \(language.rawValue).lproj, got \(AppLanguage.resolvedBundle.bundlePath)"
            )
        }
    }

    /// End to end: the same key comes back in two different languages depending
    /// only on the setting.
    func testTheSameKeyResolvesDifferentlyPerLanguage() {
        choose(.vietnamese)
        let vi = String(
            localized: "Bài hát",
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        )
        choose(.english)
        let en = String(
            localized: "Bài hát",
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        )

        XCTAssertEqual(vi, "Bài hát")
        XCTAssertEqual(en, "Songs")
    }
}

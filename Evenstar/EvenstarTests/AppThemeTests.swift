import XCTest
import SwiftUI
@testable import Evenstar

/// `AppTheme` — three cases, one `UserDefaults` key, and one mapping onto
/// `ColorScheme?`.
///
/// Small enough to look self-evident, which is why the mapping is worth
/// pinning. `.system` maps to `nil`, and `nil` is the one value that means
/// something other than a colour: it is "defer to the phone". An enum that
/// mapped it to `.light` would look right in a light-mode simulator and be
/// wrong for every user who has their phone set to dark.
final class AppThemeTests: XCTestCase {

    func testSystemDefersRatherThanChoosingALightScheme() {
        XCTAssertNil(
            AppTheme.system.colorScheme,
            "nil is what `preferredColorScheme` reads as 'no preference'"
        )
    }

    func testLightAndDarkMapToTheirOwnSchemes() {
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    /// `@AppStorage` persists the raw value. If one is ever renamed, everybody's
    /// saved choice silently reverts to the default on the next launch — so the
    /// strings are part of the contract, not an implementation detail.
    func testRawValuesAreStable() {
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.light.rawValue, "light")
        XCTAssertEqual(AppTheme.dark.rawValue, "dark")
    }

    func testEveryStoredValueCanBeReadBack() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(rawValue: theme.rawValue), theme)
        }
    }

    /// An unknown string — a key written by a future version, or by hand —
    /// must not resolve to a real case.
    func testAnUnknownStoredValueDoesNotResolve() {
        XCTAssertNil(AppTheme(rawValue: "sepia"))
    }

    /// The order the picker shows. "Theo hệ thống" first because it is the
    /// default and the one most users will leave alone.
    func testThePickerOrderPutsSystemFirst() {
        XCTAssertEqual(AppTheme.allCases, [.system, .light, .dark])
    }

    func testEveryCaseHasAVietnameseLabel() {
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.label.isEmpty)
            XCTAssertNotEqual(theme.label, theme.rawValue, "the label must not be the raw value")
        }
    }
}

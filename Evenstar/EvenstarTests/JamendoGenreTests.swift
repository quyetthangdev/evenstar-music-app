import XCTest
@testable import Evenstar

/// The split between the tag Jamendo indexes and the label a person reads.
///
/// The whole reason `JamendoGenre` exists is that these two strings differ for
/// some cases and not others, and the ones where they differ are exactly the
/// ones a `capitalized` shortcut got wrong. So the assertions worth writing are
/// about the *relationship* between the two, not about either alone.
final class JamendoGenreTests: XCTestCase {

    func testTheTagIsTheWireValueLowercaseAndUnspaced() {
        // Jamendo's index holds these verbatim. A label leaking into a request
        // would silently return nothing rather than fail.
        XCTAssertEqual(JamendoGenre.hiphop.tag, "hiphop")
        XCTAssertEqual(JamendoGenre.electronic.tag, "electronic")
        XCTAssertEqual(JamendoGenre.classical.tag, "classical")
        for genre in JamendoGenre.offered {
            XCTAssertEqual(genre.tag, genre.tag.lowercased(), "\(genre) tag is not lower case")
            XCTAssertFalse(genre.tag.contains(" "), "\(genre) tag contains a space")
        }
    }

    /// The bug this type was added for: `tag.capitalized` rendered "Hiphop",
    /// which is not a word in either language.
    func testHiphopReadsAsTwoWords() {
        XCTAssertEqual(JamendoGenre.hiphop.label, "Hip hop")
        XCTAssertEqual(JamendoGenre.hiphop.tag, "hiphop", "the tag must not gain the space")
    }

    /// Loanwords Vietnamese uses unchanged. Asserted so that routing them
    /// through the string catalogue later is a deliberate change rather than an
    /// accident nobody notices.
    func testTheLoanwordsAreLeftAlone() {
        XCTAssertEqual(JamendoGenre.rock.label, "Rock")
        XCTAssertEqual(JamendoGenre.pop.label, "Pop")
        XCTAssertEqual(JamendoGenre.jazz.label, "Jazz")
    }

    /// A chip with no label is a blank capsule, which is the failure mode a
    /// dictionary-keyed-by-string version of this would have allowed.
    func testEveryOfferedGenreHasANonEmptyLabel() {
        for genre in JamendoGenre.offered {
            XCTAssertFalse(genre.label.isEmpty, "\(genre) has no label")
        }
    }

    func testOfferedHasNoDuplicates() {
        XCTAssertEqual(Set(JamendoGenre.offered).count, JamendoGenre.offered.count)
    }
}

import SwiftUI

/// One catalogue row: artwork, title, `artist · licence`, and a save button.
///
/// **The licence is on the row, not hidden in a detail screen.** CC-BY obliges
/// visible credit, and this is one of the three places the spec requires it.
struct JamendoResultRow: View {
    let track: JamendoCatalogueTrack
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkThumbnail(url: track.coverURL, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 44×44, not the 32×32 the icon itself needs: HIG's rule on
            // Buttons is a hit region of at least 44×44pt, and a `.frame`
            // only draws — it does not hit-test — so a tighter frame here
            // would tap-test just the glyph's ink. This app has shipped that
            // exact bug once already, in `FloatingTabBar`.
            Button(action: onSave) {
                Image(systemName: isSaved ? "checkmark" : "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
            .accessibilityLabel(isSaved
                ? String(localized: "Đã lưu", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
                : String(localized: "Lưu vào thư viện", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale))
        }
    }

    private var subtitle: String {
        guard let licence = LicenceName.short(for: track.licenceURL) else { return track.artistName }
        return "\(track.artistName) · \(licence)"
    }
}

/// Turns a Creative Commons URL into the short name people recognise.
///
/// A pure function so it can be tested, and because the alternative — showing
/// the raw URL — is credit nobody reads.
enum LicenceName {
    /// `nil` for no URL, or a URL with no host at all (the shape a malformed
    /// stored string parses to) — there is nothing there to name, and the
    /// caller's fallback (the track's artist name alone, or the localized
    /// "Jamendo" brand name in the expanded player) is the honest answer.
    ///
    /// A host that is present but is not `creativecommons.org` — Jamendo's
    /// catalogue does carry non-CC licences, the Free Art License among them
    /// — is **not** labelled "CC anything": that would assert a licence the
    /// track does not carry, in the exact places attribution is a legal
    /// requirement. It gets its own, honest label instead.
    static func short(for url: URL?) -> String? {
        guard let url, let host = url.host(), !host.isEmpty else { return nil }
        guard host == "creativecommons.org" else {
            return String(
                localized: "Giấy phép khác",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
        }
        // .../licenses/by-nc-sa/3.0/  ->  CC BY-NC-SA. Shares its parse of the
        // path with `JamendoLicencePolicy.ccLicenceSlug` — see that function's
        // doc comment for why that parse wins over Jamendo's structured
        // `licenses` object.
        guard let slug = JamendoLicencePolicy.ccLicenceSlug(in: url) else { return nil }
        return "CC " + slug.uppercased()
    }
}

/// A remote counterpart to `ArtworkThumbnail`: the same rounded shape and the
/// same placeholder, backed by `AsyncImage` instead of `ArtworkStore` — a
/// Jamendo cover is a URL on Jamendo's own CDN, not a file this app has
/// downloaded and cached, so there is nothing for `ArtworkStore`'s cache to
/// key on until (and unless) the track is saved.
struct RemoteArtworkThumbnail: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.secondary)
        }
    }
}

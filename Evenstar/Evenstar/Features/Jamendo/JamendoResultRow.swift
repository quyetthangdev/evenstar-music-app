import SwiftUI

/// One catalogue row: artwork, title, `artist · licence`, and a save button.
///
/// **The licence is on the row, not hidden in a detail screen.** CC-BY obliges
/// visible credit, and this is one of the three places the spec requires it.
struct JamendoResultRow: View {
    let track: JamendoCatalogueTrack
    let isSaved: Bool
    /// Whether this row is the one currently sounding through
    /// `JamendoPreviewPlayer`.
    let isPreviewing: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // The pause glyph replaces the cover rather than sitting beside it:
            // the artwork is the largest thing in the row and the only part big
            // enough to read at a glance which of thirty rows is sounding.
            RemoteArtworkThumbnail(url: track.coverURL, size: 44)
                .overlay {
                    if isPreviewing {
                        ZStack {
                            RoundedRectangle(cornerRadius: 44 * 0.12)
                                .fill(.black.opacity(0.45))
                            Image(systemName: "pause.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    // Tinted while previewing, the way every system list marks
                    // its currently playing row. The glyph above says "tap to
                    // stop"; this says "this is the one" from across the row,
                    // and survives a cover that failed to load.
                    .foregroundStyle(isPreviewing ? AnyShapeStyle(Color.accentColor)
                                                  : AnyShapeStyle(.primary))
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

/// A remote counterpart to `ArtworkThumbnail`: the same rounded shape, the same
/// placeholder, the same cache-seeded first frame, for a cover that lives on
/// Jamendo's CDN rather than in `Artwork/`.
///
/// **This was `AsyncImage`, which is the wrong tool for a long list.** It keeps
/// no decoded-image cache, so every row scrolling back into view re-downloaded
/// and re-decoded its JPEG — and it offers no seed, so even a row whose cover
/// was already in memory drew the placeholder for a frame first. Both are
/// problems `ArtworkThumbnail` had and solved; see
/// `ArtworkStore.remoteImage(from:maxPixel:)`, which is the local path's
/// machinery pointed at a URL. Deliberately a near-copy of `ArtworkThumbnail`
/// rather than a shared generic: the two differ only in which pair of
/// `ArtworkStore` functions they call, and a protocol to abstract that would be
/// more moving parts than the duplication it removed.
struct RemoteArtworkThumbnail: View {
    let url: URL?
    let size: CGFloat

    /// Seeded synchronously, exactly as `ArtworkThumbnail` seeds itself, and
    /// for the same reason: `.task` runs after the first body evaluation and
    /// `remoteImage` is `@concurrent`, so awaiting it suspends even on a hit.
    @State private var image: UIImage?

    init(url: URL?, size: CGFloat) {
        self.url = url
        self.size = size
        _image = State(
            initialValue: ArtworkStore.cachedRemoteImage(
                from: url,
                maxPixel: Self.pixels(for: size)
            )
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .task(id: url) {
            // Covers a *changed* URL on a recycled row, where the seeded image
            // belongs to the previous track. Probing the cache before clearing
            // keeps that change flicker-free: only a genuine miss ever shows
            // the placeholder.
            if let cached = ArtworkStore.cachedRemoteImage(
                from: url,
                maxPixel: Self.pixels(for: size)
            ) {
                image = cached
                return
            }
            image = nil
            image = await ArtworkStore.remoteImage(
                from: url,
                maxPixel: Self.pixels(for: size)
            )
        }
    }

    /// Shared by the seed and the task so the two cannot ask the cache
    /// different questions about the same thumbnail.
    private static func pixels(for size: CGFloat) -> CGFloat {
        size * UIScreen.main.scale
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

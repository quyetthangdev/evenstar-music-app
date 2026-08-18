import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Shared artwork loading. Decodes at the size actually needed rather than at
/// the file's full resolution, and caches the result.
///
/// Embedded cover art is routinely 1000x1000 to 3000x3000. Decoding a
/// 3000x3000 JPEG to draw a 44pt thumbnail allocates roughly 36 MB, and doing
/// that inside a view's `body` repeats it on every render. Downsampling through
/// ImageIO decodes only what is drawn.
///
/// Every function here is `nonisolated async`, but under this project's
/// `SWIFT_APPROACHABLE_CONCURRENCY` flags (SE-0461's
/// `NonisolatedNonsendingByDefault`) that alone does *not* move work off the
/// caller's executor — a `nonisolated async` function now runs on the
/// caller's actor instead of hopping to the cooperative pool. A caller on the
/// main actor (e.g. a `.task(id:)` closure, which is `@_inheritActorContext`)
/// would therefore decode on the main thread. `@concurrent` is what makes the
/// off-main hop explicit and guaranteed, regardless of who calls in. Nothing
/// throws — every failure path returns nil, so a corrupt or missing image
/// file can never crash a view.
enum ArtworkStore {

    /// `NSCache`, narrowed to exactly the operations Apple documents as
    /// thread-safe.
    ///
    /// Under the Swift 6 language mode the three `static let` caches below are
    /// an error — "not concurrency-safe because non-`Sendable` type
    /// `NSCache<…>` may have shared mutable state". They were the first three
    /// errors the compiler reached, and for a while they looked like the only
    /// three in the app target; that turned out to be an artefact of the
    /// compiler stopping here, and four more files needed work once it could
    /// get past this one. Worth saying plainly, because a first probe of a
    /// language-mode bump reports the errors it reaches, not the errors there
    /// are.
    ///
    /// These caches really are safe to touch from several threads at once, and
    /// that is not a judgement call — Apple's `NSCache` documentation says so
    /// outright:
    ///
    /// > You can add, remove, and query items in the cache from different
    /// > threads without having to lock the cache yourself.
    ///
    /// Note precisely what that sentence covers: *items*. It says nothing about
    /// `name`, `delegate`, `countLimit`, `totalCostLimit`, or
    /// `evictsObjectsWithDiscardedContent`, which are ordinary unsynchronised
    /// properties. And the gap is deliberate rather than an oversight:
    /// `NSCache.h` sits inside `NS_HEADER_AUDIT_BEGIN(nullability, sendability)`,
    /// so Apple swept that header for sendability and still declined to mark the
    /// class `NS_SWIFT_SENDABLE`. The mutable configuration properties are why.
    ///
    /// Hence a wrapper rather than three `nonisolated(unsafe)` annotations. That
    /// annotation means "the compiler cannot see it, trust me", and it would
    /// leave `images.countLimit = 3` from a background thread reachable and
    /// unremarked — the one corner of the API the guarantee does not reach.
    /// Exposing only `object(forKey:)` and `setObject` makes the claim
    /// structural instead of asserted: what this type permits is exactly what
    /// Apple promises. All configuration happens inside `init`, before the value
    /// can be shared.
    ///
    /// `Value: Sendable` keeps the wrapper honest about its scope — only the
    /// container's thread-safety is being asserted here, never the elements'.
    /// `Key` cannot carry the same constraint: `NSString`'s `Sendable`
    /// conformance is explicitly unavailable, because `NSMutableString`
    /// subclasses it. That is tolerable here only because `cacheKey` builds
    /// every key fresh and immutable and hands it straight in — worth knowing,
    /// since a cache does not copy its keys, so a mutable one handed in and then
    /// mutated would corrupt lookups.
    private struct SafeCache<Key: AnyObject, Value: AnyObject & Sendable>: @unchecked Sendable {
        private let cache = NSCache<Key, Value>()

        init(configure: (NSCache<Key, Value>) -> Void) {
            configure(cache)
        }

        func object(forKey key: Key) -> Value? {
            cache.object(forKey: key)
        }

        func setObject(_ object: Value, forKey key: Key) {
            cache.setObject(object, forKey: key)
        }

        func setObject(_ object: Value, forKey key: Key, cost: Int) {
            cache.setObject(object, forKey: key, cost: cost)
        }
    }

    /// ~50 MB, as the parent design spec has required since Phase 2.
    private static let images = SafeCache<NSString, UIImage> {
        $0.totalCostLimit = 50 * 1024 * 1024
    }

    /// The `maxPixel` each path was most recently decoded at.
    ///
    /// `images` is keyed by *path and size together*, which is correct — a 44pt
    /// thumbnail and a full-bleed cover are different bitmaps — but it means a
    /// caller that wants "whatever decode of this picture already exists" has no
    /// way to ask. `NSCache` cannot be enumerated, so the sizes are recorded
    /// beside it.
    ///
    /// This exists for `anyCachedImage(for:)`, which exists for the expanded
    /// player: it decodes far larger than the list rows do, so it never shares
    /// their cache entry and had nothing to draw on its first frame.
    ///
    /// Most recent rather than largest, deliberately: the most recent decode is
    /// the one least likely to have been evicted, and a slightly small stand-in
    /// for a few frames beats a correct one that is gone.
    private static let decodedSizes = SafeCache<NSString, NSNumber> {
        $0.countLimit = 512
    }

    private static let colors = SafeCache<NSString, UIColor> {
        $0.countLimit = 256
    }

    /// - Parameter maxPixel: the longest edge, in pixels, the decoded image needs.
    ///   Pass the point size multiplied by the screen scale for a crisp result.
    @concurrent
    static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage? {
        guard let relativePath else { return nil }
        let key = cacheKey(relativePath, maxPixel)
        if let cached = images.object(forKey: key) {
            noteDecodedSize(relativePath, maxPixel)
            return cached
        }

        let url = FileLocation.absoluteURL(forRelative: relativePath)
        guard let image = downsample(url: url, maxPixel: maxPixel) else { return nil }

        images.setObject(image, forKey: key, cost: cost(of: image))
        noteDecodedSize(relativePath, maxPixel)
        return image
    }

    private static func noteDecodedSize(_ relativePath: String, _ maxPixel: CGFloat) {
        decodedSizes.setObject(NSNumber(value: Double(maxPixel)), forKey: relativePath as NSString)
    }

    /// The same treatment for a cover that lives on someone else's server.
    ///
    /// Jamendo returns a cover URL, not a file in `Artwork/`, and until a track
    /// is saved there is nothing local to key on. `AsyncImage` is the obvious
    /// answer and the wrong one: it keeps no decoded-image cache, so every row
    /// that scrolls back into view decodes its JPEG again, at full size, on the
    /// main thread — down a list Jamendo will happily return 200 rows for. That
    /// is precisely the cost this type exists to avoid. The only thing that
    /// differs is where the bytes come from.
    ///
    /// Shares `images` with the local path rather than opening a second cache:
    /// one eviction policy and one 50 MB budget, instead of two that each
    /// believe they own the memory. The key is the absolute URL, which cannot
    /// collide with the Documents-relative paths the local path stores.
    ///
    /// Bytes come from `URLSession.shared`, whose `URLCache` means a cover
    /// survives eviction from `images` without a second trip to the network.
    /// Nothing here throws: a cover that will not load is a placeholder, which
    /// is what the caller draws anyway.
    @concurrent
    static func remoteImage(from url: URL?, maxPixel: CGFloat) async -> UIImage? {
        guard let url else { return nil }
        let key = cacheKey(url.absoluteString, maxPixel)
        if let cached = images.object(forKey: key) { return cached }

        guard let data = try? await URLSession.shared.data(from: url).0,
              let image = downsample(data: data, maxPixel: maxPixel)
        else { return nil }

        images.setObject(image, forKey: key, cost: cost(of: image))
        return image
    }

    /// The synchronous probe for `remoteImage`, and it exists for the reason
    /// `cachedImage` does: on a hit there is neither a download nor a decode,
    /// so suspending to discover that costs a frame of placeholder on every row
    /// that scrolls back into view. See `cachedImage`'s doc comment.
    static func cachedRemoteImage(from url: URL?, maxPixel: CGFloat) -> UIImage? {
        guard let url else { return nil }
        return images.object(forKey: cacheKey(url.absoluteString, maxPixel))
    }

    /// Any decode of this picture that is already in memory, at whatever size it
    /// happens to be. Never decodes, never suspends.
    ///
    /// For drawing *something correct* on a first frame when the caller's own
    /// size has not been decoded yet. The expanded player wants a 1200px cover
    /// and the list row that was just tapped has a 100px one; scaled up for the
    /// tens of milliseconds until the real decode lands, that is the same
    /// picture and nobody sees the difference. Nothing, on the other hand, is
    /// very visible — it is the cover failing to grow with the card.
    static func anyCachedImage(for relativePath: String?) -> UIImage? {
        guard let relativePath else { return nil }
        guard let size = decodedSizes.object(forKey: relativePath as NSString) else { return nil }
        return images.object(forKey: cacheKey(relativePath, CGFloat(size.doubleValue)))
    }

    /// The cached image, or nil — never decodes, never suspends.
    ///
    /// Exists so a view can render an already-decoded thumbnail on its **first**
    /// frame. `image(for:maxPixel:)` above is `@concurrent`, so awaiting it
    /// always suspends, even on a cache hit: a row scrolling into a list would
    /// draw its placeholder for at least one frame before the image it already
    /// had in memory could be shown. That is the grey flicker during a fast
    /// scroll, and no amount of making the decode faster addresses it, because
    /// on a hit there is no decode.
    ///
    /// Synchronous on the caller's thread by design, main included: an
    /// `NSCache` lookup is a lock and a hash, and the whole point is to have the
    /// answer before the frame is drawn. `NSCache` is thread-safe — see
    /// `SafeCache` above for the documented guarantee — so this is safe to call
    /// from anywhere, including concurrently with the writes in
    /// `image(for:maxPixel:)` above.
    static func cachedImage(for relativePath: String?, maxPixel: CGFloat) -> UIImage? {
        guard let relativePath else { return nil }
        return images.object(forKey: cacheKey(relativePath, maxPixel))
    }

    /// The longest edge, in pixels, worth keeping for a stored cover.
    ///
    /// The widest iPhone is 440pt across at `@3x`, so 1320px is the most the
    /// full-bleed expanded artwork can ever draw. 1400 clears that with a
    /// margin and nothing beyond it is ever visible.
    static let storedArtworkMaxPixel: CGFloat = 1400

    /// Re-encodes a picked photo into something worth writing to disk.
    ///
    /// A photo out of the library is routinely 4000px on its long edge and
    /// several megabytes of HEIC. Stored as-is it would cost the user's disk
    /// many times what it can ever display, and every first decode of it would
    /// be slow. Downsampling through the same ImageIO path the read side uses
    /// keeps one behaviour rather than two.
    ///
    /// Returns JPEG, so what lands in `Artwork/` matches what `ImportService`
    /// writes from an embedded tag — one folder, one format, one thing for
    /// `delete(_:)` to clean up.
    ///
    /// `nil` when the data is not a decodable image, which is the honest answer
    /// for a file the picker handed over but the system cannot read.
    @concurrent
    static func jpegForStorage(
        from data: Data,
        maxPixel: CGFloat = storedArtworkMaxPixel
    ) async -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85)
    }

    /// One key builder for both paths above. Inlining the format string in each
    /// would let the async writer and the synchronous reader drift apart, and
    /// the symptom would be silent: every probe misses, the flicker returns, and
    /// nothing anywhere reports an error.
    private static func cacheKey(_ relativePath: String, _ maxPixel: CGFloat) -> NSString {
        "\(relativePath)@\(Int(maxPixel))" as NSString
    }

    /// The cover is downsampled to this before the 3×3 draw rather than being
    /// drawn from full size.
    ///
    /// Not for speed — the draw is nine pixels either way — but to reuse the
    /// decode `dominantColor` and the thumbnail path have very likely already
    /// cached at some size. Small enough to be nearly free, large enough that
    /// each ninth still averages over hundreds of pixels rather than dozens.
    private static let palettePreScale: CGFloat = 48

    /// The average colour of the artwork, used to tint the expanded player's
    /// background. Derived from a 10px decode, so it costs almost nothing.
    @concurrent
    static func dominantColor(for relativePath: String?) async -> Color? {
        guard let relativePath else { return nil }
        let key = relativePath as NSString
        if let cached = colors.object(forKey: key) { return Color(uiColor: cached) }

        guard let small = await image(for: relativePath, maxPixel: 10),
              let averaged = averageColor(of: small) else { return nil }

        colors.setObject(averaged, forKey: key)
        return Color(uiColor: averaged)
    }

    // MARK: - Private

    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    /// The `Data` counterpart, for bytes that arrived over the network and were
    /// never written to disk. Used by `remoteImage(from:maxPixel:)`.
    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    /// The decode itself, shared by both `downsample` overloads.
    ///
    /// One copy for the same reason `cacheKey` is one function: two copies of
    /// this options dictionary would let the file path and the network path
    /// drift into decoding differently, and the symptom — one of them decoding
    /// lazily and stuttering on the draw — reports no error anywhere.
    ///
    /// `kCGImageSourceShouldCacheImmediately` is the load-bearing line. Without
    /// it `UIImage` defers the decode to first draw, which puts it back on the
    /// main thread at exactly the moment this type exists to protect.
    private static func thumbnail(from source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }


    /// Pushes a cell average back toward the colour a person would say the
    /// cover *is*.
    ///
    /// Averaging nine ninths of a photograph greys everything: mixed hues
    /// cancel, and what comes out is duller than any part of the picture. A
    /// modest saturation lift undoes that much of it. The brightness ceiling is
    /// a legibility rule, not taste — the expanded player draws white text over
    /// this field, and a cover that averages to near-white would leave it
    /// invisible in the moment before the darkening gradient takes hold.
    private static func enrich(red: Double, green: Double, blue: Double) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        let base = UIColor(red: red, green: green, blue: blue, alpha: 1)
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return base
        }
        return UIColor(
            hue: hue,
            saturation: min(saturation * 1.35, 1),
            brightness: min(brightness, 0.88),
            alpha: 1
        )
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0
        var opaqueCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.01 else { continue }
            // The buffer is premultiplied, so undo the scaling before averaging;
            // otherwise a semi-transparent cover averages toward black.
            red += Double(pixels[index]) / alpha
            green += Double(pixels[index + 1]) / alpha
            blue += Double(pixels[index + 2]) / alpha
            opaqueCount += 1
        }
        guard opaqueCount > 0 else { return nil }
        let divisor = Double(opaqueCount) * 255
        return UIColor(
            red: min(red / divisor, 1),
            green: min(green / divisor, 1),
            blue: min(blue / divisor, 1),
            alpha: 1
        )
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

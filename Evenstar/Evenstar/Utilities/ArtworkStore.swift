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

    /// ~50 MB, as the parent design spec has required since Phase 2.
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private static let colors: NSCache<NSString, UIColor> = {
        let cache = NSCache<NSString, UIColor>()
        cache.countLimit = 256
        return cache
    }()

    /// - Parameter maxPixel: the longest edge, in pixels, the decoded image needs.
    ///   Pass the point size multiplied by the screen scale for a crisp result.
    @concurrent
    static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage? {
        guard let relativePath else { return nil }
        let key = cacheKey(relativePath, maxPixel)
        if let cached = images.object(forKey: key) { return cached }

        let url = FileLocation.absoluteURL(forRelative: relativePath)
        guard let image = downsample(url: url, maxPixel: maxPixel) else { return nil }

        images.setObject(image, forKey: key, cost: cost(of: image))
        return image
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
    /// answer before the frame is drawn. `NSCache` is thread-safe, so this is
    /// safe to call from anywhere — including concurrently with the writes in
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

    /// Nine colours laid out as a 3×3 grid over the cover, for the expanded
    /// player's animated background.
    ///
    /// **A grid rather than a set of "dominant colours".** The usual palette
    /// extractor clusters an image into its most common colours and throws away
    /// where they were. That loses the thing worth keeping: a cover with a
    /// bright sky over dark ground should still read as bright above dark. Nine
    /// cells in reading order preserve the composition, and handed to a
    /// `MeshGradient` in the same order they reconstruct it — softened into a
    /// colour field rather than a picture.
    ///
    /// The averaging is free: the cover is drawn into a 3×3 bitmap context and
    /// Core Graphics' own scaler averages each ninth on the way in. No pixel
    /// loop, no clustering.
    @concurrent
    static func meshPalette(for relativePath: String?) async -> [Color]? {
        guard let small = await image(for: relativePath, maxPixel: palettePreScale),
              let cgImage = small.cgImage else { return nil }
        return grid3x3(of: cgImage)?.map { Color(uiColor: $0) }
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

    /// Nine cell averages, top-left first, reading order.
    ///
    /// **The row order is load-bearing and is not obvious.** A `CGBitmapContext`
    /// has its coordinate origin at the bottom left, which invites the
    /// assumption that row 0 of the buffer is the bottom of the picture — the
    /// first version of this reversed the rows on exactly that reasoning and
    /// came out upside down. The buffer is laid out top row first;
    /// `CGContext.draw` renders the image the right way up within it. Reading
    /// straight out is correct.
    ///
    /// Getting this wrong is invisible: an upside-down colour field taken from
    /// an abstract cover looks entirely plausible, and nothing but a test with
    /// a known top and bottom would ever report it. `ArtworkPaletteTests` is
    /// that test.
    static func grid3x3(of cgImage: CGImage) -> [UIColor]? {
        let side = 3
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        var colours: [UIColor] = []
        colours.reserveCapacity(side * side)
        for row in 0..<side {
            for column in 0..<side {
                let index = (row * side + column) * 4
                let alpha = Double(pixels[index + 3]) / 255
                guard alpha > 0.01 else {
                    colours.append(.black)
                    continue
                }
                // The buffer is premultiplied; undo it before using the
                // channels, or a semi-transparent cover reads as muddy.
                colours.append(
                    enrich(
                        red: Double(pixels[index]) / 255 / alpha,
                        green: Double(pixels[index + 1]) / 255 / alpha,
                        blue: Double(pixels[index + 2]) / 255 / alpha
                    )
                )
            }
        }
        return colours
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

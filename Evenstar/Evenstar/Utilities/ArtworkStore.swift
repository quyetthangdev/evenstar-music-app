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
/// Every function here is `nonisolated async`, so the decode runs on the
/// cooperative pool rather than the main actor. Nothing throws — every failure
/// path returns nil, so a corrupt or missing image file can never crash a view.
enum ArtworkStore {

    /// ~50 MB, as the parent design spec has required since Phase 2.
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private static let colors = NSCache<NSString, UIColor>()

    /// - Parameter maxPixel: the longest edge, in pixels, the decoded image needs.
    ///   Pass the point size multiplied by the screen scale for a crisp result.
    static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage? {
        guard let relativePath else { return nil }
        let key = "\(relativePath)@\(Int(maxPixel))" as NSString
        if let cached = images.object(forKey: key) { return cached }

        let url = FileLocation.absoluteURL(forRelative: relativePath)
        guard let image = downsample(url: url, maxPixel: maxPixel) else { return nil }

        images.setObject(image, forKey: key, cost: cost(of: image))
        return image
    }

    /// The average colour of the artwork, used to tint the expanded player's
    /// background. Derived from a 10px decode, so it costs almost nothing.
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

        var red = 0, green = 0, blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index])
            green += Int(pixels[index + 1])
            blue += Int(pixels[index + 2])
        }
        let count = width * height
        return UIColor(
            red: CGFloat(red) / CGFloat(count) / 255,
            green: CGFloat(green) / CGFloat(count) / 255,
            blue: CGFloat(blue) / CGFloat(count) / 255,
            alpha: 1
        )
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

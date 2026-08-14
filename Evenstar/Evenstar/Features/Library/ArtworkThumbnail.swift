import SwiftUI

struct ArtworkThumbnail: View {
    let relativePath: String?
    let size: CGFloat
    /// Màu nền cho ô placeholder, khi có một màu chủ đạo để bám vào.
    ///
    /// `nil` ở mọi màn hình thường: ở đó nền là màu hệ thống và một ô xám hệ
    /// thống là đúng. Trên thẻ player thì nền là chính tấm bìa đang phát, và
    /// một ô xám hệ thống nằm giữa đó đọc ra như một mảng vá.
    let tint: Color?

    /// Seeded synchronously from `ArtworkStore`'s cache, so a row whose artwork
    /// is already decoded draws it on its **first** frame instead of showing
    /// the placeholder for one frame and swapping.
    ///
    /// The old version started at nil and let `.task` fill it in. `.task` runs
    /// after the first body evaluation, and `ArtworkStore.image` is
    /// `@concurrent` so awaiting it suspends even on a cache hit — so every row
    /// scrolling into view flashed grey regardless of what was in memory.
    @State private var image: UIImage?

    init(relativePath: String?, size: CGFloat, tint: Color? = nil) {
        self.relativePath = relativePath
        self.size = size
        self.tint = tint
        _image = State(
            initialValue: ArtworkStore.cachedImage(
                for: relativePath,
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
        .task(id: relativePath) {
            // The seed in `init` covers the first path this view instance
            // renders. This covers a *changed* path — the same row identity
            // pointed at a different track — where the seeded image belongs to
            // the previous one and must not be left on screen.
            //
            // Probing the cache again before clearing is what keeps the change
            // flicker-free too: only a genuine miss ever shows the placeholder.
            if let cached = ArtworkStore.cachedImage(
                for: relativePath,
                maxPixel: Self.pixels(for: size)
            ) {
                image = cached
                return
            }
            image = nil
            image = await ArtworkStore.image(
                for: relativePath,
                maxPixel: Self.pixels(for: size)
            )
        }
    }

    /// The decode size in pixels. Shared by the seed and the task so the two
    /// cannot ask the cache different questions about the same thumbnail.
    private static func pixels(for size: CGFloat) -> CGFloat {
        size * UIScreen.main.scale
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12)
                // Pha loãng, để ô placeholder đọc như một chỗ trống *thuộc về*
                // nền này chứ không phải một khối màu tranh chỗ với tấm bìa
                // thật bên cạnh — nhưng 0.6 chứ không phải 0.35.
                //
                // Con số cũ hợp với màu trội thô, vốn sáng sẵn. Người gọi duy
                // nhất truyền `tint` là thẻ player, và nó giờ truyền xuống màu
                // *mặt phẳng* đã kéo về 0.50 độ sáng — pha loãng thêm ba lần
                // nữa là kéo ô này về đúng màu nền, tức là xoá nó.
                .fill(tint.map { AnyShapeStyle($0.opacity(0.6)) }
                      ?? AnyShapeStyle(Color(.tertiarySystemFill)))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.secondary)
        }
    }
}

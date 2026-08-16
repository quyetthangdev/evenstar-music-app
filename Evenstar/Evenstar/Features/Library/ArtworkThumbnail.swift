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

    /// The decode size in pixels. Resolved **once**, here in `init`, and stored,
    /// so the seed and the task cannot ask the cache different questions about
    /// the same thumbnail.
    ///
    /// Stored rather than recomputed because the scale is only readable at one
    /// of those two moments. `UITraitCollection.current` carries the trait
    /// collection of the view actually *hosting* this one while SwiftUI
    /// evaluates a body: measured with `traitOverrides.displayScale = 2` on the
    /// hosting controller and a 3x main screen, an `init` reached from that
    /// host's body reads 2.0 — which is the external-display and Stage Manager
    /// case the old main-screen read got wrong. Inside `.task` that push is
    /// gone and the same expression falls back to the main screen's 3.0, so
    /// reading it in both places would break the shared question on precisely
    /// the displays this change exists for.
    ///
    /// `@Environment(\.displayScale)` is not the answer either: it is empty
    /// until `body`, and the seed below has to run in `init`. (It is measurably
    /// fine from an `async` method the way `PlayerCard` uses it — that view has
    /// no `init` to serve.)
    private let maxPixel: CGFloat

    init(relativePath: String?, size: CGFloat, tint: Color? = nil) {
        self.relativePath = relativePath
        self.size = size
        self.tint = tint
        let maxPixel = size * UITraitCollection.current.displayScale
        self.maxPixel = maxPixel
        _image = State(
            initialValue: ArtworkStore.cachedImage(
                for: relativePath,
                maxPixel: maxPixel
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
                maxPixel: maxPixel
            ) {
                image = cached
                return
            }
            image = nil
            image = await ArtworkStore.image(
                for: relativePath,
                maxPixel: maxPixel
            )
        }
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

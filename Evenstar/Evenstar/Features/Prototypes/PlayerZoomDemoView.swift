//
//  PlayerZoomDemoView.swift
//  Bản thử thứ ba: cú morph do **hệ thống** chạy.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ĐIỀU ĐÁNG CHÚ Ý NHẤT LÀ THỨ KHÔNG CÓ Ở ĐÂY
//  ─────────────────────────────────────────────────────────────────────────
//  Không có `progress`. Không `DragGesture`. Không `withAnimation`. Không
//  `UIViewPropertyAnimator`. Không một phép nội suy nào. Không một con số hình
//  học nào được tính theo tiến trình.
//
//  Toàn bộ cú morph là hai modifier:
//
//      .matchedTransitionSource(id:in:)            ← ở viên thuốc
//      .navigationTransition(.zoom(sourceID:in:))  ← ở màn đích
//
//  Hệ thống lo phần còn lại: phình view nguồn thành màn hình đích, vuốt xuống
//  để đóng có tương tác, ngắt được giữa chừng, mang quán tính. Chạy ở render
//  server — luồng chính không làm gì mỗi khung hình, nên về nguyên tắc không
//  có gì để rớt frame.
//
//  Có từ iOS 18, tức chạy được trên target 18.6 hiện tại của Evenstar. Đây là
//  thứ Photos dùng khi chạm vào một tấm ảnh.
//
//  ─────────────────────────────────────────────────────────────────────────
//  CÁI PHẢI TỪ BỎ
//  ─────────────────────────────────────────────────────────────────────────
//  **Không vuốt-lên-để-mở.** Mở là chạm; ngón tay chỉ lái được chiều đóng.
//  Spec `player-morph` của Evenstar viết "dragging tracks your finger in both
//  directions", và bản này bỏ một nửa câu đó. Đổi lại: không dòng animation
//  nào để sai, và không có gì chạy trên luồng chính giữa các khung hình.
//
//  **Không tự biên đạo được.** Cú fade lệch pha, ảnh bìa tan dần, thứ tự các
//  lớp — hệ thống quyết định hết. Được cú zoom của Apple, không được cú của
//  mình.
//

import SwiftUI

struct PlayerZoomDemoView: View {
    /// Namespace nối viên thuốc với màn đích. Phải sống ở tổ tiên chung của cả
    /// hai, đúng như `matchedGeometryEffect`.
    @Namespace private var zoom
    @State private var showingPlayer = false
    @State private var isPlaying = true

    let onClose: () -> Void

    private let song = DemoSong.mock
    private static let sourceID = "zoom.player"

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(DemoSong.library.enumerated()), id: \.offset) { _, song in
                    row(song)
                }
            }
            .listStyle(.plain)
            .navigationTitle(Text(verbatim: "Bài hát"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onClose() } label: { Image(systemName: "xmark") }
                }
            }
        }
        // Layout thường, không hình học tay: viên thuốc và thanh tab là một
        // `safeAreaInset` ở đáy, nên danh sách tự chừa chỗ cho chúng. Bản
        // SwiftUI kia phải tự cộng `playerBottomOffset` vào cuối danh sách.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: BottomBarMetrics.playerTabGap) {
                miniPlayer
                tabBar
            }
            .padding(.horizontal, BottomBarMetrics.sideMargin)
            .padding(.bottom, 8)
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            ZoomNowPlaying(song: song, isPlaying: $isPlaying)
                // Nửa còn lại của cú morph. `sourceID` phải trùng đúng chuỗi ở
                // viên thuốc — gõ lệch một ký tự thì nó lặng lẽ thành cú
                // present thường, không báo lỗi gì.
                .navigationTransition(.zoom(sourceID: Self.sourceID, in: zoom))
        }
    }

    // MARK: Viên thuốc — nguồn của cú zoom

    private var miniPlayer: some View {
        HStack(spacing: DemoZoomMetrics.artworkGap) {
            artwork(corner: 8)
                .frame(width: DemoZoomMetrics.miniArtwork, height: DemoZoomMetrics.miniArtwork)

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.footnote).lineLimit(1)
                Text(song.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            Button {} label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 9)
        .padding(.trailing, 16)
        .frame(height: PlayerCard.collapsedHeight)
        .background(.regularMaterial, in: Capsule())
        .floatingBarShadow()
        // Nguồn của cú morph. Đặt **sau** `background` để hệ thống lấy cả nền
        // viên thuốc làm thứ phình ra, không chỉ mỗi nội dung.
        .matchedTransitionSource(id: Self.sourceID, in: zoom)
        .contentShape(Capsule())
        .onTapGesture { showingPlayer = true }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem("music.note.list", "Bài hát", current: true)
            tabItem("square.stack", "Album", current: false)
            tabItem("music.mic", "Nghệ sĩ", current: false)
            tabItem("person.crop.circle", "Tài khoản", current: false)
        }
        .frame(height: BottomBarMetrics.tabBarHeight)
        .background(.regularMaterial, in: Capsule())
        .floatingBarShadow()
    }

    private func tabItem(_ glyph: String, _ label: String, current: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: glyph).font(.system(size: 18))
            Text(verbatim: label).font(.caption2)
        }
        .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
    }

    private func row(_ song: DemoSong) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: song.colours,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: song.glyph).foregroundStyle(.white.opacity(0.9)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func artwork(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: song.colours,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: song.glyph)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}

private enum DemoZoomMetrics {
    static let miniArtwork: CGFloat = 36
    static let artworkGap: CGFloat = 10
}

// MARK: - Màn đích

/// Không có gì đặc biệt ở đây, và đó là điểm mấu chốt: nó chỉ là một màn hình.
/// Mọi chuyển động nằm ở `.navigationTransition(.zoom(...))` mà chỗ gọi gắn
/// vào, không có dòng nào trong này biết mình đang được morph tới.
private struct ZoomNowPlaying: View {
    let song: DemoSong
    @Binding var isPlaying: Bool
    @State private var scrub: Double = 0.32
    @State private var volume: Double = 0.6

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width - 48

            ZStack {
                LinearGradient(colors: [song.colours[0], song.colours[1], .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: song.colours,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            Image(systemName: song.glyph)
                                .font(.system(size: 76))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .frame(width: side, height: side)
                        .shadow(color: .black.opacity(0.35), radius: 26, y: 14)

                    Spacer(minLength: 0)

                    controls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var controls: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.title3.weight(.semibold)).lineLimit(1)
                Text(verbatim: "\(song.artist) · \(song.album)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $scrub).tint(.white.opacity(0.9))
                HStack {
                    Text(verbatim: "1:12")
                    Spacer()
                    Text(verbatim: "-2:31")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 48) {
                Image(systemName: "backward.fill").font(.title2).frame(width: 44, height: 44)
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Image(systemName: "forward.fill").font(.title2).frame(width: 44, height: 44)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: $volume).tint(.white.opacity(0.9))
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

#Preview {
    PlayerZoomDemoView {}
}

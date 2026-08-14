//
//  PlayerMorphPrototype.swift
//  Prototype độc lập — KHÔNG thuộc target Evenstar.
//
//  Tái tạo cú "bung mở" Mini Player → Full Player của Apple Music bằng
//  matchedGeometryEffect. Chạy được từ iOS 16.
//
//  Cách dùng: tạo một project SwiftUI mới, dán file này vào, đặt
//  `PlayerMorphPrototype()` làm root view. Cố tình không phụ thuộc gì vào
//  Evenstar để có thể sờ vào từng tham số mà không sợ hỏng app.
//
//  Bốn chỗ dễ sai nhất được đánh dấu bằng "BẪY:" trong chú thích.
//

import SwiftUI
import Foundation
import UIKit

// MARK: - Dữ liệu

struct MorphTrack: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    /// Đứng thay cho ảnh bìa thật, để prototype không cần asset.
    let glyph: String
    /// Màu trội "trích" từ ảnh bìa. Trong app thật xem `dominantColour(of:)`
    /// ở cuối file.
    let tint: Color
}

extension MorphTrack {
    static let samples: [MorphTrack] = [
        .init(title: "Chiều nay không có mưa bay", artist: "Vũ.", glyph: "cloud.rain.fill", tint: Color(red: 0.24, green: 0.36, blue: 0.55)),
        .init(title: "Có hẹn với thanh xuân", artist: "MONSTAR", glyph: "sun.max.fill", tint: Color(red: 0.72, green: 0.42, blue: 0.20)),
        .init(title: "Nhất thời", artist: "Hoàng Dũng", glyph: "moon.stars.fill", tint: Color(red: 0.35, green: 0.24, blue: 0.48)),
        .init(title: "Đông kiếm em", artist: "Nguyên Hà", glyph: "snowflake", tint: Color(red: 0.20, green: 0.45, blue: 0.45))
    ]
}

// MARK: - Định danh cho matchedGeometryEffect

/// Gom vào một chỗ vì cả hai view đều phải dùng **đúng cùng một chuỗi**. Gõ
/// tay hai lần là cách phổ biến nhất để morph im lặng không chạy: SwiftUI
/// không báo lỗi, nó chỉ fade chéo và anh ngồi tự hỏi tại sao.
private enum MorphID {
    static let artwork = "player.artwork"
    static let title = "player.title"
    static let artist = "player.artist"
}

// MARK: - Tham số chuyển động

private enum Motion {
    /// Lò xo cho cú mở. `response` là chu kỳ dao động tự nhiên — hiểu nôm na
    /// là "mất bao lâu để tới nơi"; `dampingFraction` dưới 1 cho phép vượt
    /// đích một chút rồi lùi lại, đó là cái làm nó ra chất cơ học.
    ///
    /// 0.82 nảy vừa đủ để cảm được là có khối lượng, chưa tới mức thấy nó
    /// rung. Dưới 0.7 là bắt đầu thành đồ chơi.
    static let expand = Animation.spring(response: 0.50, dampingFraction: 0.82)

    /// Cú đóng nhanh hơn cú mở. Mở là "cho tôi xem thứ này", người ta chờ
    /// được; đóng là "bỏ đi", chờ là bực.
    static let collapse = Animation.spring(response: 0.42, dampingFraction: 0.84)

    /// Khi ngón tay buông mà chưa đủ điều kiện đóng: card phải bật về chỗ cũ.
    static let settleBack = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// Nền thu lại còn bao nhiêu khi player mở hẳn.
    static let backdropScale: CGFloat = 0.93
    /// Bo góc của nền lúc đó.
    static let backdropCorner: CGFloat = 38

    /// Kéo xuống bao nhiêu điểm thì coi như đi hết hành trình đóng.
    static let dismissDistance: CGFloat = 420
    /// Kéo qua bao nhiêu phần hành trình thì buông tay là đóng.
    static let dismissFraction: CGFloat = 0.35
    /// Ngưỡng "hất tay": xem chú thích ở `onEnded` để biết đơn vị này là gì.
    static let flingThreshold: CGFloat = 180
}

// MARK: - Root

struct PlayerMorphPrototype: View {

    /// BẪY 1: namespace phải sống ở **tổ tiên chung** của cả mini lẫn full.
    /// Khai báo nó bên trong một trong hai view thì mỗi lần view đó bị dựng
    /// lại là một namespace mới, và morph biến thành fade chéo.
    @Namespace private var morph

    /// Mở sẵn khi chạy với `-expanded`, để chụp được trạng thái mở mà không
    /// cần ngón tay — `simctl` không bấm hộ được. Chỉ là tiện ích của
    /// prototype; đừng mang kiểu này về app thật.
    @State private var isExpanded = ProcessInfo.processInfo.arguments.contains("-expanded")
    @State private var current = MorphTrack.samples[0]

    /// Ngón tay đã đẩy full player xuống bao nhiêu điểm.
    @State private var dragOffset: CGFloat = 0
    /// Cùng thứ đó quy về 0…1, để nền nở ra theo tay.
    @State private var dismissProgress: CGFloat = 0

    // Nền thu nhỏ khi mở, rồi nở lại **theo ngón tay** trong lúc kéo đóng.
    // Đây là chi tiết làm cú vuốt có cảm giác dính tay: nếu nền chỉ nở ra sau
    // khi buông thì suốt cú kéo người dùng đang đẩy một tấm ảnh chết.
    private var backdropScale: CGFloat {
        guard isExpanded else { return 1 }
        return Motion.backdropScale + (1 - Motion.backdropScale) * dismissProgress
    }

    private var backdropCorner: CGFloat {
        guard isExpanded else { return 0 }
        return Motion.backdropCorner * (1 - dismissProgress)
    }

    var body: some View {
        // GeometryReader này **không** được `ignoresSafeArea`, vì chỉ một reader
        // còn tôn trọng safe area mới báo lại `safeAreaInsets` thật. Card bên
        // trong tự tràn ra mép, nhưng con số dùng để xếp chỗ thì phải đúng —
        // ngược lại grabber chui vào sau Dynamic Island, đúng lỗi ảnh chụp đầu
        // tiên của prototype này mắc phải.
        GeometryReader { outer in
            ZStack(alignment: .bottom) {
                // Nền đen dưới cùng, để khi thư viện thu lại thì thứ lộ ra là
                // bóng tối chứ không phải màu nền trắng của cửa sổ.
                Color.black.ignoresSafeArea()

                LibraryList(tracks: MorphTrack.samples, current: $current)
                    .scaleEffect(backdropScale)
                    .clipShape(RoundedRectangle(cornerRadius: backdropCorner, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
                    // BẪY 2: `.animation(_:value:)` chứ không phải
                    // `.animation(_:)`. Dạng chỉ có animation sẽ animate **mọi**
                    // thay đổi, kể cả `dismissProgress` đang chạy theo ngón tay
                    // — tức là mỗi frame của cú kéo lại khởi động một lò xo mới
                    // và nền trôi lẹt đẹt sau tay. Buộc vào `isExpanded` nghĩa
                    // là: chỉ cú mở/đóng mới có lò xo, còn lúc kéo thì bám tay
                    // tức thời.
                    .animation(Motion.expand, value: isExpanded)

                if isExpanded {
                    FullPlayer(
                        track: current,
                        namespace: morph,
                        dismissProgress: dismissProgress,
                        topInset: outer.safeAreaInsets.top,
                        onCollapse: collapse
                    )
                    .offset(y: dragOffset)
                    .gesture(dismissGesture)
                    .zIndex(1)
                } else {
                    MiniPlayer(track: current, namespace: morph)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { expand() }
                        .zIndex(1)
                }
            }
        }
    }

    // MARK: Chuyển trạng thái

    private func expand() {
        // BẪY 3: matchedGeometryEffect chỉ nội suy khi việc đổi nhánh `if`
        // nằm **trong** một transaction có animation. Đặt `isExpanded = true`
        // trần trụi ở đây là card xuất hiện tức thì, và người ta hay đổ lỗi
        // cho matchedGeometryEffect trong khi lỗi nằm ở dòng này.
        withAnimation(Motion.expand) {
            isExpanded = true
        }
    }

    private func collapse() {
        // `dragOffset` phải về 0 trong **cùng** transaction với `isExpanded`.
        // Tách ra hai lệnh thì mini player hiện ra ở vị trí đã bị đẩy xuống
        // rồi giật một cái về chỗ.
        withAnimation(Motion.collapse) {
            isExpanded = false
            dragOffset = 0
            dismissProgress = 0
        }
    }

    // MARK: Cử chỉ kéo-để-đóng

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                // Chỉ ăn chiều xuống. Kéo lên trên một card đã mở hết thì
                // không có gì để đi tới, và để nó nhúc nhích sẽ thành cao su.
                let y = max(0, value.translation.height)
                dragOffset = y
                dismissProgress = min(1, y / Motion.dismissDistance)
            }
            .onEnded { value in
                // Vận tốc, tính theo cách chạy được từ iOS 13.
                //
                // `value.velocity` (điểm/giây) chỉ có từ iOS 17. Bản dùng được
                // ở mọi phiên bản là `predictedEndTranslation`: chỗ hệ thống
                // dự đoán ngón tay sẽ dừng nếu buông ngay bây giờ, tính theo
                // đúng đường giảm tốc mà UIScrollView dùng. Hiệu giữa nó và vị
                // trí hiện tại **tỉ lệ thuận với vận tốc**, nên nó dùng làm
                // ngưỡng "hất tay" được, chỉ khác đơn vị.
                //
                // Đơn vị là điểm-sẽ-đi-thêm, không phải điểm/giây — nên đừng
                // mượn con số 800 hay 1000 mà các bài blog dùng cho `velocity`.
                // 180 điểm quán tính là một cú hất dứt khoát.
                let momentum = value.predictedEndTranslation.height - value.translation.height

                let flungDown = momentum > Motion.flingThreshold
                let draggedFar = value.translation.height
                    > Motion.dismissDistance * Motion.dismissFraction

                // Hất mạnh thì đóng ngay, kể cả mới kéo được vài chục điểm —
                // đó là toàn bộ ý nghĩa của việc đọc vận tốc. Ngưỡng quãng
                // đường là để phục vụ người kéo chậm và thả.
                if flungDown || draggedFar {
                    collapse()
                } else {
                    withAnimation(Motion.settleBack) {
                        dragOffset = 0
                        dismissProgress = 0
                    }
                }
            }
    }
}

// MARK: - Mini player

private struct MiniPlayer: View {
    let track: MorphTrack
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            Artwork(track: track, corner: 6)
                .frame(width: 40, height: 40)
                .matchedGeometryEffect(id: MorphID.artwork, in: namespace)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    // BẪY 4: `properties: .position` — chỉ vị trí, không kích
                    // thước. Mặc định matchedGeometryEffect khớp cả frame, mà
                    // frame của Text 15pt bị ép thành frame của Text 22pt thì
                    // SwiftUI không đổi cỡ chữ, nó **kéo giãn** chữ. Chữ béo ra
                    // rồi thu lại giữa cú morph, xấu và không sửa được bằng
                    // cách chỉnh font. Cho vị trí morph, còn cỡ chữ thì để hai
                    // Text fade chéo — đúng cách Apple Music làm.
                    .matchedGeometryEffect(id: MorphID.title, in: namespace, properties: .position)

                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .matchedGeometryEffect(id: MorphID.artist, in: namespace, properties: .position)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
            Image(systemName: "forward.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

// MARK: - Full player

private struct FullPlayer: View {
    let track: MorphTrack
    let namespace: Namespace.ID
    let dismissProgress: CGFloat
    /// Safe-area trên, đọc từ reader ở root. Card phải bắt đầu **thấp hơn** mép
    /// trên của thư viện đã thu nhỏ, nếu không thì chẳng ai nhìn thấy nó thu
    /// nhỏ cả — cái card-stacking coi như không có. Thu 0.93 trên màn ~874pt
    /// đẩy mép thư viện xuống ~30pt, nên card mở ở khoảng 44pt để chừa lại một
    /// dải nhìn thấy được.
    let topInset: CGFloat
    let onCollapse: () -> Void

    private var cardTop: CGFloat { max(24, topInset - 15) }

    /// Hệ số 1.4: chrome biến mất khi mới kéo được ~70% hành trình, nên nửa
    /// sau của cú vuốt chỉ còn ảnh bìa bay về chỗ mini player. Kiểu chú thích
    /// đúng cỡ được: nếu chrome mờ cùng tốc độ với card thì lúc buông tay vẫn
    /// còn chữ đang chồng lên chữ của mini player.
    ///
    /// Kẹp ở 0 vì `opacity` âm là giá trị không hợp lệ, và `dismissProgress`
    /// chạy tới hết 1.
    private var chromeOpacity: CGFloat {
        max(0, 1 - dismissProgress * 1.4)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width - 48, proxy.size.height * 0.42)

            ZStack {
                DynamicBackground(tint: track.tint)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 12)

                    Spacer(minLength: 0)

                    Artwork(track: track, corner: 14)
                        .frame(width: side, height: side)
                        .matchedGeometryEffect(id: MorphID.artwork, in: namespace)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                            .matchedGeometryEffect(id: MorphID.title, in: namespace, properties: .position)

                        Text(track.artist)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .matchedGeometryEffect(id: MorphID.artist, in: namespace, properties: .position)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                    transport
                        .padding(.top, 28)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 0)
                }
                // Chrome mờ dần theo cú kéo, nhanh hơn card di chuyển. Ảnh bìa
                // thì không: nó là thứ nối hai trạng thái, phải nhìn thấy suốt.
                .opacity(chromeOpacity)
            }
            .foregroundStyle(.white)
            // Bo hai góc trên, vuông ở đáy — `UnevenRoundedRectangle` phải iOS
            // 17 mới có, nên dùng shape tự viết ở cuối file.
            .clipShape(TopRoundedRectangle(radius: 38))
            .padding(.top, cardTop)
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture(count: 2) { onCollapse() }
        }
    }

    private var transport: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { bar in
                        Capsule()
                            .fill(.white.opacity(0.9))
                            .frame(width: bar.size.width * 0.38)
                    }
                }

            HStack(spacing: 44) {
                Image(systemName: "backward.fill")
                Image(systemName: "play.fill").font(.system(size: 44))
                Image(systemName: "forward.fill")
            }
            .font(.system(size: 30))
        }
    }
}

// MARK: - Ảnh bìa

/// Đứng thay ảnh thật. Trong app, thay cả thân view bằng `Image(uiImage:)`
/// với `.resizable().scaledToFill()` — phần còn lại giữ nguyên.
private struct Artwork: View {
    let track: MorphTrack
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [track.tint, track.tint.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: track.glyph)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.85))
                    // Không để glyph tự phóng to theo khung, nếu không nó lại
                    // là một thứ nữa đang nội suy trong lúc morph.
                    .scaleEffect(1)
            }
            // Viền mảnh để bìa tách khỏi nền — nền được trích từ chính màu bìa
            // nên hai thứ gần như cùng màu. Ảnh thật thì không cần, nhưng ở
            // prototype này không có nó thì cover chìm nghỉm vào gradient.
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

// MARK: - Hình dạng

/// Bo hai góc trên, để nguyên hai góc dưới.
///
/// `UnevenRoundedRectangle` làm đúng việc này nhưng phải iOS 17. File này để
/// chạy được từ 16, nên mượn `UIBezierPath` — nó có `byRoundingCorners` từ
/// iOS 3 và `Path(_ cgPath:)` nhận thẳng kết quả.
private struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}

// MARK: - Nền động

/// Giả lập Mesh Gradient bằng vài quầng sáng chồng nhau — `MeshGradient` thật
/// chỉ có từ iOS 18.
///
/// **Chúng chuyển động bằng `.offset` chứ không bằng cách đổi tham số
/// gradient, và đó là điểm đáng chép lại nhất trong file này.** Dịch chuyển
/// một lớp đã vẽ xong là việc Core Animation làm một mình ở render server:
/// main thread không chạm vào frame nào. Còn animate *tham số* của gradient
/// (đổi `center`, đổi stops) buộc lớp đó phải vẽ lại mỗi frame.
///
/// Đây không phải lý thuyết: Evenstar từng có một `MeshGradient` trôi ở 30fps
/// làm nền player, và hai lần đo Instruments cùng kịch bản cho thấy gỡ nó ra
/// đưa hitch từ 189 ms/giây xuống 35 ms/giây, stall dài nhất từ 900 ms xuống
/// 183 ms. Nếu bản dựng thật thấy nặng, `isAnimated = false` là chỗ tắt trước
/// tiên — Apple Music cũng dùng nền tĩnh chứ không trôi.
private struct DynamicBackground: View {
    let tint: Color
    var isAnimated: Bool = true

    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint, .black],
                startPoint: .top,
                endPoint: .bottom
            )

            blob(tint.opacity(0.85))
                .frame(width: 340, height: 340)
                .offset(x: drift ? -70 : -130, y: drift ? -220 : -160)

            blob(.white.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: drift ? 130 : 80, y: drift ? -60 : -140)

            blob(tint.opacity(0.6))
                .frame(width: 420, height: 420)
                .offset(x: drift ? 60 : 110, y: drift ? 260 : 200)
        }
        // Không `ignoresSafeArea()` ở đây: card cha đã tự quyết định nó trải
        // tới đâu và tự clip. Một lớp con tự tràn ra bên trong một cha đã clip
        // chỉ tạo ra layout khó đoán mà không đổi được gì trên màn hình.
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ colour: Color) -> some View {
        Circle()
            .fill(colour)
            .blur(radius: 70)
    }
}

// MARK: - Thư viện phía sau

private struct LibraryList: View {
    let tracks: [MorphTrack]
    @Binding var current: MorphTrack

    var body: some View {
        NavigationStack {
            List(tracks) { track in
                Button {
                    current = track
                } label: {
                    HStack(spacing: 12) {
                        Artwork(track: track, corner: 6)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.body)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                // Không có dòng này thì `scrollContentBackground(.hidden)` bên
                // dưới chỉ giấu nền của *scroll view*; mỗi hàng vẫn tự tô nền
                // đục của nó và đè lên màu ta vừa đặt.
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            // Xám rất nhẹ chứ không phải đen tuyền, và đây không phải chuyện
            // thẩm mỹ: trên nền đen, một tấm card đen thu nhỏ lại là một tấm
            // card vô hình. Bản đầu của prototype này thu đúng 0.93 và bo góc
            // đúng 38 mà ảnh chụp không cho thấy gì cả.
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.09))
            .navigationTitle("Bài hát")
            .safeAreaInset(edge: .bottom) {
                // Chừa chỗ cho mini player, để dòng cuối không bị nó che.
                Color.clear.frame(height: 72)
            }
        }
    }
}

// MARK: - Màu trội từ ảnh thật

//  Trong app, `track.tint` nên đến từ chính ảnh bìa. Cách rẻ nhất là để
//  Core Image tính trung bình một lần rồi cache theo đường dẫn ảnh — đừng gọi
//  nó trong `body`:
//
//      import CoreImage
//
//      func dominantColour(of image: UIImage) -> Color {
//          guard let input = CIImage(image: image) else { return .gray }
//          let extent = CIVector(x: input.extent.origin.x, y: input.extent.origin.y,
//                                z: input.extent.size.width, w: input.extent.size.height)
//          guard let filter = CIFilter(name: "CIAreaAverage",
//                                      parameters: [kCIInputImageKey: input,
//                                                   kCIInputExtentKey: extent]),
//                let output = filter.outputImage else { return .gray }
//          var pixel = [UInt8](repeating: 0, count: 4)
//          CIContext(options: [.workingColorSpace: kCFNull as Any])
//              .render(output, toBitmap: &pixel, rowBytes: 4,
//                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
//                      format: .RGBA8, colorSpace: nil)
//          return Color(red: Double(pixel[0]) / 255,
//                       green: Double(pixel[1]) / 255,
//                       blue: Double(pixel[2]) / 255)
//      }

// MARK: - Preview

struct PlayerMorphPrototype_Previews: PreviewProvider {
    static var previews: some View {
        PlayerMorphPrototype()
            .preferredColorScheme(.dark)
    }
}

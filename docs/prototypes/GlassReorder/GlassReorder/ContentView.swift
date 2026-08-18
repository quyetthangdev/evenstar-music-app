//
//  ContentView.swift
//  Kéo thả sắp lại danh sách, kiểu Apple Music thời Liquid Glass. iOS 26+.
//
//  Tự chứa. Dán vào một project SwiftUI mới, đặt `ContentView()` làm root.
//
//  ─────────────────────────────────────────────────────────────────────────
//  MỘT MÔ HÌNH, KHÔNG CÓ SỐ HỌC KHUNG NÀO RẢI TRONG VIEW
//  ─────────────────────────────────────────────────────────────────────────
//  Vị trí mỗi hàng là **hàm thuần** của ba thứ trong `ReorderModel`: chỉ số của
//  nó trong mảng, hàng nào đang được nhấc, và chỗ trống hiện đang mở ở đâu.
//  Không view nào tự đo, tự nhớ, hay tự đặt vị trí cho mình.
//
//  Hệ quả đáng giá nhất: mọi trạng thái giữa chừng đều diễn đạt được bằng ba
//  con số, nên "chuyện gì đang xảy ra" luôn trả lời được mà không cần chạy thử.
//
//  ─────────────────────────────────────────────────────────────────────────
//  MẢNG CHỈ ĐỔI KHI THẢ
//  ─────────────────────────────────────────────────────────────────────────
//  Suốt cú kéo, `items` **không đổi**. Chỗ trống chỉ là hình vẽ: các hàng lân
//  cận lệch đi một ô. Điều đó giữ cho mọi thứ hoàn tác được — cú kéo bị hệ
//  thống cắt ngang thì không có gì phải hoàn tác, vì chưa có gì thay đổi.
//

import SwiftUI
import UIKit

// MARK: - Dữ liệu

struct Song: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let glyph: String
    let colours: [Color]

    static let playlist: [Song] = [
        .init(title: "Chiều nay không có mưa bay", artist: "Vũ.", glyph: "cloud.rain.fill",
              colours: [.init(red: 0.31, green: 0.45, blue: 0.72), .init(red: 0.16, green: 0.20, blue: 0.38)]),
        .init(title: "Có hẹn với thanh xuân", artist: "MONSTAR", glyph: "sun.max.fill",
              colours: [.init(red: 0.78, green: 0.45, blue: 0.22), .init(red: 0.42, green: 0.20, blue: 0.14)]),
        .init(title: "Nhất thời", artist: "Hoàng Dũng", glyph: "moon.stars.fill",
              colours: [.init(red: 0.40, green: 0.28, blue: 0.58), .init(red: 0.18, green: 0.14, blue: 0.32)]),
        .init(title: "Đông kiếm em", artist: "Nguyên Hà", glyph: "snowflake",
              colours: [.init(red: 0.20, green: 0.45, blue: 0.45), .init(red: 0.10, green: 0.22, blue: 0.24)]),
        .init(title: "Bước qua nhau", artist: "Vũ.", glyph: "figure.walk",
              colours: [.init(red: 0.52, green: 0.30, blue: 0.30), .init(red: 0.24, green: 0.14, blue: 0.16)]),
        .init(title: "Lạ lùng", artist: "Vũ.", glyph: "sparkles",
              colours: [.init(red: 0.30, green: 0.42, blue: 0.34), .init(red: 0.14, green: 0.22, blue: 0.18)]),
        .init(title: "Mùa mưa ngâu nằm cạnh", artist: "Vũ.", glyph: "drop.fill",
              colours: [.init(red: 0.26, green: 0.36, blue: 0.50), .init(red: 0.12, green: 0.18, blue: 0.28)]),
        .init(title: "Đông", artist: "Nguyên Hà", glyph: "wind",
              colours: [.init(red: 0.44, green: 0.44, blue: 0.50), .init(red: 0.20, green: 0.20, blue: 0.26)]),
        .init(title: "Tầng thượng 102", artist: "Cá Hồi Hoang", glyph: "building.2.fill",
              colours: [.init(red: 0.58, green: 0.34, blue: 0.42), .init(red: 0.26, green: 0.16, blue: 0.20)]),
        .init(title: "Nếu những tiếc nuối", artist: "Vũ.", glyph: "clock.fill",
              colours: [.init(red: 0.36, green: 0.30, blue: 0.62), .init(red: 0.16, green: 0.14, blue: 0.30)]),
        .init(title: "Ngồi", artist: "Vũ.", glyph: "chair.fill",
              colours: [.init(red: 0.62, green: 0.48, blue: 0.28), .init(red: 0.28, green: 0.22, blue: 0.14)]),
        .init(title: "Bình yên", artist: "Vũ.", glyph: "leaf.fill",
              colours: [.init(red: 0.28, green: 0.50, blue: 0.38), .init(red: 0.14, green: 0.24, blue: 0.20)])
    ]
}

// MARK: - Tham số

enum Metrics {
    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8
    /// Một "ô" là chiều cao hàng cộng khe. Mọi phép toán chỉ số quy về nó.
    static var slot: CGFloat { rowHeight + rowSpacing }

    static let liftScale: CGFloat = 1.05
    static let shadowRadius: CGFloat = 14
    static let shadowY: CGFloat = 10
    static let shadowOpacity: Double = 0.25
    static let corner: CGFloat = 12

    /// Cú nhấc. Ngắn và hơi nảy: nó là lời đáp cho ngón tay, không phải một
    /// vật đang đi tới đâu.
    static let lift = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// Các hàng nhường chỗ. Giảm chấn cao hơn — chúng đang dọn đường, và một
    /// cú nảy ở đó đọc ra như do dự.
    static let part = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Cú đáp. Xem `settle(velocity:distance:)` — nó còn mang theo quán tính.
    static let settleSpring = Spring(response: 0.4, dampingRatio: 0.78)

    /// 0.2 chứ không phải 0.25. Cùng với phản hồi lúc chạm (xem
    /// `pressGesture`), quãng chờ này không còn câm nên rút được mà vẫn phân
    /// biệt được với một cú vuốt cuộn.
    static let liftDelay: Double = 0.2
    /// Kéo quá đầu hoặc cuối thì chỉ đi tiếp 30%.
    static let overscroll: CGFloat = 0.3
    /// Vào trong bao nhiêu điểm kể từ mép thì bắt đầu tự cuộn.
    static let autoScrollZone: CGFloat = 80
    /// Tốc độ tự cuộn tối đa, điểm mỗi giây, đạt được ở sát mép.
    static let autoScrollMaxSpeed: CGFloat = 900
}

// MARK: - Mô hình

@Observable
final class ReorderModel {
    var items: [Song] = Song.playlist
    var isEditing = false

    /// Hàng đang được nhấc. `nil` nghĩa là không có phiên kéo nào.
    private(set) var draggedID: Song.ID?
    /// Quãng đường ngón tay đã đi, **đã** qua rubber band. Đây là con số hàng
    /// đang nhấc vẽ theo.
    private(set) var dragOffset: CGFloat = 0
    /// Chỗ trống hiện mở ở đâu.
    private(set) var targetIndex = 0
    /// Hàng xuất phát từ đâu. Cần nó vì mảng không đổi trong lúc kéo, nên chỉ
    /// số của hàng vẫn là chỉ số cũ.
    private(set) var sourceIndex = 0

    /// Quãng đường thô, chưa rubber band. Giữ riêng vì phép tự cuộn cộng thẳng
    /// vào nó.
    private var rawTranslation: CGFloat = 0

    var isDragging: Bool { draggedID != nil }

    // MARK: Vị trí — hàm thuần

    /// Độ lệch cần vẽ cho hàng ở chỉ số `index`.
    ///
    /// Ba trường hợp, và không có trường hợp thứ tư:
    ///
    ///   - hàng đang nhấc: bám ngón tay 1:1;
    ///   - hàng nằm giữa chỗ cũ và chỗ trống: lệch **đúng một ô**, ngược hướng
    ///     kéo, để nhường đường;
    ///   - còn lại: đứng yên.
    func offset(at index: Int) -> CGFloat {
        guard isDragging else { return 0 }
        if index == sourceIndex { return dragOffset }
        if sourceIndex < targetIndex, index > sourceIndex, index <= targetIndex {
            return -Metrics.slot
        }
        if sourceIndex > targetIndex, index >= targetIndex, index < sourceIndex {
            return Metrics.slot
        }
        return 0
    }

    // MARK: Phiên kéo

    func beginDrag(id: Song.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        draggedID = id
        sourceIndex = index
        targetIndex = index
        rawTranslation = 0
        dragOffset = 0
    }

    func updateDrag(translation: CGFloat) {
        rawTranslation = translation
        recompute()
    }

    /// Tự cuộn kéo nội dung đi dưới ngón tay, nên quãng đường trong **không
    /// gian nội dung** phải tăng theo đúng lượng ấy — nếu không, hàng đang nhấc
    /// sẽ trôi khỏi ngón tay đúng bằng phần đã cuộn.
    func absorbAutoScroll(_ delta: CGFloat) {
        rawTranslation += delta
        recompute()
    }

    private func recompute() {
        // **Ngưỡng là điểm giữa, không phải mép.**
        //
        // `rawTranslation / slot` là số ô đã đi qua, và `.rounded()` lật khi
        // vượt qua **nửa** ô — tức đúng lúc tâm hàng đang nhấc vượt tâm hàng
        // kế bên. Dùng mép thay vì điểm giữa thì ở ranh giới, một dao động vài
        // điểm của ngón tay sẽ lật qua lật lại: nhấp nháy.
        //
        // Chỗ trống được kẹp vào mảng; phần vượt ra ngoài đi vào rubber band
        // bên dưới chứ không đẩy chỉ số ra ngoài biên.
        let slots = rawTranslation / Metrics.slot
        let wanted = sourceIndex + Int(slots.rounded())
        targetIndex = min(max(wanted, 0), items.count - 1)

        // Rubber band: phần kéo vượt quá ô đầu hoặc ô cuối chỉ đi tiếp 30%.
        let lowerBound = CGFloat(-sourceIndex) * Metrics.slot
        let upperBound = CGFloat(items.count - 1 - sourceIndex) * Metrics.slot
        if rawTranslation < lowerBound {
            dragOffset = lowerBound + (rawTranslation - lowerBound) * Metrics.overscroll
        } else if rawTranslation > upperBound {
            dragOffset = upperBound + (rawTranslation - upperBound) * Metrics.overscroll
        } else {
            dragOffset = rawTranslation
        }
    }

    /// Lò xo cho cú đáp, tính **trước** khi biến đổi gì.
    ///
    /// Tách khỏi việc chốt là bắt buộc, không phải cho gọn: nó đọc `targetIndex`,
    /// `sourceIndex` và `dragOffset` ở trạng thái *trước* cú thả, mà chốt xong
    /// thì cả ba đã bị xoá.
    func settleAnimation(velocity: CGFloat) -> Animation {
        let distance = CGFloat(targetIndex - sourceIndex) * Metrics.slot - dragOffset
        return Self.settle(velocity: velocity, distance: distance)
    }

    /// Chốt cú kéo. Mảng đổi **ở đây và chỉ ở đây**.
    ///
    /// **Phải gọi bên trong `withAnimation`.** Bản trước gộp cả tính lò xo lẫn
    /// biến đổi vào một hàm rồi viết:
    ///
    ///     let animation = model.endDrag(velocity: …)
    ///     withAnimation(animation) {}          // ← thân rỗng
    ///
    /// Biến đổi nằm trong `defer`, tức chạy lúc hàm **trả về** — trước khi khối
    /// `withAnimation` bắt đầu. Nên nó không nằm trong transaction nào, và hàng
    /// nhảy thẳng sang ô mới thay vì đáp xuống. Đo trên video: suốt cú kéo thay
    /// đổi mỗi khung là 2–7, đúng khung buông tay vọt lên 15.
    func commitDrop() {
        if let draggedID, let from = items.firstIndex(where: { $0.id == draggedID }) {
            let to = targetIndex > from ? targetIndex + 1 : targetIndex
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        }
        draggedID = nil
        rawTranslation = 0
        dragOffset = 0
    }

    /// Huỷ: bay về đúng ô cũ, mảng không đổi. Cũng phải gọi trong
    /// `withAnimation`, cùng lý do với `commitDrop`.
    func cancelDrag() {
        draggedID = nil
        rawTranslation = 0
        dragOffset = 0
        targetIndex = sourceIndex
    }

    /// `initialVelocity` tính theo **đơn vị của giá trị đang animate mỗi giây**,
    /// mà giá trị ở đây là độ lệch tính bằng điểm — nên vận tốc điểm/giây phải
    /// chia cho quãng đường còn lại. Nhét thẳng điểm/giây vào là một cú giật
    /// văng khỏi màn hình.
    private static func settle(velocity: CGFloat, distance: CGFloat) -> Animation {
        guard abs(distance) > 0.5 else { return .spring(Metrics.settleSpring) }
        let unit = Double(velocity / distance)
        return .interpolatingSpring(Metrics.settleSpring,
                                    initialVelocity: min(max(unit, -18), 18))
    }
}

// MARK: - Màn hình

struct ContentView: View {
    @State private var model = ReorderModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Hàng đang bị ngón tay đè, kể cả khi chưa đủ lâu để nhấc.
    @GestureState private var pressedID: Song.ID?

    /// Vị trí cuộn, để phép tự cuộn ở Phase 3 lái được.
    @State private var scrollPosition = ScrollPosition()
    @State private var contentOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var autoScroll: Task<Void, Never>?

    private let haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    rows
                }
            }
            .scrollPosition($scrollPosition)
            // Trong lúc kéo, cuộn do phép tự cuộn lái — để ngón tay cuộn được
            // nữa thì hai thứ tranh nhau cùng một trục.
            .scrollDisabled(model.isDragging)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
                contentOffset = geometry.contentOffset.y
                viewportHeight = geometry.containerSize.height
            }
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isEditing ? "Xong" : "Sửa") {
                        withAnimation(Metrics.part) { model.isEditing.toggle() }
                    }
                }
            }
        }
        .onAppear { haptics.prepare() }
    }

    // MARK: Đầu trang

    private var header: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.indigo, .black],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 180, height: 180)
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            Text("Nghe khi trời mưa").font(.title2.weight(.semibold))
            Text("12 bài").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: Danh sách

    private var rows: some View {
        VStack(spacing: Metrics.rowSpacing) {
            // **Thân này không đọc `offset(at:)`.**
            //
            // `offset(at:)` chạm vào `dragOffset`, và `@Observable` theo dõi ở
            // mức *thân view nào đã đọc thuộc tính nào*. Đọc nó ở đây thì cả
            // `VStack` 12 con dựng lại mỗi khung ngón tay nhích — đó là cái ì
            // thứ nhất, và nó không hiện ra ở số đo khung hình vì mỗi lượt
            // dựng vẫn kịp trong một khung; nó chỉ ăn hết ngân sách.
            //
            // Đẩy phép đọc xuống `RowSlot` thì mỗi khung chỉ **một** hàng dựng
            // lại: hàng đang nhấc. Những hàng khác đọc `targetIndex`, thứ chỉ
            // đổi khi vượt qua điểm giữa.
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, song in
                RowSlot(model: model, index: index, song: song,
                        pressed: pressedID == song.id, reduceMotion: reduceMotion)
                    .gesture(gesture(for: song, at: index))
                    .simultaneousGesture(pressGesture(for: song))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    /// Phản hồi ngay khi ngón tay chạm xuống, **trước** khi cú giữ đạt.
    ///
    /// Cái ì thứ hai: ở chế độ thường phải giữ 0.2s mới nhấc được, và suốt
    /// quãng đó màn hình câm lặng. Người dùng không đọc ra "đang chờ đủ thời
    /// gian", họ đọc ra "bấm không ăn".
    ///
    /// `DragGesture(minimumDistance: 0)` nổ ngay lúc chạm. `@GestureState` tự
    /// dọn khi ngón tay rời, nên không có trạng thái nào phải nhớ xoá.
    private func pressGesture(for song: Song) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressedID) { _, state, _ in state = song.id }
    }


    // MARK: Cử chỉ

    /// Hai đường vào, đúng như Apple Music.
    ///
    ///   - **Chế độ sửa:** chạm vào tay cầm là kéo **ngay**, không chờ. Tay cầm
    ///     đã là lời tuyên bố ý định rồi, bắt giữ thêm 0.25s nữa là bắt chờ vô
    ///     cớ.
    ///   - **Bình thường:** giữ 0.25s ở bất kỳ đâu trên hàng. Cửa này tồn tại
    ///     để một cú vuốt cuộn danh sách không bị hiểu thành nhấc hàng.
    private func gesture(for song: Song, at index: Int) -> some Gesture {
        // **Nối tuần tự, một cái van duy nhất.**
        //
        // Bản trước dùng `.simultaneously`: cú kéo chạy song song với cú giữ và
        // tự chặn mình bằng `guard isEditing`. Hệ quả là ở chế độ thường, nếu
        // ngón tay nhúc nhích trước khi đủ 0.25s thì cú giữ hỏng và **không có
        // gì bắt đầu cả** — người dùng đọc ra là ì.
        //
        // `sequenced` chỉ mở cửa cho cú kéo sau khi cú giữ đã thành công, và
        // thời lượng giữ chính là cái van: 0 ở chế độ sửa (chạm tay cầm là kéo
        // ngay), 0.25s ở chế độ thường (để một cú vuốt cuộn danh sách không bị
        // hiểu thành nhấc hàng).
        LongPressGesture(minimumDuration: model.isEditing ? 0 : Metrics.liftDelay)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    begin(song)
                case .second(true, let drag?):
                    if !model.isDragging { begin(song) }
                    model.updateDrag(translation: drag.translation.height)
                    updateAutoScroll()
                default:
                    break
                }
            }
            .onEnded { value in
                stopAutoScroll()
                guard model.isDragging else { return }
                let velocity: CGFloat
                if case .second(true, let drag?) = value { velocity = drag.velocity.height }
                else { velocity = 0 }
                let settle = model.settleAnimation(velocity: velocity)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : settle) {
                    model.commitDrop()
                }
                haptics.impactOccurred()
            }
    }

    private func begin(_ song: Song) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : Metrics.lift) {
            model.beginDrag(id: song.id)
        }
        haptics.impactOccurred()
    }

    // MARK: Phase 3 — tự cuộn

    /// Chạy khi hàng đang nhấc lại gần mép vùng nhìn thấy.
    ///
    /// Tốc độ **tăng dần theo độ gần**, bình phương: ở 80pt gần như đứng yên,
    /// sát mép thì nhanh. Tuyến tính thì ở rìa vùng đã trôi rõ rệt, và người
    /// dùng chỉ muốn đưa hàng tới đó chứ chưa muốn cuộn.
    private func updateAutoScroll() {
        let liftedCentreInViewport = liftedCentreY - contentOffset
        let topGap = liftedCentreInViewport
        let bottomGap = viewportHeight - liftedCentreInViewport

        let speed: CGFloat
        if topGap < Metrics.autoScrollZone {
            let t = max(0, 1 - topGap / Metrics.autoScrollZone)
            speed = -t * t * Metrics.autoScrollMaxSpeed
        } else if bottomGap < Metrics.autoScrollZone {
            let t = max(0, 1 - bottomGap / Metrics.autoScrollZone)
            speed = t * t * Metrics.autoScrollMaxSpeed
        } else {
            speed = 0
        }

        guard speed != 0 else { return stopAutoScroll() }
        guard autoScroll == nil else { return }

        autoScroll = Task { @MainActor in
            var last = CACurrentMediaTime()
            while !Task.isCancelled, model.isDragging {
                try? await Task.sleep(for: .milliseconds(16))
                let now = CACurrentMediaTime()
                let dt = CGFloat(now - last)
                last = now
                let delta = currentAutoScrollSpeed() * dt
                guard delta != 0 else { break }
                contentOffset += delta
                scrollPosition.scrollTo(y: contentOffset)
                // Nội dung vừa trôi dưới ngón tay: quãng đường trong không gian
                // nội dung phải tăng đúng bằng vậy, nếu không hàng sẽ tụt lại.
                model.absorbAutoScroll(delta)
            }
            autoScroll = nil
        }
    }

    private func currentAutoScrollSpeed() -> CGFloat {
        let centre = liftedCentreY - contentOffset
        if centre < Metrics.autoScrollZone {
            let t = max(0, 1 - centre / Metrics.autoScrollZone)
            return -t * t * Metrics.autoScrollMaxSpeed
        }
        let bottom = viewportHeight - centre
        if bottom < Metrics.autoScrollZone {
            let t = max(0, 1 - bottom / Metrics.autoScrollZone)
            return t * t * Metrics.autoScrollMaxSpeed
        }
        return 0
    }

    /// Tâm hàng đang nhấc, trong không gian nội dung.
    private var liftedCentreY: CGFloat {
        CGFloat(model.sourceIndex) * Metrics.slot + Metrics.rowHeight / 2
            + model.dragOffset + headerHeight
    }

    /// Chiều cao khối đầu trang, cộng lề. Hằng số vì đầu trang cố định — nếu nó
    /// thành co giãn thì đo bằng `onGeometryChange` và đưa vào state.
    private var headerHeight: CGFloat { 180 + 12 + 26 + 20 + 8 + 24 }

    private func stopAutoScroll() {
        autoScroll?.cancel()
        autoScroll = nil
    }
}

// MARK: - Ô chứa một hàng

/// Lớp mỏng giữa danh sách và hàng, và nó tồn tại **chỉ để thu hẹp phạm vi
/// theo dõi**.
///
/// `offset(at:)` chạm vào `dragOffset` khi và chỉ khi chỉ số đúng bằng hàng
/// đang nhấc. Vì `@Observable` theo dõi theo từng thân view, đặt phép đọc ấy ở
/// đây nghĩa là mỗi khung chỉ một `RowSlot` dựng lại. Đặt nó ở danh sách thì cả
/// mười hai cùng dựng.
private struct RowSlot: View {
    let model: ReorderModel
    let index: Int
    let song: Song
    let pressed: Bool
    let reduceMotion: Bool

    var body: some View {
        let lifted = song.id == model.draggedID
        SongRow(song: song, showsHandle: model.isEditing, lifted: lifted,
             pressed: pressed && !lifted, reduceMotion: reduceMotion)
            .frame(height: Metrics.rowHeight)
            .offset(y: model.offset(at: index))
            // **Một property, animate mãi cùng nó — điều kiện để lò xo *đổi
            // đích* thay vì chạy nốt.** Đảo chiều giữa chừng thì `offset(at:)`
            // trả giá trị mới, SwiftUI nhắm lại cùng con số ấy và giữ nguyên
            // vận tốc đang có. Chuỗi hoá bằng completion handler thì cú đảo
            // chiều phải xếp hàng đợi cú trước chạy xong.
            //
            // Hàng đang nhấc không animate độ lệch: nó bám ngón tay 1:1.
            .animation(lifted ? nil : partAnimation, value: model.targetIndex)
            .animation(lifted ? nil : partAnimation, value: model.draggedID)
            .zIndex(lifted ? 1 : 0)
    }

    private var partAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : Metrics.part
    }
}

// MARK: - Hàng

/// `Equatable` với đúng những gì nó vẽ, nên một hàng không đổi thì không chạy
/// lại `body` khi hàng khác đổi chỗ.
private struct SongRow: View, Equatable {
    let song: Song
    let showsHandle: Bool
    let lifted: Bool
    /// Ngón tay đang đè nhưng chưa nhấc. Một cú co nhẹ, tức thì.
    let pressed: Bool
    let reduceMotion: Bool

    static func == (lhs: SongRow, rhs: SongRow) -> Bool {
        lhs.song.id == rhs.song.id
            && lhs.showsHandle == rhs.showsHandle
            && lhs.lifted == rhs.lifted
            && lhs.pressed == rhs.pressed
            && lhs.reduceMotion == rhs.reduceMotion
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: song.colours,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: song.glyph)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.subheadline).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(background)
        .scaleEffect(lifted ? Metrics.liftScale : (pressed ? 0.97 : 1))
        // Cú co lúc đè phải **nhanh hơn hẳn** cú nhấc: nó là biên nhận cho ngón
        // tay, không phải một vật đang đi tới đâu.
        .animation(.easeOut(duration: 0.12), value: pressed)
        .shadow(color: .black.opacity(lifted ? Metrics.shadowOpacity : 0),
                radius: lifted ? Metrics.shadowRadius : 0,
                y: lifted ? Metrics.shadowY : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : Metrics.lift, value: lifted)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if lifted && !reduceMotion {
            // Hàng đang nhấc là một tấm kính: những hàng nó bay qua khúc xạ qua
            // nó. Reduce Motion thì bỏ — khúc xạ là chuyển động thị giác.
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Metrics.corner))
        } else {
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

// MARK: - Stretch: xếp chồng nhiều bài
//
// Chưa làm, và đây là hình dạng của nó nếu làm:
//
//   - `ReorderModel` thêm `stackedIDs: [Song.ID]`. Chạm một hàng khác trong lúc
//     đang kéo thì thêm id vào đó thay vì bắt đầu phiên mới.
//   - Mỗi hàng trong `stackedIDs` vẽ dưới tấm kính đang nhấc, lệch 4pt và xoay
//     1.5° tăng dần, cùng một huy hiệu đếm ở góc.
//   - Lúc thả, chèn cả cụm tại `targetIndex` rồi cho chúng xoè ra bằng cách
//     hoãn animation mỗi phần tử thêm 40ms — `withAnimation(.delay(0.04 * i))`.
//
// Phần khó không nằm ở hình vẽ mà ở chỗ trống: chỗ trống phải rộng bằng **cả
// cụm**, nên `offset(at:)` phải nhân theo số phần tử đang giữ chứ không còn là
// một ô. Đó là lý do nó chưa nằm ở đây — nó đổi bất biến trung tâm của mô hình.

#Preview {
    ContentView()
}

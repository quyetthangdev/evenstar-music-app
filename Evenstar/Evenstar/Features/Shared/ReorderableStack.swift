import SwiftUI
import UIKit

/// Một danh sách kéo thả được, tự dựng cử chỉ và tự dựng chuyển động.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO CỬ CHỈ LÀ CỦA UIKIT
/// ─────────────────────────────────────────────────────────────────────────
/// Bản đầu dùng `LongPressGesture.sequenced(before: DragGesture)` trên từng
/// hàng. Nó trễ và chập chờn, và không knob nào chữa được, vì hỏng ở ba chỗ mà
/// SwiftUI không phơi ra:
///
/// **Cú giữ của SwiftUI hỏng khi ngón tay nhích.** Nó không có thứ tương đương
/// `allowableMovement` để nới. Đặt trong `ScrollView`, cú pan của scroll thắng
/// ngay khi có chuyển động, nên một ngón tay run nhẹ trước mốc thời gian không
/// làm cú giữ *trễ* — nó làm cú giữ **không xảy ra**.
///
/// **`.sequenced` có điểm bàn giao.** Cú kéo chỉ bắt đầu đo sau khi cú giữ
/// xong, nên quãng ngón tay đi trong lúc bàn giao bị mất: ì ở đầu.
///
/// **Mỗi hàng một cử chỉ.** Hai chục hàng × ba recogniser cùng tranh một ngón
/// tay.
///
/// Nên ở đây là **hai** `UILongPressGestureRecognizer`, gắn một lần cho cả danh
/// sách, qua `UIGestureRecognizerRepresentable` (iOS 18+):
///
///   · `press` — `minimumPressDuration = 0`, chạy song song với mọi thứ. Bật
///     nền, và nhận cú chạm. Y như highlight của `UITableView`.
///   · `lift`  — `minimumPressDuration` 0.18, `allowableMovement` 12. `.began`
///     là nhấc, `.changed` là kéo, `.ended` là thả. **Một** recogniser lo cả
///     ba, nên không còn điểm bàn giao nào để mất quãng đường.
///
/// `allowableMovement` là mấu chốt: ngón tay được phép run trong 12 điểm suốt
/// 0.18s mà cú nhấc vẫn tính. Đi quá thì recogniser hỏng và danh sách cuộn bình
/// thường — đúng phân xử của `UITableView`, và là thứ SwiftUI không cho.
///
/// ─────────────────────────────────────────────────────────────────────────
/// HAI BẤT BIẾN GIỮ CHO PHẦN CÒN LẠI ĐƠN GIẢN
/// ─────────────────────────────────────────────────────────────────────────
/// **Vị trí là hàm thuần.** Độ lệch của mỗi hàng suy ra từ ba con số: chỉ số
/// của nó, hàng nào đang nhấc, chỗ trống đang ở đâu. Không view nào tự đo hay
/// tự nhớ vị trí của mình.
///
/// **Thứ tự chỉ đổi khi thả, và chỉ khi hàng đã bay tới nơi.** Suốt cú kéo thứ
/// tự đứng yên; chỗ trống thuần là hình vẽ. Nên một cú kéo bị cắt ngang không
/// để lại gì phải dọn. Xem `ReorderModel.liftEnded()` về lý do phần thứ hai của
/// câu này là bắt buộc chứ không phải cho gọn.
struct ReorderableStack<Row: View>: View {

    /// Thứ tự hiện tại, theo cái nhìn của người gọi. Trong lúc kéo, thay đổi từ
    /// đây bị bỏ qua — xem `ReorderModel.adopt(_:)`.
    let ids: [UUID]
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    /// Bật suốt từ lúc nhấc tới lúc hàng đáp xong. Người gọi dùng nó để tắt
    /// những cử chỉ bao ngoài mà một cú kéo dọc sẽ vô tình kích hoạt.
    @Binding var isReordering: Bool
    let onTap: (UUID) -> Void
    /// Quy ước của `move(fromOffsets:toOffset:)`: `to` là chỉ số trong mảng
    /// **trước khi** phần tử bị lấy ra.
    let onMove: (Int, Int) -> Void
    /// Nội dung một hàng, kèm hai trạng thái để nó tự quyết định bộ mặt.
    @ViewBuilder let row: (UUID, _ lifted: Bool, _ pressed: Bool) -> Row

    @State private var model = ReorderModel()
    /// Mép trên của danh sách trong hệ toạ độ cửa sổ.
    ///
    /// Đo **trong lượt cập nhật view** rồi giữ lại, để callback của recogniser
    /// chỉ phải trừ một số — xem `ReorderLongPress` về việc hỏi SwiftUI toạ độ
    /// từ trong callback ấy làm app abort.
    @State private var listOriginY: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: rowSpacing) {
                // Thân này **không đọc** `offset(at:)`. Hàm đó chạm vào
                // `dragOffset`, và `@Observable` theo dõi theo từng thân view —
                // đọc ở đây thì cả danh sách dựng lại mỗi khung ngón tay nhích.
                // Đẩy xuống `Slot` thì mỗi khung chỉ một hàng dựng lại: hàng
                // đang nhấc.
                ForEach(Array(model.order.enumerated()), id: \.element) { index, id in
                    Slot(model: model, index: index, id: id, height: rowHeight, row: row)
                }
            }
            // Cả khối là một vùng chạm liền, kể cả khoảng hở giữa các hàng: hai
            // recogniser gắn ở đây, và chúng chỉ nhận được cú chạm nằm trong
            // vùng chạm của chính view này.
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                listOriginY = $0
            }
            .gesture(ReorderLongPress(minimumDuration: 0,
                                      allowableMovement: .greatestFiniteMagnitude) { state, point in
                switch state {
                case .began: model.pressBegan(atY: point.y - listOriginY)
                case .changed: model.pressMoved(toY: point.y - listOriginY)
                case .ended: model.pressEnded(committing: true)
                case .cancelled, .failed: model.pressEnded(committing: false)
                default: break
                }
            })
            .gesture(ReorderLongPress(minimumDuration: ReorderTuning.holdToLift,
                                      allowableMovement: ReorderTuning.holdSlop) { state, point in
                switch state {
                case .began: model.liftBegan(atY: point.y - listOriginY)
                case .changed: model.liftMoved(toY: point.y - listOriginY)
                case .ended, .cancelled, .failed: model.liftEnded()
                default: break
                }
            })
        }
        // Đã nhấc thì ngón tay là của hàng, không phải của scroll. Tắt cuộn ở
        // đây huỷ luôn cú pan nếu nó vừa kịp bắt đầu.
        .scrollDisabled(model.isDragging)
        // **Không có thanh cuộn**, và nó là thuộc tính của kiểu danh sách này
        // chứ không phải sở thích của một chỗ gọi.
        //
        // Hàng ở đây có tay cầm kéo nằm sát mép phải, và thanh cuộn của SwiftUI
        // vẽ đè lên đúng chỗ ấy — hai thứ nhỏ chồng nhau ở cùng một mép. Nó
        // cũng vẽ đè lên cả cái thẻ của hàng đang được nhấc.
        //
        // Bản UIKit trước đây tắt nó bằng `showsVerticalScrollIndicator = false`
        // vì cùng lý do; dòng ấy mất khi danh sách chuyển sang SwiftUI.
        .scrollIndicators(.hidden)
        .onAppear {
            model.slot = rowHeight + rowSpacing
            model.onTap = onTap
            model.onMove = onMove
            model.adopt(ids)
        }
        .onChange(of: ids) { model.adopt(ids) }
        .onChange(of: model.isDragging) { isReordering = model.isDragging }
    }
}

// MARK: - Tham số

enum ReorderTuning {
    /// Nhấn giữ bao lâu thì nhấc, và ngón tay được run bao nhiêu trong lúc ấy.
    /// UIKit đo cả hai; con số thứ hai mới là cái quyết định cảm giác ổn định.
    static let holdToLift: Double = 0.18
    static let holdSlop: CGFloat = 12

    /// Quá ngần này thì cú chạm là để cuộn: tắt nền, và không tính là chạm.
    static let scrollSlop: CGFloat = 10

    /// Các hàng nhường chỗ. `dampingFraction` 0.68 để có **chút vọt lố** — đó
    /// là cái đàn hồi nhẹ; 1.0 thì chúng trượt tới nơi rồi đứng, đọc ra như cửa
    /// trượt chứ không như vật có khối lượng.
    static let part = Animation.spring(response: 0.28, dampingFraction: 0.68)

    /// Nền hiện ra lúc chạm. Nhanh và không nảy: đây là biên nhận, không phải
    /// chuyển động.
    static let press = Animation.easeOut(duration: 0.14)

    /// Cú đáp lúc thả. Xem `ReorderModel.settleAnimation(distance:velocity:)`.
    static let settleSpring = Spring(response: 0.34, dampingRatio: 0.76)

    static let corner: CGFloat = 12
}

// MARK: - Mô hình

/// Trạng thái một phiên kéo, và máy trạng thái mà hai recogniser gọi vào.
///
/// Cử chỉ nằm ở đây chứ không ở view vì đây là chỗ duy nhất biết đủ để trả lời
/// "chạm vào đâu là hàng nào" — và vì một máy trạng thái thì đọc được thành
/// lời, còn một chuỗi `.onChanged` lồng nhau thì không.
@Observable
final class ReorderModel {

    /// Thứ tự **của riêng danh sách này**, không phải của người gọi.
    ///
    /// Tách ra vì cú đổi chỗ phải thấy được ngay trong khung hình mà cú đáp kết
    /// thúc, còn thứ tự của người gọi thì tới sau một vòng cập nhật. Một khung
    /// hình lệch nhịp ở đúng chỗ ấy là một cú nháy.
    private(set) var order: [UUID] = []

    /// Hàng đang bị ngón tay đè, kể cả khi chưa đủ lâu để nhấc.
    private(set) var pressedID: UUID?
    private(set) var draggedID: UUID?
    /// Quãng đường ngón tay đã đi kể từ lúc nhấc.
    private(set) var dragOffset: CGFloat = 0
    /// Chỗ trống đang mở ở đâu.
    private(set) var targetIndex = 0
    /// Hàng xuất phát từ đâu — cần vì thứ tự không đổi trong lúc kéo.
    private(set) var sourceIndex = 0
    /// Ngón tay đã rời, hàng đang bay về ô đích. Vẫn là một phiên kéo — phép
    /// toán ô vẫn chạy — nhưng hàng thôi trông như đang được nhấc.
    private(set) var isSettling = false

    var isDragging: Bool { draggedID != nil }

    @ObservationIgnored var slot: CGFloat = 1
    @ObservationIgnored var onTap: (UUID) -> Void = { _ in }
    @ObservationIgnored var onMove: (Int, Int) -> Void = { _, _ in }

    /// Nơi ngón tay đặt xuống, để đo quãng đường. Hai recogniser hai gốc riêng,
    /// vì chúng bắt đầu ở hai thời điểm khác nhau.
    @ObservationIgnored private var pressOriginY: CGFloat = 0
    @ObservationIgnored private var liftOriginY: CGFloat = 0
    @ObservationIgnored private var lastSample: (y: CGFloat, t: CFTimeInterval)?
    @ObservationIgnored private var velocity: CGFloat = 0
    /// Vé cho cú đáp đang chạy. Nhấc hàng mới giữa chừng thì `commit()` cắt vé,
    /// và closure hoàn tất của cú đáp cũ — vẫn sẽ nổ — thấy vé sai nên đứng im
    /// thay vì xoá `dragOffset` của phiên mới.
    @ObservationIgnored private var settleToken = 0

    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .light)

    /// Nhận thứ tự mới từ người gọi.
    ///
    /// **Bỏ qua trong lúc kéo.** Hàng đợi đổi vì rất nhiều lý do không liên
    /// quan tới ngón tay đang giữ — bài hết, người dùng bấm bài khác từ nơi
    /// khác — và một thứ tự mới ập vào giữa cú kéo sẽ giật hàng ra khỏi tay.
    /// Thay đổi bị bỏ qua sẽ tới ở lượt `onChange` sau khi chốt.
    func adopt(_ ids: [UUID]) {
        guard !isDragging, ids != order else { return }
        order = ids
    }

    // MARK: Vẽ

    /// Độ lệch cần vẽ cho hàng ở `index`. Ba trường hợp, không có trường hợp
    /// thứ tư: hàng đang nhấc bám ngón tay; hàng nằm giữa chỗ cũ và chỗ trống
    /// lệch đúng một ô để nhường đường; còn lại đứng yên.
    func offset(at index: Int) -> CGFloat {
        guard isDragging else { return 0 }
        if index == sourceIndex { return dragOffset }
        if sourceIndex < targetIndex, index > sourceIndex, index <= targetIndex { return -slot }
        if sourceIndex > targetIndex, index >= targetIndex, index < sourceIndex { return slot }
        return 0
    }

    // MARK: Recogniser "press" — cái nền, và cú chạm

    func pressBegan(atY y: CGFloat) {
        haptics.prepare()
        pressOriginY = y
        guard let index = index(atY: y) else { return }
        withAnimation(ReorderTuning.press) { pressedID = order[index] }
    }

    func pressMoved(toY y: CGFloat) {
        // Đi quá xa mà chưa nhấc nghĩa là người dùng đang cuộn, không phải đang
        // giữ. Tắt nền đi — nếu không nó sáng suốt cú cuộn — và cú chạm cũng
        // không còn là cú chạm.
        guard !isDragging, abs(y - pressOriginY) > ReorderTuning.scrollSlop else { return }
        clearPress()
    }

    /// `committing` phân biệt ngón tay nhả ra với cú chạm bị hệ thống cắt.
    func pressEnded(committing: Bool) {
        guard !isDragging else { return }
        let tapped = pressedID
        clearPress()
        if committing, let tapped { onTap(tapped) }
    }

    private func clearPress() {
        guard pressedID != nil else { return }
        withAnimation(ReorderTuning.press) { pressedID = nil }
    }

    // MARK: Recogniser "lift" — nhấc, kéo, thả

    func liftBegan(atY y: CGFloat) {
        // Cú đáp trước còn đang bay thì chốt nó ngay tại chỗ. Nó đã ở đúng vị
        // trí cuối rồi (xem `liftEnded`), nên chốt sớm không thấy được.
        if isSettling { commit() }
        guard let index = index(atY: y) else { return }
        liftOriginY = y
        lastSample = (y, CACurrentMediaTime())
        velocity = 0
        withAnimation(ReorderTuning.part) {
            draggedID = order[index]
            pressedID = order[index]
            sourceIndex = index
            targetIndex = index
            dragOffset = 0
        }
        haptics.impactOccurred()
    }

    func liftMoved(toY y: CGFloat) {
        guard isDragging, !isSettling else { return }
        // **Ngoài mọi `withAnimation`.** Hàng đang nhấc bám ngón tay 1:1; một
        // lò xo ở đây là một khoảng trễ giữa ngón tay và hàng.
        dragOffset = y - liftOriginY

        let now = CACurrentMediaTime()
        if let last = lastSample, now > last.t {
            // Làm trơn: một mẫu đơn lẻ ngay trước lúc nhả tay hay là nhiễu, và
            // nhiễu ấy đi thẳng vào vận tốc ban đầu của lò xo.
            let instant = (y - last.y) / CGFloat(now - last.t)
            velocity = velocity * 0.4 + instant * 0.6
        }
        lastSample = (y, now)

        // **Ngưỡng là điểm giữa.** `dragOffset / slot` là số ô đã đi qua, và
        // `.rounded()` lật khi vượt **nửa** ô — đúng lúc tâm hàng đang nhấc
        // vượt tâm hàng kế bên. So mép thì ở ranh giới, một dao động vài điểm
        // của ngón tay lật qua lật lại: nhấp nháy.
        let wanted = min(max(sourceIndex + Int((dragOffset / slot).rounded()), 0), order.count - 1)
        // Chỉ *chỗ trống* mới có lò xo, và chỉ khi nó thật sự dời.
        if wanted != targetIndex {
            withAnimation(ReorderTuning.part) { targetIndex = wanted }
        }
    }

    /// Thả.
    ///
    /// **Hàng bay về đích bằng `dragOffset`, không bằng việc đổi thứ tự.** Đây
    /// là điểm mấu chốt. Đổi thứ tự ngay lúc này thì `LazyVStack` dời hàng sang
    /// ô đích *đồng thời* `dragOffset` tan về 0 — hai đại lượng cộng vào nhau,
    /// và nếu chúng chạy hai lò xo khác nhau thì tổng giật ngược. Đo được trên
    /// bản trước: hàng nhảy 24 điểm về phía ô nguồn ngay khung sau khi nhả tay.
    ///
    /// Nên ở đây chỉ **một** đại lượng động. Hàng vẫn nằm ở ô nguồn,
    /// `dragOffset` chạy tới đúng khoảng cách sang ô đích. Đổi thứ tự để lúc
    /// sau, khi mọi hàng đã ở đúng vị trí cuối.
    func liftEnded() {
        guard isDragging, !isSettling else { return }
        // Ngón tay đứng yên một lúc rồi mới nhả thì mẫu cuối đã cũ; dùng nó là
        // ném hàng đi theo một cú vẩy đã kết thúc từ lâu.
        if let last = lastSample, CACurrentMediaTime() - last.t > 0.05 { velocity = 0 }
        lastSample = nil

        let destination = CGFloat(targetIndex - sourceIndex) * slot
        let settle = settleAnimation(distance: destination - dragOffset, velocity: velocity)
        // Thôi trông như đang nhấc — thu về, tắt bóng, tắt nền — nhưng vẫn là
        // một phiên kéo, nên phép toán ô không đổi dưới chân cú đáp.
        withAnimation(ReorderTuning.part) {
            isSettling = true
            pressedID = nil
        }
        let token = settleToken
        withAnimation(settle) {
            dragOffset = destination
        } completion: { [weak self] in
            guard let self, self.settleToken == token else { return }
            self.commit()
        }
        haptics.impactOccurred()
    }

    // MARK: Trong

    private func index(atY y: CGFloat) -> Int? {
        let index = Int(floor(y / slot))
        return order.indices.contains(index) ? index : nil
    }

    private func settleAnimation(distance: CGFloat, velocity: CGFloat) -> Animation {
        guard abs(distance) > 0.5 else { return .spring(ReorderTuning.settleSpring) }
        // `initialVelocity` tính theo đơn vị của giá trị đang animate mỗi giây;
        // giá trị ở đây là độ lệch tính bằng điểm, nên điểm/giây phải chia cho
        // quãng đường còn lại. Kẹp lại để một cú hất mạnh không văng ra ngoài.
        let unit = Double(velocity / distance)
        return .interpolatingSpring(ReorderTuning.settleSpring,
                                    initialVelocity: min(max(unit, -14), 14))
    }

    /// Chốt. Thứ tự đổi ở đây và chỉ ở đây.
    ///
    /// **Phải chạy với animation tắt**, và phải đợi cú đáp xong. Lúc ấy hàng
    /// đang nhấc nằm ở `slot(nguồn) + (đích − nguồn) × slot` = `slot(đích)`,
    /// còn mỗi hàng nhường chỗ nằm lệch đúng một ô so với ô của nó — nghĩa là
    /// mọi hàng đã ở đúng chỗ mà thứ tự mới sẽ đặt chúng vào. Đổi thứ tự và xoá
    /// hết độ lệch cho ra y hệt khung hình vừa rồi: không một điểm ảnh nào dời.
    private func commit() {
        settleToken &+= 1
        var from: Int?
        var to: Int?
        var silent = Transaction()
        silent.disablesAnimations = true
        withTransaction(silent) {
            if let draggedID, let source = order.firstIndex(of: draggedID) {
                let destination = targetIndex > source ? targetIndex + 1 : targetIndex
                order.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
                from = source
                to = destination
            }
            draggedID = nil
            dragOffset = 0
            isSettling = false
        }
        // Ngoài transaction câm: đây là lượt báo cho model của app, và những gì
        // *nó* làm — animation trong màn hình khác chẳng hạn — không việc gì
        // phải im theo.
        if let from, let to { onMove(from, to) }
    }
}

// MARK: - Ô chứa một hàng

/// Lớp mỏng, tồn tại **chỉ để thu hẹp phạm vi theo dõi** — xem ghi chú ở
/// `ForEach`.
private struct Slot<Row: View>: View {
    let model: ReorderModel
    let index: Int
    let id: UUID
    let height: CGFloat
    @ViewBuilder let row: (UUID, Bool, Bool) -> Row

    var body: some View {
        // Hai khái niệm khác nhau, và tách chúng ra là điều kiện để cú đáp
        // đúng. `dragging` là "hàng này sở hữu phép toán ô" — đúng cho tới khi
        // chốt. `lifted` là "hàng này *trông* như đang được nhấc" — tắt ngay
        // khi ngón tay rời, nên nó thu về và tắt bóng trong lúc bay về đích.
        let dragging = id == model.draggedID
        let lifted = dragging && !model.isSettling
        row(id, lifted, id == model.pressedID && !lifted)
            .frame(height: height)
            .offset(y: model.offset(at: index))
            // **Không `.animation(_:value:)` ở đây.** Nó đè transaction bao
            // ngoài, và đó chính là lỗi đã sửa: lúc thả, khung hàng trượt theo
            // lò xo của `withAnimation` còn `.offset` tan theo lò xo của
            // modifier, hai đường cộng lại thành một cú giật ngược. Ai gây ra
            // biến đổi thì người ấy chọn lò xo — xem `liftMoved`, `liftEnded`.
            .zIndex(dragging ? 1 : 0)
    }
}

// MARK: - Bộ mặt của một hàng

extension View {
    /// Thẻ nền cho một hàng kéo thả được: nền lúc đè, nền đặc hơn lúc nhấc,
    /// thu nhỏ một chút, và bóng.
    ///
    /// Cùng một màu cho cả hai trạng thái, khác nhau ở độ đục. Nền lúc đè không
    /// phải một hiệu ứng riêng — nó là cùng cái thẻ ấy, mờ hơn.
    func reorderCard(
        lifted: Bool,
        pressed: Bool,
        fill: some ShapeStyle,
        pressedOpacity: Double = 0.4
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: ReorderTuning.corner, style: .continuous)
                    .fill(fill)
                    // Bóng gắn vào **riêng hình thẻ**, không vào cả hàng.
                    // `.shadow` áp cho từng thứ được vẽ trong cây con, nên đặt
                    // nó ngoài nội dung hàng thì tiêu đề, tên nghệ sĩ và ảnh
                    // bìa mỗi thứ tự đổ một bóng đen của riêng mình. Chữ có
                    // viền đen mờ đọc ra là "gắt", không đọc ra là "bóng".
                    //
                    // Hai lớp thay vì một, đúng cách vật thật đổ bóng: một lớp
                    // rộng và rất mờ cho ánh sáng môi trường, một lớp hẹp và
                    // sát cho chỗ tiếp xúc. Một lớp duy nhất muốn đủ thấy thì
                    // phải đậm, mà đậm thì thành vệt đen.
                    .shadow(color: .black.opacity(lifted ? 0.12 : 0), radius: 18, y: 9)
                    .shadow(color: .black.opacity(lifted ? 0.06 : 0), radius: 3, y: 1)
                    .opacity(lifted ? 1 : (pressed ? pressedOpacity : 0))
            )
            // **Không phóng to.** Bản trước có `scaleEffect(1.03)`, và trên một
            // hàng rộng ~330 điểm thì 3% là 5 điểm mỗi bên: ảnh bìa của hàng
            // đang nhấc lệch ra khỏi lề trái, thôi thẳng hàng với ảnh bìa ở
            // header ngay phía trên, và bị mép vùng cắt của thẻ xén.
            //
            // Không có con số nào chữa được — một tỉ lệ luôn quy ra điểm theo
            // chiều rộng hàng, còn lề thì cố định. Cảm giác "được nhấc lên" đã
            // nằm ở cái bóng và ở nền đặc hơn; đó cũng là chỗ Apple Music đặt
            // nó, hàng đợi của họ không phóng to hàng đang nhấc.
            .animation(ReorderTuning.part, value: lifted)
    }
}

// MARK: - Cầu nối cử chỉ

/// Một `UILongPressGestureRecognizer` gắn vào một view SwiftUI.
///
/// `cancelsTouchesInView = false` và nhận diện song song với mọi cử chỉ khác:
/// hai recogniser này **quan sát** ngón tay chứ không giành nó. Việc chặn cuộn
/// để `.scrollDisabled` lo, sau khi đã nhấc.
private struct ReorderLongPress: UIGestureRecognizerRepresentable {
    let minimumDuration: Double
    let allowableMovement: CGFloat
    let onEvent: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recogniser = UILongPressGestureRecognizer()
        recogniser.minimumPressDuration = minimumDuration
        recogniser.allowableMovement = allowableMovement
        recogniser.cancelsTouchesInView = false
        recogniser.delegate = context.coordinator
        return recogniser
    }

    /// **Toạ độ lấy từ UIKit, không hỏi `context.converter`. Đây là một vụ crash
    /// đã xảy ra, không phải một mối lo lý thuyết.**
    ///
    /// `context.converter.location(in:)` trông như một phép đọc rẻ. Nó không:
    /// nó gọi `GeometryProxy.convert(globalPoint:to:)`, thứ bắt AttributeGraph
    /// của SwiftUI tính lại cả chuỗi thuộc tính hình học — và với danh sách này
    /// chuỗi ấy đi qua `ScrollViewChildTransform`, `AnimatableFrameAttribute`,
    /// `OffsetPosition`, tức đúng những thuộc tính mà cú đáp lúc thả đang
    /// animate.
    ///
    /// Hỏi graph một câu từ trong callback của một recogniser UIKit là hỏi
    /// ngoài lượt cập nhật view. Khi graph không thêm được input, nó không trả
    /// lỗi — nó gọi `AG::precondition_failure` rồi `abort()`. Báo cáo crash:
    /// `Evenstar-2026-08-14-090115.ips`, SIGABRT, main thread, và bốn khung
    /// trên cùng của app chính là hàm này.
    ///
    /// `location(in: nil)` là toạ độ cửa sổ, thuần UIKit, không đụng gì tới
    /// SwiftUI. Chỗ gọi trừ đi mép trên của danh sách — con số ấy đo trong lượt
    /// cập nhật view, nơi hỏi hình học là hợp lệ.
    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer,
                                         context: Context) {
        onEvent(recognizer.state, recognizer.location(in: nil))
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

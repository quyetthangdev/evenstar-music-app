//
//  ContentView.swift
//  SPIKE — code bỏ đi, không đưa vào app.
//
//  Câu hỏi: một thẻ player tự vẽ có nối mượt được từ `tabViewBottomAccessory`
//  native không — bung ra từ đúng chỗ accessory đang nằm, ở cả `.expanded` lẫn
//  `.inline`, rồi thu về đúng chỗ ấy?
//
//  Tham số khi chạy (xem run.sh):
//    -progress 0.3        mở thẻ sẵn tới 30% (để chụp từng khung)
//    -card glass|solid    chất liệu thẻ ở đầu cú bung (mặc định glass)
//    -noTrack             accessory không có nội dung — xem hệ thống vẽ gì
//    -debugFrame          viền đỏ quanh khung accessory đo được
//    -scrolled            tự cuộn danh sách, thử làm thanh tab thu nhỏ
//    -trackAfter 3        accessory rỗng, có bài sau 3 giây
//    -slow                lò xo 4 giây, để UITests chụp khung giữa chừng
//    -mode uikit|swiftui|custom   chế độ lúc mở (mặc định uikit — xem UIKitZoom.swift)
//    -uikit pill|strip|art        nguồn/căn của chế độ UIKit (mặc định pill)
//    -present full                UIKit trình bày .fullScreen thay vì .overFullScreen
//    -src capsule|plain|artwork|none   nguồn của chế độ SwiftUI (mặc định capsule)
//    -player heavy                full player lần 1 (gradient + bóng đổ), để so
//    -hitchLog <path>             ghi khung main thread trễ > 20 ms + mốc sự kiện
//    -logChain                    ghi chuỗi superview từ neo trong hàng accessory
//

import SwiftUI

// MARK: - Tham số

enum Args {
    static let all = ProcessInfo.processInfo.arguments
    static func value(_ key: String) -> String? {
        guard let i = all.firstIndex(of: key), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
    static let progress = CGFloat(value("-progress").flatMap(Double.init) ?? 0)
    static let solidCard = value("-card") == "solid"
    static let noTrack = all.contains("-noTrack")
    static let debugFrame = all.contains("-debugFrame")
    static let scrolled = all.contains("-scrolled")
    /// Bài xuất hiện sau bấy nhiêu giây — thử accessory hiện ra giữa chừng.
    static let trackAfter = value("-trackAfter").flatMap(Double.init)
    /// Lò xo dài 4 giây, để test chụp được các khung giữa cú bung.
    static let slow = all.contains("-slow")
    /// `-snapContent`: nội dung accessory nhảy bố cục tức thì (bản đầu), để so.
    static let snapContent = all.contains("-snapContent")
    /// Mặc định UIKit zoom (lần 2: hạ cánh vào đúng viên thuốc, không mờ).
    static let startMode: PlayerMode = value("-mode") == "custom" ? .custom : value("-mode") == "swiftui" ? .native : .uikit
    /// Nguồn zoom: `capsule` (cả hàng, cấu hình cắt theo viên thuốc — mặc định),
    /// `plain` (cả hàng, không cấu hình — bản lần 1), `artwork` (ô bìa, cắt bo 6).
    static let zoomSource = value("-src") ?? (value("-zoomFrom") == "artwork" ? "artwork" : "capsule")
    static var zoomFromArtwork: Bool { zoomSource == "artwork" }
    /// `-player heavy`: full player lần 1 (gradient + bóng đổ bìa), để so.
    static let heavyPlayer = value("-player") == "heavy"
}

enum PlayerMode: String, CaseIterable, Identifiable {
    case native = "SwiftUI zoom"
    case uikit = "UIKit zoom"
    case custom = "Custom"
    var id: String { rawValue }
}

enum Song {
    static let title = "Chiều nay không có mưa bay"
    static let artist = "Vũ."
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

// MARK: - Gốc

struct ContentView: View {
    @State private var tab = 0
    @State private var query = ""

    /// Khung accessory trong toạ độ màn hình, đo liên tục khi thẻ đóng.
    @State private var accessoryFrame: CGRect = .zero
    @State private var placement: TabViewBottomAccessoryPlacement?
    /// Khung chụp lại lúc bắt đầu bung — không đổi suốt cú bung, vì nội dung
    /// lùi lại phía sau làm khung đo được co theo.
    @State private var startFrame: CGRect = .zero

    @State private var progress: CGFloat = Args.progress
    @State private var cardShown = Args.progress > 0
    @State private var hasTrack = !Args.noTrack && Args.trackAfter == nil

    @State private var mode: PlayerMode = Args.startMode
    /// UIKit `-uikit art`: ô bìa nhỏ ẩn trong lúc player mở (hệ thống bay ô bìa lớn về đúng chỗ nó).
    @State private var artHidden = false
    /// Native: binding `$showingPlayer` tổng hợp thẳng — iOS 26.1 có lỗi zoom từ
    /// tabViewBottomAccessory khi binding không tầm thường / đổi Observable.
    @State private var showingPlayer = false
    @Namespace private var zoom

    var body: some View {
        let _ = HitchLog.shared.mark("body ContentView")
        GeometryReader { geo in
            let screen = geo.frame(in: .global)
            ZStack {
                tabs
                    .scaleEffect(1 - 0.06 * progress)
                    .ignoresSafeArea()

                if cardShown {
                    PlayerOverlay(
                        start: startFrame,
                        screen: screen,
                        progress: progress,
                        onDrag: { dy in
                            progress = min(1, max(0, 1 - dy / travel))
                        },
                        onDragEnd: { dy, predicted in
                            settle(open: 1 - predicted / travel > 0.5)
                        }
                    )
                }

                if Args.debugFrame { debugOverlay(screen: screen) }
            }
        }
        .ignoresSafeArea()
        .onAppear { HitchLog.shared.start() }
        .onChange(of: showingPlayer) { _, v in HitchLog.shared.mark("showingPlayer=\(v)") }
        .task {
            // `-openAfter 3`: tự mở player sau 3 s (cho test vuốt sớm, không qua XCUITest tap).
            guard let t = Args.value("-openAfter").flatMap(Double.init) else { return }
            try? await Task.sleep(for: .seconds(t))
            UIKitZoom.present(setArtHidden: { artHidden = $0 })
        }
        .task {
            guard let delay = Args.trackAfter else { return }
            try? await Task.sleep(for: .seconds(delay))
            hasTrack = true
        }
        .onChange(of: accessoryFrame, initial: true) { _, f in
            // Mở sẵn bằng -progress: khung chưa có lúc dựng, chụp ngay khi có.
            if startFrame == .zero || !cardShown { startFrame = f }
        }
    }

    /// Quãng đường ngón tay đi để bung trọn: từ mép trên accessory lên đỉnh màn.
    private var travel: CGFloat { max(200, startFrame.minY) }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Bài hát", systemImage: "music.note.list", value: 0) { LongList(title: "Bài hát", mode: $mode) }
            Tab("Album", systemImage: "square.stack", value: 1) { LongList(title: "Album") }
            Tab("Nghệ sĩ", systemImage: "music.mic", value: 2) { LongList(title: "Nghệ sĩ") }
            Tab("Tài khoản", systemImage: "person.crop.circle", value: 3) { LongList(title: "Tài khoản") }
            Tab(value: 4, role: .search) {
                NavigationStack {
                    List(0..<30, id: \.self) { Text("Kết quả \($0)") }
                        .navigationTitle("Tìm kiếm")
                }
                .searchable(text: $query)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if !hasTrack {
                EmptyView()
            } else {
                MiniPlayerAccessory(
                    native: mode != .custom,
                    artHidden: artHidden,
                    zoom: zoom,
                    hidden: cardShown,
                    // Chỉ chế độ Custom cần khung đo được. Ghi @State ở đây làm
                    // dựng lại cả `ContentView` (TabView + 5 tab) mỗi lần khung đổi
                    // — kể cả lúc UIKit gỡ/gắn lại cây view quanh cú trình bày.
                    onFrame: { f in if mode == .custom || cardShown { accessoryFrame = f } },
                    onPlacement: { placement = $0 },
                    onTap: {
                        switch mode {
                        case .native: showingPlayer = true
                        case .uikit:
                            // Biến thể "SwiftUI" của cú vuốt: đi đường fullScreenCover lần 1.
                            if DismissVariant.current == .swiftui {
                                ZoomLog.write("present variant=SwiftUI (fullScreenCover)")
                                showingPlayer = true
                            } else {
                                UIKitZoom.present(setArtHidden: { artHidden = $0 })
                            }
                        case .custom: begin(); settle(open: true)
                        }
                    },
                    onDrag: { dy in
                        if !cardShown { begin() }
                        progress = min(1, max(0, -dy / travel))
                    },
                    onDragEnd: { _, predicted in settle(open: -predicted / travel > 0.5) }
                )
            }
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            FullPlayer()
                .navigationTransition(.zoom(sourceID: "player", in: zoom))
        }
    }

    private func begin() {
        startFrame = accessoryFrame
        cardShown = true
    }

    private func settle(open: Bool) {
        withAnimation(.spring(duration: Args.slow ? 4 : 0.45, bounce: open ? 0.12 : 0)) {
            progress = open ? 1 : 0
        } completion: {
            if !open { cardShown = false }
        }
    }

    private func debugOverlay(screen: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.red, lineWidth: 1)
                .frame(width: accessoryFrame.width, height: accessoryFrame.height)
                .position(x: accessoryFrame.midX - screen.minX, y: accessoryFrame.midY - screen.minY)
            Text(verbatim: "\(placement.map { "\($0)" } ?? "nil")  \(Int(accessoryFrame.minX)),\(Int(accessoryFrame.minY)) \(Int(accessoryFrame.width))×\(Int(accessoryFrame.height))  p=\(String(format: "%.2f", progress)) card=\(cardShown) track=\(hasTrack) tab=\(tab)")
                .font(.caption.monospaced())
                .accessibilityIdentifier("debugInfo")
                .padding(4)
                .background(.yellow)
                .padding(.top, 60)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Danh sách giả

struct LongList: View {
    let title: String
    var mode: Binding<PlayerMode>? = nil
    var body: some View {
        let _ = HitchLog.shared.mark("body LongList \(title)")
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let mode {
                        Picker("Mode", selection: mode) {
                            ForEach(PlayerMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("modePicker")
                    }
                    ForEach(0..<60, id: \.self) { i in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hue: Double(i % 12) / 12, saturation: 0.5, brightness: 0.8))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text("\(title) \(i + 1)")
                            Text("Nghệ sĩ \(i % 7 + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .id(i)
                    }
                }
                .navigationTitle(title)
                .task {
                    guard Args.scrolled else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { proxy.scrollTo(30, anchor: .top) }
                }
            }
        }
    }
}

// MARK: - Bìa giả

struct Artwork: View {
    let cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.42, blue: 0.68),
                                          Color(red: 0.13, green: 0.16, blue: 0.30)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "cloud.rain.fill")
                    .resizable().scaledToFit()
                    .padding(cornerRadius * 1.2)
                    .foregroundStyle(.white.opacity(0.85))
            }
    }
}

// MARK: - Nội dung accessory

/// Chỉ nội dung — kính là của hệ thống. Bìa đặt ở lề trái `artworkInset`, cỡ
/// `artworkSide`; thẻ phủ xuất phát từ đúng hai con số này.
struct MiniPlayerAccessory: View {
    static let artworkInset: CGFloat = 10
    static let artworkSide: CGFloat = 30

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let native: Bool
    let artHidden: Bool
    let zoom: Namespace.ID
    let hidden: Bool
    @State private var height: CGFloat = 48
    let onFrame: (CGRect) -> Void
    let onPlacement: (TabViewBottomAccessoryPlacement?) -> Void
    let onTap: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnd: (CGFloat, CGFloat) -> Void

    private var row: some View {
        HStack(spacing: 10) {
            if Args.zoomFromArtwork {
                Artwork(cornerRadius: 6)
                    .frame(width: Self.artworkSide, height: Self.artworkSide)
                    .matchedTransitionSource(id: "player", in: zoom) { source in
                        source.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
            } else {
                Artwork(cornerRadius: 6)
                    .frame(width: Self.artworkSide, height: Self.artworkSide)
                    .opacity(artHidden ? 0 : 1)
                    .background(ZoomAnchor(kind: .art))
            }
            // Một dòng ở CẢ HAI vị trí: không có dòng nghệ sĩ để biến mất, nên
            // chữ không nhảy dọc khi hệ thống đổi vị trí.
            Text(Song.title).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "play.fill").font(.title3)
            if placement != .inline || Args.snapContent {
                Image(systemName: "forward.fill").font(.title3)
            }
        }
    }

    var body: some View {
        let _ = HitchLog.shared.mark("body MiniPlayerAccessory")
        ZStack {
            // Đã thử `.id(placement)` + `.transition(.blurReplace)`: không có
            // tác dụng — hệ thống đổi `placement` không kèm animation, dựng nội
            // dung ở cỡ cuối rồi tự morph viên kính.
            row
        }
        .padding(.leading, Self.artworkInset)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZoomAnchor(kind: .row))
        .contentShape(Rectangle())
        .modifier(ZoomSource(enabled: !Args.zoomFromArtwork && Args.zoomSource != "none", zoom: zoom, height: height))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("miniPlayer")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("miniPlayer")
        .opacity(hidden ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0); height = $0.height }
        .onChange(of: placement, initial: true) { _, p in onPlacement(p) }
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { onDrag($0.translation.height) }
                .onEnded { onDragEnd($0.translation.height, $0.predictedEndTranslation.height) },
            // Native zoom: chỉ chạm để mở — hệ thống không cho kéo-để-mở.
            including: native ? .subviews : .all
        )
    }
}

struct ZoomSource: ViewModifier {
    let enabled: Bool
    let zoom: Namespace.ID
    let height: CGFloat
    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if Args.zoomSource == "plain" {
            content.matchedTransitionSource(id: "player", in: zoom)
        } else {
            content.matchedTransitionSource(id: "player", in: zoom) { source in
                // Chỉ nhận RoundedRectangle: bán kính = nửa chiều cao đo được = viên thuốc.
                source.clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
            }
        }
    }
}

// MARK: - Full player native (đích của zoom)

struct FullPlayer: View {
    var body: some View {
        if Args.heavyPlayer { HeavyFullPlayer() } else { LeanFullPlayer() }
    }
}

/// Full player gọn cho cú zoom: gốc là màu đục phẳng, không GeometryReader,
/// không ScrollView, không bóng đổ (bóng của một view ghép = một lượt vẽ
/// offscreen mỗi khung khi hệ thống co thẻ lúc vuốt xuống).
struct LeanFullPlayer: View {
    @Environment(\.dismiss) private var dismiss
    /// Trình bày bằng UIKit: `dismiss` của SwiftUI không đóng được VC đó.
    var onClose: (() -> Void)? = nil
    @State private var variant = DismissVariant.current
    static let background = Color(red: 0.13, green: 0.17, blue: 0.29)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HitchLog.shared.mark("chevron")
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("closePlayer")
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // Biến thể cú vuốt đóng (lần 3) — áp dụng cho lần mở sau.
            VStack(spacing: 2) {
                Picker("Dismiss", selection: $variant) {
                    ForEach(DismissVariant.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityIdentifier("dismissPicker")
                Text(verbatim: "Kiểu vuốt đóng — áp dụng lần mở sau")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 4)

            Artwork(cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ZoomAnchors.shared.bigArt = $0 }
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(Song.title).font(.title2.bold()).lineLimit(1)
                Text(Song.artist).font(.title3).foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 32)

            // Thanh tua giả — hai hình chữ nhật phẳng, không GeometryReader.
            VStack(spacing: 6) {
                Capsule().fill(.white.opacity(0.25))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.9))
                            .containerRelativeFrame(.horizontal) { w, _ in (w - 64) * 0.35 }
                    }
                HStack {
                    Text(verbatim: "1:12"); Spacer(); Text(verbatim: "-2:21")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 24)

            HStack(spacing: 48) {
                Image(systemName: "backward.fill")
                Image(systemName: "play.fill").font(.system(size: 44))
                Image(systemName: "forward.fill")
            }
            .font(.system(size: 30))
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.background, ignoresSafeAreaEdges: .all)
        .onChange(of: variant) { _, v in DismissVariant.current = v; ZoomLog.write("variant → \(v.rawValue)") }
        .onAppear { HitchLog.shared.mark("player onAppear") }
        .onDisappear { HitchLog.shared.mark("player onDisappear") }
    }
}

/// Bản lần 1 (`-player heavy`): GeometryReader, gradient, bóng đổ bìa.
struct HeavyFullPlayer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width - 64
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("closePlayer")
                    Spacer()
                }
                .padding(.top, 8)

                Artwork(cornerRadius: 16)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Song.title).font(.title2.bold()).lineLimit(1)
                    Text(Song.artist).font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Thanh tua giả.
                VStack(spacing: 6) {
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white.opacity(0.9)).frame(width: bar.size.width * 0.35)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        Text(verbatim: "1:12"); Spacer(); Text(verbatim: "-2:21")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                HStack(spacing: 48) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 44))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 30))
                .frame(maxWidth: .infinity)
                .padding(.top, 32)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .frame(width: geo.size.width)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            LinearGradient(colors: [Color(red: 0.22, green: 0.30, blue: 0.50),
                                    Color(red: 0.07, green: 0.08, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Thẻ phủ

/// Một view duy nhất, hình dạng là hàm của `progress` — cùng cách PlayerCard
/// thật làm. Ở 0 nó trùng khít khung accessory, ở 1 nó phủ kín màn hình.
struct PlayerOverlay: View {
    let start: CGRect
    let screen: CGRect
    let progress: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnd: (CGFloat, CGFloat) -> Void

    /// Bán kính góc màn hình iPhone 17 xấp xỉ — spike không cần chính xác.
    private let displayRadius: CGFloat = 55

    var body: some View {
        let p = progress
        let frame = lerp(start, screen, p)
        let radius = lerp(start.height / 2, displayRadius, p)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Thẻ thành đục rất sớm: kính chồng kính (thẻ trên accessory) chỉ
        // được phép sống vài khung đầu.
        let solid = Args.solidCard ? 1 : min(1, p / 0.18)

        let small = CGRect(x: MiniPlayerAccessory.artworkInset,
                           y: (start.height - MiniPlayerAccessory.artworkSide) / 2,
                           width: MiniPlayerAccessory.artworkSide,
                           height: MiniPlayerAccessory.artworkSide)
        let bigSide = screen.width - 64
        let big = CGRect(x: 32, y: 130, width: bigSide, height: bigSide)
        let art = lerp(small, big, p)
        let miniTextOpacity: Double = Double(1 - min(1, p / 0.12))
        let fullTextOpacity: Double = Double(max(0, (p - 0.55) / 0.45))
        let miniTextY: CGFloat = start.height / 2 - 9

        ZStack(alignment: .topLeading) {
            Artwork(cornerRadius: lerp(6, 16, p))
                .frame(width: art.width, height: art.height)
                .offset(x: art.minX, y: art.minY)

            // Chữ của mini player tắt nhanh, chữ toàn màn hình hiện sau.
            Text(Song.title)
                .font(.subheadline.weight(.medium)).lineLimit(1)
                .offset(x: small.maxX + 10, y: miniTextY)
                .opacity(miniTextOpacity)

            VStack(alignment: .leading, spacing: 4) {
                Text(Song.title).font(.title2.bold())
                Text(Song.artist).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 48) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 44))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 30))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            .frame(width: bigSide, alignment: .leading)
            .offset(x: 32, y: big.maxY + 28)
            .opacity(fullTextOpacity)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background { shape.fill(Color(.systemBackground)).opacity(solid) }
        .glassEffect(.regular, in: shape)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityIdentifier("playerCard")
        .position(x: frame.midX - screen.minX, y: frame.midY - screen.minY)
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { onDrag($0.translation.height) }
                .onEnded { onDragEnd($0.translation.height, $0.predictedEndTranslation.height) }
        )
    }
}

import XCTest
import SwiftUI
@testable import Evenstar

/// Hàng chip thể loại của Jamendo dùng kính native (`glassToggleStyle`): chip
/// đang chọn là `.glassProminent`, còn lại là `.glass`. Dựng đúng hàng ấy
/// trong cửa sổ thật, ở sáng và tối, lưu ảnh cho người xem.
@MainActor
final class GenreChipTests: XCTestCase {
    private static let size = CGSize(width: 390, height: 100)
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func row(selected: JamendoGenre) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JamendoGenre.offered, id: \.self) { genre in
                    GenreChip(genre: genre, isSelected: genre == selected) {}
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func render(_ style: UIUserInterfaceStyle, name: String) -> UIImage {
        let background: Color = style == .dark ? .black : .white
        let host = UIHostingController(rootView: ZStack(alignment: .top) { background.ignoresSafeArea(); row(selected: .jazz).ignoresSafeArea() })
        host.view.frame = CGRect(origin: .zero, size: Self.size)
        host.overrideUserInterfaceStyle = style
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let image = UIGraphicsImageRenderer(size: Self.size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: Self.size), afterScreenUpdates: true)
        }
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".superpowers/sdd/2026-10-06-native-liquid-glass")
        if FileManager.default.fileExists(atPath: directory.path), let data = image.pngData() {
            try? data.write(to: directory.appendingPathComponent(name))
        }
        return image
    }

    /// Một chip cao ít nhất 44pt (vùng chạm của HIG), và hàng dựng ra không bị
    /// cắt theo chiều dọc trong cửa sổ.
    func testChipsKeepA44PointHitHeightAndTheRowIsNotClipped() {
        let chip = UIHostingController(rootView: GenreChip(genre: .rock, isSelected: false) {})
            .sizeThatFits(in: CGSize(width: 400, height: 500))
        print("[chips] single chip \(chip)")
        XCTAssertGreaterThanOrEqual(chip.height, 44)
        let rowHeight = UIHostingController(rootView: row(selected: .jazz))
            .sizeThatFits(in: CGSize(width: Self.size.width, height: 500)).height
        print("[chips] row \(rowHeight)")
        XCTAssertLessThanOrEqual(rowHeight, Self.size.height, "the row fits its window, so nothing is clipped")
        for (style, name) in [(UIUserInterfaceStyle.light, "chips-light.png"), (.dark, "chips-dark.png")] {
            XCTAssertEqual(render(style, name: name).size, Self.size)
        }
    }
}

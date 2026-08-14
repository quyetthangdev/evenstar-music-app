import SwiftUI

/// Vỏ app tối thiểu. Trong project mới, file này chính là file `App` Xcode đã
/// tạo sẵn — chỉ `ContentView.swift` mới là thứ cần dán.
@main
struct LiquidGlassMorphApp: App {
    private var initialProgress: CGFloat {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-progress"), i + 1 < args.count,
           let v = Double(args[i + 1]) { return CGFloat(v) }
        return 0
    }

    var body: some Scene {
        WindowGroup { ContentView(initialProgress: initialProgress) }
    }
}

import SwiftUI

/// Vỏ app tối thiểu. Trong một project mới, file này chính là file `App` mà
/// Xcode đã tạo sẵn cho anh — chỉ `ContentView.swift` mới là thứ cần dán.
///
/// `-expanded` để chụp được trạng thái mở mà không cần ngón tay: `simctl`
/// không bấm hộ được.
@main
struct AppleMusicMorphApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                startExpanded: ProcessInfo.processInfo.arguments.contains("-expanded")
            )
        }
    }
}

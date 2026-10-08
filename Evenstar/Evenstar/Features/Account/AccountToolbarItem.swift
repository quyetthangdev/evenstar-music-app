import SwiftUI

extension EnvironmentValues {
    /// Sheet Tài khoản đang mở hay không. `RootView` giữ `@State` và đẩy
    /// binding xuống đây; nút ở ba tab thư viện chỉ việc bật nó lên.
    ///
    /// Một binding chứ không phải closure: `Binding` là `Sendable`, nên giá trị
    /// mặc định của `@Entry` không vướng kiểm tra concurrency của Swift 6.
    /// `.constant(false)` cho preview và mọi chỗ ngoài `RootView` — bấm nút
    /// ở đó không làm gì, thay vì crash.
    @Entry var showingAccount: Binding<Bool> = .constant(false)
}

/// Nút tài khoản ở góc trên bên phải, như ảnh đại diện của Apple Music.
///
/// Dùng chung cho ba tab gốc Bài hát / Album / Nghệ sĩ: `.toolbar {
/// AccountToolbarItem() }`. Một `ToolbarItem` riêng, để thanh điều hướng của
/// iOS 26 vẽ viên kính cho nó — không có nền tự vẽ nào ở đây. Chỗ đã có nút
/// khác ở góc phải (`+` của Bài hát) thì đặt `ToolbarSpacer(.fixed)` trước nó,
/// kẻo hệ thống gộp hai nút vào chung một viên.
struct AccountToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            AccountButton()
        }
    }
}

private struct AccountButton: View {
    @Environment(\.showingAccount) private var showingAccount

    var body: some View {
        Button {
            showingAccount.wrappedValue = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
        }
        // Khoá "Tài khoản" có sẵn trong catalogue — từng là nhãn của tab.
        .accessibilityLabel(String(
            localized: "Tài khoản",
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        ))
    }
}

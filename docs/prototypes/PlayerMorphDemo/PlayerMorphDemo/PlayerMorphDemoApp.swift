import SwiftUI

/// Vỏ app tối thiểu, không có gì ngoài việc dựng prototype lên màn hình.
///
/// Deployment target của project này để 16.0 chứ không phải 18.6 như Evenstar —
/// cố ý, để bất cứ thứ gì lỡ dùng API mới hơn sẽ không biên dịch được thay vì
/// lặng lẽ chạy trên máy anh rồi hỏng ở nơi khác.
@main
struct PlayerMorphDemoApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerMorphPrototype()
                .preferredColorScheme(.dark)
        }
    }
}

import SwiftUI

extension View {
    /// Nút bật/tắt bằng kính native: bật → `.glassProminent`, tắt → `.glass`.
    /// Trạng thái phải nhìn ra được, vì glyph của shuffle và repeat vẽ giống
    /// hệt nhau dù bật hay tắt.
    @ViewBuilder
    func glassToggleStyle(isOn: Bool) -> some View {
        if isOn {
            buttonStyle(.glassProminent)
                // Accent của app là trắng: không đặt màu thì nút bật là trắng
                // với glyph trắng. Cùng cách xử lý như nút hành động chính.
                .tint(Color(.label))
                .foregroundStyle(Color(.systemBackground))
        } else {
            buttonStyle(.glass)
        }
    }
}

import XCTest

/// Những khoá Info.plist mà App Store Connect đọc, kiểm trên bundle đã dựng.
///
/// `Info.plist` của target không được đóng làm resource — nó là `INFOPLIST_FILE`,
/// và pbxproj liệt nó trong `membershipExceptions`. Bản trong bundle là bản
/// **đã trộn** với mọi build setting `INFOPLIST_KEY_*`, nên đọc `Bundle.main`
/// là cách duy nhất thấy được thứ Apple sẽ thấy.
final class InfoPlistTests: XCTestCase {

    /// Thiếu khoá này thì mỗi build lên App Store Connect đều treo lại chờ trả
    /// lời thủ công câu hỏi tuân thủ xuất khẩu. App không dùng mã hoá riêng nào
    /// ngoài HTTPS của hệ thống, nên `false` là câu trả lời đúng.
    func testKhaiKhongDungMaHoaNgoaiMienTru() throws {
        let value = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption")
        XCTAssertEqual(value as? Bool, false,
                       "Info.plist thiếu ITSAppUsesNonExemptEncryption = false")
    }

    /// Nền `audio` cho phát nền, `remote-notification` cho push im lặng của
    /// đồng bộ SwiftData qua CloudKit. Khai một nền không dùng tới là lý do bị
    /// từ chối theo mục 2.5.4, nên danh sách này được ghim đúng bằng.
    func testChiKhaiHaiNenThucSuDung() throws {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertEqual(Set(modes ?? []), ["audio", "remote-notification"])
    }
}

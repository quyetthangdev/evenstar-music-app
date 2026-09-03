import XCTest

/// Bản kê quyền riêng tư phải nằm **trong bundle đã dựng**, không chỉ nằm trong
/// thư mục nguồn.
///
/// Dự án dùng Xcode 16 synced folders: một tệp mới được thêm vào target một
/// cách tự động và không có dòng nào trong pbxproj để đọc lại mà xác nhận. Một
/// test đọc `#filePath` sẽ xanh kể cả khi bản build không chứa manifest — đúng
/// thứ hỏng mà nó phải bắt. `TEST_HOST` của bó test này là `Evenstar.app`, nên
/// `Bundle.main` ở đây là bundle của app thật.
final class PrivacyManifestTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy không được đóng vào bundle của app"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(plist as? [String: Any], "Manifest không phải một dictionary")
    }

    func testManifestNamTrongBundleCuaApp() throws {
        _ = try loadManifest()
    }

    func testKhongTheoDoiVaKhongThuThapDuLieu() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertTrue(collected.isEmpty, "App không thu thập dữ liệu nào; đừng khai thừa")
    }

    /// `@AppStorage` ở `AppTheme`, `AppLanguage`, `JamendoLicencePolicy` và
    /// `RootView` đều đọc/ghi `UserDefaults`, thuộc nhóm API bắt buộc khai lý
    /// do. `CA92.1` là mã cho "chỉ đọc/ghi thiết lập của chính app này".
    func testKhaiLyDoDungUserDefaults() throws {
        let manifest = try loadManifest()
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let entry = try XCTUnwrap(
            apis.first { $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults" },
            "Chưa khai NSPrivacyAccessedAPICategoryUserDefaults"
        )
        XCTAssertEqual(entry["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}

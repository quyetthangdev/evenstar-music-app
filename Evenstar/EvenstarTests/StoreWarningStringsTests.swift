import XCTest
@testable import Evenstar

/// Ba chuỗi của hộp thoại "không mở được thư viện" phải theo **ngôn ngữ chọn
/// trong app**, không theo ngôn ngữ của máy.
///
/// Vì sao cần test riêng cho ba chuỗi mà cả app có 155 khoá: hộp thoại ấy nằm
/// **trên** `.environment(\.locale,)` trong chuỗi modifier của `RootView.body`
/// — nó phải nằm đó, nếu không thì `.id(language)` sẽ đóng sập nó mỗi lần đổi
/// ngôn ngữ. Cái giá là một `LocalizedStringKey` ở vị trí ấy tra theo locale
/// thừa kế, tức của máy. Bản đầu tiên của hộp thoại đúng là đã mắc lỗi ấy, và
/// nó không hiện ra ở đâu cả: chuỗi vẫn ra tiếng Việt, chỉ là ra tiếng Việt
/// ngay cả với người đã chọn English.
///
/// `RootView.storeWarning*` vì thế đi qua `String(localized:bundle:locale:)`,
/// và ba test dưới ghim đúng chỗ đó. Nếu ai đó "dọn dẹp" chúng về lại
/// `.alert("Không mở được thư viện")`, ba dòng này đỏ.
final class StoreWarningStringsTests: XCTestCase {

    private var saved: String??

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        if let saved, let value = saved {
            UserDefaults.standard.set(value, forKey: AppLanguage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
        saved = nil
        super.tearDown()
    }

    private func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    @MainActor
    func testChonEnglishThiHopThoaiRaTiengAnh() {
        choose(.english)
        XCTAssertEqual(RootView.storeWarningTitle, "Couldn't open your library")
        XCTAssertEqual(RootView.storeWarningDismiss, "OK")
        XCTAssertTrue(
            RootView.storeWarningBody.hasPrefix("This session is running in temporary memory"),
            "Thân hộp thoại không ra tiếng Anh: \(RootView.storeWarningBody)"
        )
    }

    @MainActor
    func testChonTiengVietThiHopThoaiRaTiengViet() {
        choose(.vietnamese)
        XCTAssertEqual(RootView.storeWarningTitle, "Không mở được thư viện")
        XCTAssertEqual(RootView.storeWarningDismiss, "Đã hiểu")
        XCTAssertTrue(
            RootView.storeWarningBody.hasPrefix("Lần chạy này dùng bộ nhớ tạm"),
            "Thân hộp thoại không ra tiếng Việt: \(RootView.storeWarningBody)"
        )
    }

    /// Không chọn gì thì theo máy — và trên máy chạy test, "theo máy" nghĩa là
    /// bundle chính. Test này không ghim ra chuỗi cụ thể (nó phụ thuộc ngôn ngữ
    /// của simulator), chỉ ghim rằng ba chuỗi **có nội dung** chứ không rơi về
    /// chính khoá nguồn vì tra hỏng bundle.
    @MainActor
    func testKhongChonGiThiVanRaChuoiThatSu() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        XCTAssertFalse(RootView.storeWarningTitle.isEmpty)
        XCTAssertFalse(RootView.storeWarningDismiss.isEmpty)
        XCTAssertFalse(RootView.storeWarningBody.isEmpty)
    }
}

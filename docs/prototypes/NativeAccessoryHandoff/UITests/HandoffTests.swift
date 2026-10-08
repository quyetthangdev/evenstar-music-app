import XCTest

/// SPIKE — chạy ngầm trên simulator, không cần cửa sổ. Ảnh ghi thẳng ra thư mục
/// `SPIKE_OUT` của máy host (simulator không sandbox runner khỏi đĩa host).
final class HandoffTests: XCTestCase {
    let out = ProcessInfo.processInfo.environment["SPIKE_OUT"] ?? NSTemporaryDirectory()
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        sleep(2)
    }

    private func debug(_ tag: String) {
        let label = app.staticTexts["debugInfo"].label
        print("SPIKE[\(name.split(separator: " ").last ?? "")] \(tag): \(label)")
    }

    private func shot(_ file: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(file).png"))
    }

    private func scrollList() {
        let list = app.collectionViews.firstMatch
        list.swipeUp(velocity: .slow)
        sleep(2)
    }

    /// Bung chậm từ vị trí `.expanded`, chụp các khung đầu.
    func test1_expandedHandoff() {
        launch(["-debugFrame", "-slow"])
        debug("rest"); shot("t1_rest")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        for (i, ms) in [100, 300, 700, 1500].enumerated() {
            usleep(useconds_t(ms * 1000) - (i == 0 ? 0 : useconds_t([100, 300, 700, 1500][i - 1] * 1000)))
            shot("t1_open_\(ms)ms")
        }
        sleep(4); debug("open"); shot("t1_open_end")
    }

    /// Thu thanh tab bằng cuộn thật, rồi bung từ vị trí `.inline`.
    func test2_inlineHandoff() {
        launch(["-debugFrame", "-slow"])
        scrollList()
        debug("afterScroll"); shot("t2_inline")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        usleep(150_000); shot("t2_open_150ms")
        usleep(350_000); shot("t2_open_500ms")
        sleep(5); debug("open"); shot("t2_open_end")

        // Thu về: kéo thẻ xuống.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        usleep(1_500_000); shot("t2_closing_1500ms")
        sleep(4); debug("closed"); shot("t2_closed")
    }

    /// Kéo tay từ accessory lên — cử chỉ có lọt qua khung UIKit của hệ thống không?
    func test3_dragOpens() {
        launch(["-debugFrame"])
        let pill = app.descendants(matching: .any)["miniPlayer"].firstMatch
        let from = pill.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        debug("heldMidDrag")
        sleep(2); debug("released"); shot("t3_after_drag")
    }

    /// Bài xuất hiện khi đang ở tab khác, đã cuộn — tab và vị trí cuộn còn giữ không?
    func test4_trackAppears() {
        launch(["-debugFrame", "-trackAfter", "12"])
        app.tabBars.buttons["Album"].tap()
        sleep(1)
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        sleep(1)
        debug("before"); shot("t4_before")
        sleep(10)
        debug("after"); shot("t4_after")
    }

    /// Cuộn chậm lên rồi xuống, để host quay video cú thu nhỏ của hệ thống.
    func test5_scrollMinimise() {
        launch([])
        sleep(2)
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        sleep(3)
        app.collectionViews.firstMatch.swipeDown(velocity: .slow)
        sleep(3)
    }

    // MARK: - Native zoom (fullScreenCover + .zoom)

    private func burst(_ prefix: String, count: Int) {
        for i in 0..<count { shot("\(prefix)_\(i)") }
    }

    private func swipeDownPlayer() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Mở rồi vuốt xuống đóng. XCUITest chờ app đứng yên sau mỗi thao tác nên
    /// ảnh chỉ bắt được trạng thái cuối — khung giữa chừng lấy từ video host
    /// (`xcrun simctl io <udid> recordVideo`).
    func test6_nativeZoomSlow() {
        launch([])
        shot("t6_rest")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        burst("t6_open", count: 10)
        sleep(6); shot("t6_open_end")
        XCTAssertTrue(app.buttons["closePlayer"].exists, "full player không mở")
        swipeDownPlayer()
        burst("t6_close", count: 12)
        sleep(6); shot("t6_closed")
        XCTAssertFalse(app.buttons["closePlayer"].exists, "full player không đóng")
    }

    /// Tốc độ thật: chụp dồn dập, rồi đóng bằng nút chevron.
    func test7_nativeZoomRealSpeed() {
        launch([])
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        burst("t7_open", count: 6)
        sleep(2); shot("t7_open_end")
        swipeDownPlayer()
        burst("t7_close", count: 6)
        sleep(2); shot("t7_closed")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        sleep(2)
        app.buttons["closePlayer"].tap()
        burst("t7_chevron_close", count: 4)
        sleep(2); shot("t7_chevron_closed")
    }

    /// Từ vị trí `.inline` (thanh tab thu nhỏ).
    func test8_nativeZoomInline() {
        launch((ProcessInfo.processInfo.environment["SPIKE_ARGS"] ?? "").split(separator: " ").map(String.init))
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        sleep(8); shot("t8_inline")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        burst("t8_open", count: 8)
        sleep(6); shot("t8_open_end")
        swipeDownPlayer()
        burst("t8_close", count: 10)
        sleep(6); shot("t8_closed")
    }

    /// Nguồn zoom là ô bìa thay vì cả nội dung accessory.
    func test9_nativeZoomFromArtwork() {
        launch(["-zoomFrom", "artwork"])
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        burst("t9_open", count: 8)
        sleep(6); shot("t9_open_end")
        swipeDownPlayer()
        burst("t9_close", count: 10)
        sleep(6); shot("t9_closed")
    }

    /// Chế độ Custom vẫn chạy: chuyển bằng picker rồi bung thẻ tự vẽ.
    func test10_customModeStillWorks() {
        launch(["-slow"])
        app.segmentedControls.buttons["Custom"].tap()
        sleep(1); shot("t10_custom_selected")
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        usleep(400_000); shot("t10_open_400ms")
        sleep(5); shot("t10_open_end")
        XCTAssertTrue(app.descendants(matching: .any)["playerCard"].firstMatch.exists)
    }

    /// Một vòng đủ: chạm mở → vuốt xuống đóng → chạm mở → chevron đóng.
    /// Tham số app lấy từ `SPIKE_ARGS` (chạy với `TEST_RUNNER_SPIKE_ARGS="-src artwork"`).
    /// Khung giữa chừng lấy từ video host, không từ ảnh.
    func test11_zoomCycle() {
        let args = (ProcessInfo.processInfo.environment["SPIKE_ARGS"] ?? "")
            .split(separator: " ").map(String.init)
        launch(args + ["-hitchLog", out + "/hitch.log"])
        let pill = app.descendants(matching: .any)["miniPlayer"].firstMatch
        pill.tap()
        sleep(2)
        XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 3), "không mở")
        swipeDownPlayer()
        sleep(3)
        XCTAssertFalse(app.buttons["closePlayer"].exists, "vuốt không đóng")
        pill.tap()
        sleep(2)
        app.buttons["closePlayer"].tap()
        sleep(3)
        XCTAssertFalse(app.buttons["closePlayer"].exists, "chevron không đóng")
    }

    /// Vuốt chậm, giữ giữa chừng: thẻ có bám tay không.
    func test12_slowDrag() {
        let args = (ProcessInfo.processInfo.environment["SPIKE_ARGS"] ?? "")
            .split(separator: " ").map(String.init)
        launch(args)
        app.descendants(matching: .any)["miniPlayer"].firstMatch.tap()
        sleep(2)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: mid, withVelocity: 300, thenHoldForDuration: 1.0)
        sleep(3)
    }

    /// Lần 3: mỗi biến thể vuốt đóng đều mở → vuốt đóng → mở → chevron đóng;
    /// rồi đổi biến thể bằng picker trên player và kiểm lần mở sau dùng nó.
    func test13_dismissVariants() {
        for v in ["default", "direction", "full", "swiftui"] {
            launch(["-dismiss", v, "-hitchLog", out + "/hitch_\(v).log"])
            let pill = app.descendants(matching: .any)["miniPlayer"].firstMatch
            pill.tap()
            XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 3), "\(v): không mở")
            sleep(1)
            swipeDownPlayer()
            sleep(2)
            XCTAssertFalse(app.buttons["closePlayer"].exists, "\(v): vuốt không đóng")
            pill.tap()
            XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 3), "\(v): không mở lần 2")
            sleep(1)
            app.buttons["closePlayer"].tap()
            sleep(2)
            XCTAssertFalse(app.buttons["closePlayer"].exists, "\(v): chevron không đóng")
            app.terminate()
        }
        // Picker trên player: chọn Full, đóng, mở lại → nhật ký phải ghi variant=Full.
        launch(["-hitchLog", out + "/hitch_picker.log"])
        let pill = app.descendants(matching: .any)["miniPlayer"].firstMatch
        pill.tap()
        XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 3))
        sleep(1)
        app.segmentedControls["dismissPicker"].buttons["Full"].tap()
        shot("t13_picker")
        app.buttons["closePlayer"].tap()
        sleep(2)
        pill.tap()
        sleep(2)
        app.buttons["closePlayer"].tap()
        sleep(2)
    }

    /// Lần 3: vuốt xuống NGAY sau khi mở (trước khi lò xo mở kết thúc) — cú
    /// dismiss tương tác có phải chờ `viewDidAppear` không?
    func test14_earlySwipe() {
        let args = (ProcessInfo.processInfo.environment["SPIKE_ARGS"] ?? "")
            .split(separator: " ").map(String.init)
        launch(args + ["-hitchLog", out + "/hitch_early.log", "-openAfter", "3"])
        // App tự mở sau 3 s (không qua XCUITest tap → không chờ app đứng yên).
        // Cú kéo bắt đầu ~0.3 s sau khi mở.
        usleep(1_300_000)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        sleep(3)
    }
}

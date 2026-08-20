import XCTest
@testable import Evenstar

/// Hai ràng buộc CloudKit áp lên `@Model`, và **cả hai đều không báo lỗi lúc
/// biên dịch**: không được có `@Attribute(.unique)`, và mọi thuộc tính lưu trữ
/// phải optional hoặc mang giá trị mặc định. Vi phạm chỉ lộ ra lúc chạy — hoặc
/// tệ hơn, chỉ lộ ở bản Release nói chuyện với môi trường Production.
///
/// Đây là test đọc **mã nguồn**, không phải test hành vi, và đó là chủ ý chứ
/// không phải chỗ lười. Test hành vi tương đương phải dựng một `ModelContainer`
/// mang `cloudKitDatabase`, thứ đòi entitlement iCloud mà bó test không có và
/// không nên có. Nên chỗ này đọc thẳng năm file trong `Models/`.
///
/// `throw XCTSkip` chứ không `XCTFail` khi không thấy thư mục nguồn: bó test
/// phải chạy được ở nơi mã nguồn không nằm cạnh nó.
final class ModelCloudKitConformanceTests: XCTestCase {

    /// `#filePath` là đường dẫn tuyệt đối lúc biên dịch, nên nó trỏ tới cây
    /// nguồn thật trên máy đang dịch — cách duy nhất để với tới `Models/` từ
    /// bên trong một bó test không mang mã nguồn.
    private static let modelsDirectory: URL? = {
        let here = URL(fileURLWithPath: #filePath)
        let dir = here
            .deletingLastPathComponent()            // EvenstarTests/
            .deletingLastPathComponent()            // Evenstar/ (thư mục dự án)
            .appendingPathComponent("Evenstar/Models", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }()

    private func modelSources() throws -> [URL] {
        guard let dir = Self.modelsDirectory else {
            throw XCTSkip("Không tìm thấy Models/ cạnh bó test — bỏ qua.")
        }
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// CloudKit không chấp nhận ràng buộc duy nhất. Bỏ nó **không** tháo mất
    /// hàng rào chống trùng nào đang được dùng: doc comment của `JamendoTrack`
    /// ghi rằng dựa vào `unique` chính là lỗi đã phải sửa, và
    /// `JamendoLibraryService.inFlightSaves` mới là thứ chống trùng thật.
    ///
    /// **Chỉ soi dòng mã, bỏ qua dòng comment.** Bản đầu của test này soi
    /// nguyên văn bản file, kể cả comment — và vô tình cấm luôn
    /// `DriveTrack`/`JamendoTrack` *nhắc tên* ràng buộc mà chúng vừa bỏ, đúng
    /// hai chỗ người đọc cần lời giải thích nhất. Ràng buộc đã mất, nhưng
    /// *lịch sử* của nó đáng được ghi lại; một test cấm nhắc tên thứ nó vừa
    /// xoá làm tài liệu tệ đi, không phải tốt lên. Đừng "đơn giản hoá" chỗ
    /// này về lại `source.contains(...)` trên cả file — trông gọn hơn, nhưng
    /// âm thầm phá tài liệu lần nữa.
    ///
    /// Bỏ qua bằng cách nhận diện dòng có bản rút gọn (đã trim khoảng trắng)
    /// bắt đầu bằng `//` — đủ dùng ở đây vì các file trong `Models/` không có
    /// block comment (`/* ... */`) và không có chuỗi ký tự nào chứa
    /// `@Attribute(.unique)`. Không dựng lexer Swift cho việc này.
    func testNoModelDeclaresAUniqueAttribute() throws {
        for url in try modelSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            let code = source
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(
                code.contains("@Attribute(.unique)"),
                "\(url.lastPathComponent) còn @Attribute(.unique) trong mã (ngoài comment). CloudKit từ chối nó."
            )
        }
    }

    /// Một thuộc tính không-optional, không mặc định là một cột mà CloudKit
    /// không đọc nổi khi bản ghi cũ chưa có nó. Bốn thuộc tính của
    /// `PlaybackState` đã mang mặc định từ trước vì đúng lý do ấy — doc comment
    /// của chúng nói rõ — nên mẫu để noi theo nằm sẵn trong repo.
    func testEveryStoredPropertyIsOptionalOrHasADefault() throws {
        var offenders: [String] = []
        for url in try modelSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("@Model") else { continue }
            for line in source.components(separatedBy: .newlines) {
                // Thuộc tính ở tầng kiểu là thụt đúng 4 dấu cách. `{` loại ra
                // thuộc tính tính toán, thứ không có cột nào trong lược đồ.
                guard line.hasPrefix("    var "), !line.contains("{") else { continue }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let declaredType = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if declaredType.contains("=") { continue }        // có mặc định
                if declaredType.hasSuffix("?") { continue }       // optional
                offenders.append("\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(
            offenders, [],
            "Các thuộc tính này phải optional hoặc mang giá trị mặc định thì CloudKit mới nhận."
        )
    }
}

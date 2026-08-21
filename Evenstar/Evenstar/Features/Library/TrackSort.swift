import Foundation

/// Thứ tự bày danh sách bài hát trong tab Bài hát.
///
/// **Ba trong bốn kiểu ở đây đọc những trường app đã ghi từ lâu mà chưa màn hình
/// nào đọc.** `playCount` và `lastPlayedAt` được `PlaybackService` cộng lên mỗi
/// lần một bài chạy quá ba mươi giây, và `DuplicateMerge` còn cẩn thận cộng dồn
/// chúng khi gộp hai hàng trùng từ hai máy — nhưng cho tới trước file này, không
/// ai nhìn thấy kết quả. `dateAdded` cũng vậy.
///
/// Ở file riêng chứ không nhét vào `SongsView` vì đây là chỗ **duy nhất** có
/// logic đáng sai trong cả tính năng, và nó là hàm thuần nên test được mà không
/// cần dựng view. `SongsView` đã hơn bốn trăm dòng; thứ nó cần là bớt việc chứ
/// không phải thêm.
enum TrackSort: String, CaseIterable, Identifiable {
    /// Tên A→Z. Mặc định, và khớp thứ tự `LibraryStore` vốn đã đưa ra.
    case title
    /// Mới thêm trước.
    case dateAdded
    /// Nghe gần đây nhất trước.
    case lastPlayed
    /// Nghe nhiều nhất trước.
    case playCount

    var id: String { rawValue }

    static let `default`: TrackSort = .title

    /// Chữ trên menu. Xem `LibraryTab.label` về lý do dùng `String(localized:)`
    /// chứ không phải chuỗi trần.
    var label: String {
        switch self {
        case .title:
            String(localized: "Tên A→Z",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .dateAdded:
            String(localized: "Mới thêm",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .lastPlayed:
            String(localized: "Nghe gần đây",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .playCount:
            String(localized: "Nghe nhiều nhất",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat.abc"
        case .dateAdded: "clock.badge.checkmark"
        case .lastPlayed: "clock.arrow.circlepath"
        case .playCount: "chart.bar.fill"
        }
    }

    /// Sắp lại danh sách. Hàm thuần: cùng đầu vào, cùng đầu ra, không đọc gì
    /// ngoài chính các bài được đưa vào.
    func apply(to tracks: [Track]) -> [Track] {
        switch self {
        case .title:
            tracks.sorted { Self.titleBefore($0, $1) }

        case .dateAdded:
            tracks.sorted {
                $0.dateAdded == $1.dateAdded
                    ? Self.titleBefore($0, $1)
                    : $0.dateAdded > $1.dateAdded
            }

        case .lastPlayed:
            // `nil` là "chưa nghe bao giờ", và nó xuống **cuối**.
            //
            // Đây là chỗ dễ làm ngược. Nếu coi `nil` như một mốc rất xa xưa thì
            // đúng; nếu để nó lên trước thì màn "Nghe gần đây" mở ra toàn bài
            // chưa nghe bao giờ — đúng ngược nghĩa cái tên nó mang.
            tracks.sorted {
                switch ($0.lastPlayedAt, $1.lastPlayedAt) {
                case let (l?, r?): return l == r ? Self.titleBefore($0, $1) : l > r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return Self.titleBefore($0, $1)
                }
            }

        case .playCount:
            tracks.sorted {
                $0.playCount == $1.playCount
                    ? Self.titleBefore($0, $1)
                    : $0.playCount > $1.playCount
            }
        }
    }

    /// Dòng phụ của hàng bài dưới kiểu sắp xếp này.
    ///
    /// Ở đây chứ không trong `SongsView` vì nó là thứ **dẫn xuất từ chính kiểu
    /// sắp xếp** — cùng một quyết định nói ra hai lần, một lần thành thứ tự và
    /// một lần thành chữ. Để hai nửa ấy ở hai file là mời chúng lệch nhau: đổi
    /// `apply(to:)` mà quên đổi chữ thì danh sách xếp theo một thứ và giải thích
    /// bằng một thứ khác.
    ///
    /// `nil` cho `.title` để `SongRow` quay về tên nghệ sĩ như mặc định — đó là
    /// chỗ tham số `subtitle` của nó vốn để dành.
    ///
    /// Ba kiểu còn lại bày ra chính con số vừa quyết định thứ tự. Không có nó
    /// thì danh sách đổi thứ tự mà không nói vì sao, và người dùng không kiểm
    /// chứng được thứ tự ấy có đúng không.
    func subtitle(for track: Track) -> String? {
        switch self {
        case .title:
            return nil
        case .dateAdded:
            return track.dateAdded.formatted(.relative(presentation: .named))
        case .lastPlayed:
            guard let when = track.lastPlayedAt else { return Self.neverPlayed }
            return when.formatted(.relative(presentation: .named))
        case .playCount:
            guard track.playCount > 0 else { return Self.neverPlayed }
            return String(
                format: String(localized: "%lld lượt",
                               bundle: AppLanguage.resolvedBundle,
                               locale: AppLanguage.resolvedLocale),
                track.playCount
            )
        }
    }

    /// Cùng một chữ cho cả hai kiểu sắp theo lượt nghe.
    ///
    /// Một bài chưa nghe bao giờ thì `playCount` là 0 **và** `lastPlayedAt` là
    /// `nil` — cùng một sự thật, nên phải cùng một chữ. Hai chuỗi riêng là hai
    /// chỗ để chúng trôi khỏi nhau.
    private static var neverPlayed: String {
        String(localized: "Chưa nghe",
               bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
    }

    /// Cắt hoà, dùng chung cho cả bốn kiểu.
    ///
    /// **Mọi kiểu sắp xếp đều phải cắt hoà, và cắt bằng cùng một thứ.** Mười bài
    /// cùng không lượt nghe mà xếp theo thứ tự `store.tracks` tình cờ đưa tới sẽ
    /// xáo lại mỗi lần thư viện đổi — người dùng đọc ra là app hỏng, không phải
    /// là một thứ tự.
    ///
    /// So theo kiểu người đọc (`.localizedStandard`), cùng cách `LibraryStore`
    /// so cho danh sách mặc định: `"Ô"` phải đứng cạnh `"O"` chứ không trôi ra
    /// tận đâu theo giá trị scalar.
    private static func titleBefore(_ a: Track, _ b: Track) -> Bool {
        a.title.compare(b.title, options: [.caseInsensitive, .diacriticInsensitive],
                        range: nil, locale: .current) == .orderedAscending
    }
}

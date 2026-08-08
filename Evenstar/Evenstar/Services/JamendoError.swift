import Foundation

/// What can go wrong talking to Jamendo.
///
/// Mirrors `DriveError` case for case where the failures are the same, so the
/// two sources report the same thing in the same words. `notShared` has no
/// analogue — a public catalogue has no sharing to get wrong.
enum JamendoError: Error, Equatable, LocalizedError {
    case missingClientID
    /// The device has no connectivity.
    case offline
    /// A transport failure that is not "no connectivity" — DNS, TLS, timeouts.
    /// Kept apart from `.offline` so the message never claims something untrue
    /// about the user's connection on a device that is, in fact, online.
    case connectionFailed
    /// Jamendo answered, and the answer was "too many requests". Its own thing
    /// because waiting fixes it, which is not true of the others.
    case rateLimited
    case decodingFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            String(localized: "Chưa cấu hình client ID cho Jamendo.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .offline:
            String(localized: "Không có kết nối mạng.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .connectionFailed:
            String(localized: "Không thể kết nối tới Jamendo. Vui lòng thử lại sau.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .rateLimited:
            String(localized: "Jamendo đang giới hạn số lượt truy cập. Thử lại sau ít phút.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .decodingFailed:
            String(localized: "Không đọc được dữ liệu từ Jamendo.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .notFound:
            String(localized: "Không tìm thấy bài này trên Jamendo.",
                   bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        }
    }
}

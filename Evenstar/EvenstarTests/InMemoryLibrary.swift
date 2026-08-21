import Foundation
import SwiftData
@testable import Evenstar

@MainActor
enum InMemoryLibrary {
    /// Dựng **đúng hình dạng hai kho** mà `EvenstarStores` dựng cho app, chỉ
    /// khác là trong bộ nhớ.
    ///
    /// Không phải chuyện thẩm mỹ. `NSManagedObjectModel` được lưu đệm theo tiến
    /// trình: app host của bó test chạy `EvenstarApp.init()` trước mọi test, và
    /// container của nó gán từng entity vào một *configuration* của Core Data —
    /// bốn bảng thư viện vào kho mặc định, `PlaybackState` vào kho `Playback`.
    /// Một container dựng sau đó trong cùng tiến trình, trên cùng năm model,
    /// dùng lại mô hình đã đệm ấy. Nên một cấu hình **đơn** ở đây sẽ thêm một
    /// kho cho configuration mặc định, thứ không còn chứa `PlaybackState`, và
    /// lượt `insert` đầu tiên của nó ném `NSInvalidArgumentException`: "Can't
    /// assign an object to a store that does not contain the object's entity."
    ///
    /// `cloudKitDatabase: .none` cũng bắt buộc, và vì một lý do khác: mặc định
    /// là `.automatic`, thứ đọc entitlement iCloud của **app host**. Từ khi
    /// target Evenstar có entitlement ấy, một cấu hình để mặc định sẽ dựng cả
    /// một `NSCloudKitMirroringDelegate` cho kho trong bộ nhớ của test.
    static func make() throws -> LibraryService {
        LibraryService(context: ModelContext(try makeContainer()))
    }

    /// Container hai kho trong bộ nhớ. Xem `make()` về vì sao phải hai.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(EvenstarStores.syncedModels + EvenstarStores.localOnlyModels),
            configurations:
                ModelConfiguration(schema: Schema(EvenstarStores.syncedModels),
                                   isStoredInMemoryOnly: true, cloudKitDatabase: .none),
                ModelConfiguration(EvenstarStores.localStoreName,
                                   schema: Schema(EvenstarStores.localOnlyModels),
                                   isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    static func makeTrack(title: String = "Sample",
                          artistName: String = "Unknown Artist",
                          albumTitle: String = "Unknown Album",
                          durationSeconds: Double = 180,
                          relativePath: String = "Music/sample.mp3",
                          artworkRelativePath: String? = nil,
                          format: String = "mp3") -> Track {
        Track(
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            durationSeconds: durationSeconds,
            relativePath: relativePath,
            artworkRelativePath: artworkRelativePath,
            format: format
        )
    }
}

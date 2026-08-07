import SwiftUI

/// Edits one track's title, artist and album.
///
/// The app reads tags once, at import, from whatever the file carries — and a
/// great many files carry nothing. A library of "Unknown Artist" is not a
/// cosmetic problem: the Album and Nghệ sĩ tabs group by exactly those fields,
/// so untagged files leave two whole screens grouping by a value that does not
/// exist. This is the only way to put that right from inside the app.
///
/// Local tracks only. `DriveTrack` has its own optional-tag columns and its own
/// deferred đợt for filling them; offering the same sheet there would write to
/// a row the next rescan reconciles.
struct TrackMetadataEditor: View {
    let track: Track

    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var errorMessage: String?

    /// Seeds the fields from the track, **with the placeholders cleared**.
    ///
    /// A user opening this on an untagged file would otherwise be handed a field
    /// containing the literal words "Unknown Artist" and have to delete them
    /// before typing. The placeholder is what the app shows in place of a
    /// missing value, not a value the user ever entered, so it has no business
    /// being in an editable field. Blank on the way out is turned back into the
    /// placeholder by `LibraryService.updateMetadata`.
    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(
            initialValue: track.artistName == MetadataPlaceholder.artist ? "" : track.artistName
        )
        _album = State(
            initialValue: track.albumTitle == MetadataPlaceholder.album ? "" : track.albumTitle
        )
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên bài hát", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Tên nghệ sĩ", text: $artist)
                        .textInputAutocapitalization(.words)
                    TextField("Tên album", text: $album)
                        .textInputAutocapitalization(.words)
                } footer: {
                    // Says what blank means, so leaving a field empty is a
                    // choice rather than something the user discovers after
                    // saving.
                    Text("Để trống Nghệ sĩ hoặc Album thì bài hát sẽ được xếp vào nhóm chưa rõ.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sửa thông tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // `.prominent` marks it as the one action this sheet exists
                    // for — the guidelines ask for exactly one primary action on
                    // the trailing side.
                    Button("Lưu") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    /// Dismisses only on success. A failed save has to leave the sheet up with
    /// the user's typing intact — closing it would discard the edit and say
    /// nothing.
    private func save() {
        errorMessage = nil
        do {
            try library.updateMetadata(
                title: title,
                artistName: artist,
                albumTitle: album,
                for: track
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

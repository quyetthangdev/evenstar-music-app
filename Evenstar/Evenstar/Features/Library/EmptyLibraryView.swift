import SwiftUI

struct EmptyLibraryView: View {
    let onImportTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("No music yet")
                .font(.title2.bold())
            Text("Import audio files from the Files app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onImportTap) {
                Label("Import Music", systemImage: "plus.circle.fill")
                    .font(.body.bold())
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

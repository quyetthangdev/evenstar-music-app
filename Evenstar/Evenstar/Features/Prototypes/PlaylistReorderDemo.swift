//
//  PlaylistReorderDemo.swift
//  Bản thử cho cách kéo thả sắp lại danh sách.
//
//  Chỉ còn là **lớp da**. Cử chỉ và chuyển động nằm ở `ReorderableStack`, dùng
//  chung với hàng đợi thật trong `QueuePanel` — nên thứ cảm nhận được ở đây
//  đúng là thứ chạy trong app, không phải một bản sao đã trôi đi.
//

import SwiftUI
import UIKit

// MARK: - Dữ liệu

struct PlaylistSong: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let glyph: String
    let colours: [Color]

    static let samples: [PlaylistSong] = [
        .init(title: "Chiều nay không có mưa bay", artist: "Vũ.", glyph: "cloud.rain.fill",
              colours: [.init(red: 0.31, green: 0.45, blue: 0.72), .init(red: 0.16, green: 0.20, blue: 0.38)]),
        .init(title: "Có hẹn với thanh xuân", artist: "MONSTAR", glyph: "sun.max.fill",
              colours: [.init(red: 0.78, green: 0.45, blue: 0.22), .init(red: 0.42, green: 0.20, blue: 0.14)]),
        .init(title: "Nhất thời", artist: "Hoàng Dũng", glyph: "moon.stars.fill",
              colours: [.init(red: 0.40, green: 0.28, blue: 0.58), .init(red: 0.18, green: 0.14, blue: 0.32)]),
        .init(title: "Đông kiếm em", artist: "Nguyên Hà", glyph: "snowflake",
              colours: [.init(red: 0.20, green: 0.45, blue: 0.45), .init(red: 0.10, green: 0.22, blue: 0.24)]),
        .init(title: "Bước qua nhau", artist: "Vũ.", glyph: "figure.walk",
              colours: [.init(red: 0.52, green: 0.30, blue: 0.30), .init(red: 0.24, green: 0.14, blue: 0.16)]),
        .init(title: "Lạ lùng", artist: "Vũ.", glyph: "sparkles",
              colours: [.init(red: 0.30, green: 0.42, blue: 0.34), .init(red: 0.14, green: 0.22, blue: 0.18)]),
        .init(title: "Mùa mưa ngâu nằm cạnh", artist: "Vũ.", glyph: "drop.fill",
              colours: [.init(red: 0.26, green: 0.36, blue: 0.50), .init(red: 0.12, green: 0.18, blue: 0.28)]),
        .init(title: "Tầng thượng 102", artist: "Cá Hồi Hoang", glyph: "building.2.fill",
              colours: [.init(red: 0.58, green: 0.34, blue: 0.42), .init(red: 0.26, green: 0.16, blue: 0.20)])
    ]
}

// MARK: - Màn hình

struct PlaylistReorderDemo: View {
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) { self.onClose = onClose }

    @State private var songs = PlaylistSong.samples
    @State private var isReordering = false

    private static let rowHeight: CGFloat = 60
    private static let rowSpacing: CGFloat = 6

    var body: some View {
        NavigationStack {
            let byID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
            ReorderableStack(
                ids: songs.map(\.id),
                rowHeight: Self.rowHeight,
                rowSpacing: Self.rowSpacing,
                isReordering: $isReordering,
                onTap: { _ in },
                onMove: { source, destination in
                    songs.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
                }
            ) { id, lifted, pressed in
                if let song = byID[id] {
                    Row(song: song)
                        .reorderCard(lifted: lifted, pressed: pressed,
                                     fill: .regularMaterial, pressedOpacity: 0.7)
                }
            }
            .padding(.horizontal, 16)
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onClose() } label: { Image(systemName: "xmark") }
                    }
                }
            }
        }
    }
}

// MARK: - Hàng

private struct Row: View {
    let song: PlaylistSong

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: song.colours,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: song.glyph)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.subheadline).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

#Preview {
    PlaylistReorderDemo()
}

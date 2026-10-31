import SwiftUI

/// Watch Sync (from the cog menu): choose playlists, albums and artists for the watch, see how much that is, and send it.
struct WatchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WatchSender.self) private var watch

    var body: some View {
        List {
            Section {
                status
                if watch.isPaired && watch.isAppInstalled {
                    Button {
                        watch.send()
                    } label: {
                        Label(watch.pendingTransfers > 0 ? "Sending… \(watch.pendingTransfers) left" : "Sync to Apple Watch",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(watch.selection.isEmpty && watch.onWatch.isEmpty)
                }
                if let problem = watch.problem { Text(problem).foregroundStyle(.red).font(.callout) }
            } footer: {
                Text("\(watch.wantedTracks.count) songs chosen (\(ByteCountFormatter.string(fromByteCount: watch.wantedSize, countStyle: .file))), \(watch.syncedCount) on the watch. Music on the watch plays through Bluetooth headphones.")
            }

            if !library.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(library.playlists) { p in
                        row(p.name, detail: "\(library.tracks(of: p).count) songs", item: .playlist(p.name))
                    }
                }
            }
            Section("Albums") {
                ForEach(library.albums) { a in
                    row(a.title, detail: a.artist, item: .album(a.id), cover: a.cover)
                }
            }
            Section("Artists") {
                ForEach(library.artists) { a in
                    row(a.name, detail: "\(a.tracks.count) songs", item: .artist(a.name.lowercased()))
                }
            }
        }
        .navigationTitle("Watch Sync")
        .overlay {
            if library.tracks.isEmpty {
                ContentUnavailableView("No Music Yet", systemImage: "applewatch",
                                       description: Text("Sync music to your iPhone from Legato on your computer first."))
            }
        }
    }

    @ViewBuilder private var status: some View {
        if !watch.isSupported {
            Label("This iPhone can't pair with an Apple Watch.", systemImage: "applewatch.slash")
        } else if !watch.isPaired {
            Label("No Apple Watch is paired.", systemImage: "applewatch.slash")
        } else if !watch.isAppInstalled {
            Label("Install Legato on your Apple Watch from the Watch app.", systemImage: "applewatch.and.arrow.forward")
        } else {
            Label("Apple Watch connected", systemImage: "applewatch.radiowaves.left.and.right")
        }
    }

    private func row(_ title: String, detail: String, item: WatchSender.Item, cover: String? = nil) -> some View {
        Button { watch.toggle(item) } label: {
            HStack(spacing: 12) {
                if cover != nil { CoverImage(path: cover, size: 96).frame(width: 36, height: 36) }
                VStack(alignment: .leading) {
                    Text(title).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: watch.isSelected(item) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(watch.isSelected(item) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(watch.isSelected(item) ? .isSelected : [])
    }
}

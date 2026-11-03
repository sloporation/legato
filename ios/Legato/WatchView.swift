import SwiftUI

/// Watch Sync (from the cog menu): choose playlists, albums and artists for the watch, see how much that is, and send it.
struct WatchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WatchSender.self) private var watch
    @State private var search = ""

    /// Every word typed has to be in the name or the detail (case and accents aside).
    private func matches(_ texts: String...) -> Bool {
        search.split(whereSeparator: \.isWhitespace).allSatisfy { word in texts.contains { $0.localizedStandardContains(word) } }
    }

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
                if (watch.waitingForWatch || watch.pendingTransfers > 0) && !watch.unconfirmed
                    && watch.syncedCount < watch.wantedTracks.count {
                    // the watch says what it has after each song, so this moves as they arrive (and songs still on their way after
                    // the app was closed show here too)
                    ProgressView(value: Double(watch.syncedCount), total: Double(max(watch.wantedTracks.count, 1))) {
                        Text("On the watch: \(watch.syncedCount) of \(watch.wantedTracks.count) songs")
                    } currentValueLabel: {
                        Text("Songs take a while each. Keep the watch near the iPhone; it carries on in the background.")
                    }
                } else if watch.waitingForWatch && watch.pendingTransfers == 0 {
                    if watch.unconfirmed {
                        Label("The watch hasn't said it got this sync. Open Legato on the watch, keep it near the iPhone, and sync again.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout)
                    } else {
                        Label("Sent. Waiting for the watch to say it has it…", systemImage: "hourglass")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }
            } footer: {
                Text("\(watch.wantedTracks.count) songs chosen (\(ByteCountFormatter.string(fromByteCount: watch.wantedSize, countStyle: .file))), \(watch.syncedCount) on the watch. Music on the watch plays through Bluetooth headphones.")
            }

            let playlists = library.playlists.filter { matches($0.name) }
            let albums = library.albums.filter { matches($0.title, $0.artist) }
            let artists = library.artists.filter { matches($0.name) }
            if !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { p in
                        row(p.name, detail: "\(library.tracks(of: p).count) songs", item: .playlist(p.name))
                    }
                }
            }
            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { a in
                        row(a.title, detail: a.artist, item: .album(a.id), cover: a.cover)
                    }
                }
            }
            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { a in
                        row(a.name, detail: "\(a.tracks.count) songs", item: .artist(a.name.lowercased()))
                    }
                }
            }
            if !search.isEmpty && playlists.isEmpty && albums.isEmpty && artists.isEmpty && !library.tracks.isEmpty {
                Section {
                    Text("No playlists, albums or artists match “\(search)”.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Watch Sync")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Playlists, albums and artists")
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

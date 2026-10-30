import SwiftUI

/// A list of tracks to play from: tapping one plays the list from there, in this order. Long-pressing one offers to play it, to add it
/// to a playlist, or to go to its album, its artist or a playlist it's in (leaving out the one this list already is). A header (an
/// album's cover, Play and Shuffle) goes above the rows. A playlist's own list can also lose a track (swipe, or the long-press menu) and
/// be put in a new order (Edit).
struct TrackList<Header: View>: View {
    enum Style { case numbered, artwork }

    let tracks: [Track]
    var style: Style = .artwork
    /// What this list is, if it is an album's or an artist's: the long-press menu doesn't offer to go where you already are.
    var here: Route? = nil
    @ViewBuilder var header: Header

    @Environment(Player.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(LibraryStore.self) private var library
    @State private var naming: Track?          // the track a new playlist is being named for
    @State private var newName = ""

    /// the playlist this list is, if it is one: its tracks can be removed and moved
    private var playlistName: String? { if case .playlist(let name) = here { name } else { nil } }

    var body: some View {
        List {
            Section { header }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            Section {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button { player.play(tracks, from: index) } label: { row(track) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { player.play(tracks, from: index) } label: { Label("Play", systemImage: "play") }
                            addToPlaylistMenu(track)
                            if let playlistName {
                                Button(role: .destructive) {
                                    library.change(PlaylistChange(op: .remove, playlist: playlistName, track: track.id))
                                } label: { Label("Remove from Playlist", systemImage: "minus.circle") }
                            }
                            Divider()
                            if here != .album(track.albumKey) {
                                Button { navigator.go(.album(track.albumKey)) } label: { Label("Go to Album", systemImage: "square.stack") }
                            }
                            let artist = track.albumArtistOrArtist.lowercased()
                            if here != .artist(artist) {
                                Button { navigator.go(.artist(artist)) } label: { Label("Go to Artist", systemImage: "music.mic") }
                            }
                            // the playlists it is in: one goes straight there, several make a submenu
                            let playlists = library.playlists(containing: track).filter { here != .playlist($0.name) }
                            if playlists.count == 1, let only = playlists.first {
                                Button { navigator.go(.playlist(only.name)) } label: {
                                    Label("Go to “\(only.name)”", systemImage: "music.note.list")
                                }
                            } else if playlists.count > 1 {
                                Menu {
                                    ForEach(playlists) { p in
                                        Button(p.name) { navigator.go(.playlist(p.name)) }
                                    }
                                } label: {
                                    Label("Go to Playlist", systemImage: "music.note.list")
                                }
                            }
                        } preview: {
                            TrackPreview(track: track, library: library)
                        }
                }
                .onDelete(perform: playlistName == nil ? nil : { rows in
                    for i in rows { library.change(PlaylistChange(op: .remove, playlist: playlistName!, track: tracks[i].id)) }
                })
                .onMove(perform: playlistName == nil ? nil : { rows, destination in
                    // one at a time: each goes after the track that ends up before it
                    var order = tracks.map(\.id)
                    let moving = rows.map { order[$0] }
                    order.move(fromOffsets: rows, toOffset: destination)
                    for id in moving {
                        let at = order.firstIndex(of: id)!
                        library.change(PlaylistChange(op: .move, playlist: playlistName!, track: id, after: at > 0 ? order[at - 1] : nil))
                    }
                })
            }
        }
        .listStyle(.plain)
        .overlay { if tracks.isEmpty { ContentUnavailableView("No Songs", systemImage: "music.note") } }
        .alert("New Playlist", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { naming = nil }
            Button("Create") {
                if let track = naming {
                    let name = library.freeName(newName)
                    library.change(PlaylistChange(op: .create, playlist: name))
                    library.change(PlaylistChange(op: .add, playlist: name, track: track.id))
                }
                naming = nil
            }
        } message: {
            Text("The song goes in it. Your computer gets the playlist at the next sync.")
        }
    }

    /// Add to Playlist: the playlists it isn't in yet, and a new one
    @ViewBuilder
    private func addToPlaylistMenu(_ track: Track) -> some View {
        Menu {
            Button { newName = ""; naming = track } label: { Label("New Playlist…", systemImage: "plus") }
            let others = library.playlists.filter { !$0.tracks.contains(track.id) }
            if !others.isEmpty {
                Divider()
                ForEach(others) { p in
                    Button(p.name) { library.change(PlaylistChange(op: .add, playlist: p.name, track: track.id)) }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
    }

    private func row(_ track: Track) -> some View {
        let playing = player.current?.id == track.id
        return HStack(spacing: 12) {
            switch style {
            case .numbered:
                Group {
                    if playing { Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint) }
                    else { Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "").foregroundStyle(.secondary) }
                }
                .font(.subheadline.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
            case .artwork:
                CoverImage(path: track.cover, size: 96).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle).lineLimit(1).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                if style == .artwork || track.artist != track.albumArtistOrArtist {
                    Text(style == .artwork ? [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ") : track.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if style == .artwork && playing {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint).font(.caption)
            }
            if track.duration > 0 {
                Text(Duration.seconds(track.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// What a long-press lifts up: the cover, the title, artist and album. (It is drawn outside the app's views, so it doesn't get their
/// environment: the library is handed to it.)
private struct TrackPreview: View {
    let track: Track
    let library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(path: track.cover, size: 600).frame(width: 260, height: 260)
            Text(track.displayTitle).font(.headline).lineLimit(2)
            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding()
        .frame(width: 292)
        .environment(library)
    }
}

/// An album cover from the synced files, or a placeholder.
struct CoverImage: View {
    let path: String?
    var size: CGFloat = 300          // pixels to decode at

    @Environment(LibraryStore.self) private var library
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: path) { image = await CoverCache.shared.image(library.coverURL(path), size: size) }
    }
}

/// Decoded covers, so scrolling doesn't decode them again.
actor CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(_ url: URL?, size: CGFloat) async -> UIImage? {
        guard let url else { return nil }
        let key = "\(url.path)#\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = UIImage(contentsOfFile: url.path) else { return nil }
        let image = await full.byPreparingThumbnail(ofSize: CGSize(width: size, height: size)) ?? full
        cache.setObject(image, forKey: key)
        return image
    }
}

import SwiftUI
import WatchKit

@main
struct LegatoWatchApp: App {
    @State private var library: LibraryStore
    @State private var player: Player
    private let receiver: WatchReceiver

    init() {
        let library = LibraryStore()
        _library = State(initialValue: library)
        _player = State(initialValue: Player(library: library))
        receiver = WatchReceiver(root: library.root) { library.reload(force: true) }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchLibraryView() }
                .environment(library)
                .environment(player)
        }
    }
}

/// What's on the watch: Now Playing, then Playlists, Albums, Artists and Songs.
struct WatchLibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        List {
            if player.current != nil {
                NavigationLink { NowPlayingView() } label: {
                    Label { Text(player.current?.displayTitle ?? "").lineLimit(1) } icon: { Image(systemName: "waveform") }
                }
            }
            if library.tracks.isEmpty {
                Text("Choose music for your watch in Legato on your iPhone, under Apple Watch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if !library.playlists.isEmpty {
                    NavigationLink { list("Playlists", library.playlists.map { ($0.name, library.tracks(of: $0)) }) } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }
                NavigationLink { list("Albums", library.albums.map { ($0.title, $0.tracks) }) } label: {
                    Label("Albums", systemImage: "square.stack")
                }
                NavigationLink { list("Artists", library.artists.map { ($0.name, $0.tracks) }) } label: {
                    Label("Artists", systemImage: "music.mic")
                }
                NavigationLink { WatchTrackList(title: "Songs", tracks: library.songsByTitle) } label: {
                    Label("Songs", systemImage: "music.note")
                }
            }
        }
        .navigationTitle("Legato")
    }

    private func list(_ title: String, _ groups: [(String, [Track])]) -> some View {
        List(groups, id: \.0) { name, tracks in
            NavigationLink { WatchTrackList(title: name, tracks: tracks) } label: { Text(name).lineLimit(2) }
        }
        .navigationTitle(title)
    }
}

/// Shuffle, then the tracks: tapping one plays the list from there and opens Now Playing.
struct WatchTrackList: View {
    let title: String
    let tracks: [Track]
    @Environment(Player.self) private var player
    @State private var nowPlaying = false

    var body: some View {
        List {
            Button { player.shufflePlay(tracks); nowPlaying = true } label: { Label("Shuffle", systemImage: "shuffle") }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    player.shuffle = false
                    player.play(tracks, from: index)
                    nowPlaying = true
                } label: {
                    VStack(alignment: .leading) {
                        Text(track.displayTitle).lineLimit(2)
                        Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(isPresented: $nowPlaying) { NowPlayingView() }
    }
}

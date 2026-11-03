import SwiftUI
import WatchKit

@main
struct LegatoWatchApp: App {
    @State private var library: LibraryStore
    @State private var player: Player
    @State private var phone: PhoneRemote
    private let receiver: WatchReceiver
    @Environment(\.scenePhase) private var phase

    init() {
        let library = LibraryStore()
        let phone = PhoneRemote()
        _library = State(initialValue: library)
        _player = State(initialValue: Player(library: library))
        _phone = State(initialValue: phone)
        receiver = WatchReceiver(root: library.root, remote: phone) { library.reload(force: true) }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(library)
                .environment(player)
                .environment(phone)
                .onChange(of: phase, initial: true) { _, phase in phone.setActive(phase == .active) }
        }
    }
}

/// Three pages: Now Playing in the middle, where the app opens; the music to its left (swipe right), the iPhone's while the iPhone
/// is in reach (the watch is its remote), else the watch's own; and Up Next to its right.
struct WatchRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Player.self) private var player
    @Environment(PhoneRemote.self) private var phone

    enum Page { case music, nowPlaying, upNext }
    @State private var page = Page.nowPlaying
    /// The watch's own player is the one Now Playing shows (a song from On This Watch was played), though the iPhone is in reach.
    @State private var onWatch = false

    /// What Now Playing and Up Next show: the iPhone's player while it's in reach, unless the watch's own was the last played.
    private var playback: any Playback {
        !phone.connected || onWatch || (player.isPlaying && phone.current == nil) ? player : phone
    }

    var body: some View {
        if !phone.connected && !phone.decided {
            ProgressView("Looking for your iPhone…")
        } else {
            TabView(selection: $page) {
                NavigationStack {
                    if phone.connected {
                        WatchLibraryView(library: phone.library, playback: phone, phone: phone, onWatch: player, watchLibrary: library)
                    } else {
                        WatchLibraryView(library: library, playback: player)
                    }
                }
                .tag(Page.music)
                NavigationStack { WatchNowPlaying(playback: playback) }
                    .tag(Page.nowPlaying)
                NavigationStack { WatchUpNext(playback: playback) }
                    .tag(Page.upNext)
            }
            .tabViewStyle(.page)
            .environment(\.played) { playback in
                onWatch = playback is Player && phone.connected
                page = .nowPlaying
            }
            .id(phone.connected)        // (fresh pages when it swaps)
        }
    }
}

extension EnvironmentValues {
    /// Called when a song is played from a list: turns to Now Playing, showing the player it plays on.
    @Entry var played: (any Playback) -> Void = { _ in }
}

/// What comes after the current song.
struct WatchUpNext: View {
    let playback: any Playback

    var body: some View {
        List {
            if playback.upNext.isEmpty {
                Text(playback.current == nil ? "Nothing's playing." : "Nothing's queued after this song.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(playback.upNext.prefix(50).enumerated()), id: \.offset) { _, track in
                VStack(alignment: .leading) {
                    Text(track.displayTitle).lineLimit(2)
                    Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .navigationTitle("Up Next")
    }
}

/// A library: Playlists, Albums, Artists and Songs. The iPhone's (with `phone`), or the watch's own.
struct WatchLibraryView: View {
    let library: LibraryStore
    let playback: any Playback
    var phone: PhoneRemote? = nil
    /// The watch's own player, while the iPhone's library shows: what it's still playing, if anything.
    var onWatch: Player? = nil
    /// The music on the watch, while the iPhone's library shows: a row at the end opens it.
    var watchLibrary: LibraryStore? = nil
    var title: LocalizedStringKey? = nil

    var body: some View {
        List {
            if library.tracks.isEmpty {
                if let phone {
                    if phone.loading {
                        HStack { ProgressView().frame(width: 20); Text("Getting your iPhone's music…").font(.footnote) }
                    } else if let problem = phone.libraryProblem {
                        Text(problem).font(.footnote).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await phone.fetchLibrary() } }
                    } else {
                        Text("There's no music in Legato on your iPhone yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose music for your watch in Legato on your iPhone: the cog menu, then Watch Sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !library.playlists.isEmpty {
                    NavigationLink {
                        list("Playlists", library.playlists.map { ($0.name, library.tracks(of: $0), .playlist($0.name)) })
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }
                NavigationLink { list("Albums", library.albums.map { ($0.title, $0.tracks, .album($0.id)) }) } label: {
                    Label("Albums", systemImage: "square.stack")
                }
                NavigationLink { list("Artists", library.artists.map { ($0.name, $0.tracks, .artist($0.name)) }) } label: {
                    Label("Artists", systemImage: "music.mic")
                }
                NavigationLink { WatchTrackList(title: "Songs", tracks: library.songsByTitle, source: .songs, playback: playback) } label: {
                    Label("Songs", systemImage: "music.note")
                }
            }
            if let watchLibrary, let onWatch {
                Section {
                    NavigationLink {
                        WatchLibraryView(library: watchLibrary, playback: onWatch, title: "On This Watch")
                    } label: {
                        VStack(alignment: .leading) {
                            Label("On This Watch", systemImage: "applewatch")
                            Text(watchLibrary.tracks.isEmpty ? "No music yet" : "\(watchLibrary.tracks.count) songs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title ?? (phone == nil ? "Legato" : "iPhone"))
    }

    private func list(_ title: String, _ groups: [(String, [Track], Remote.Source)]) -> some View {
        List(groups, id: \.0) { name, tracks, source in
            NavigationLink { WatchTrackList(title: name, tracks: tracks, source: source, playback: playback) } label: {
                Text(name).lineLimit(2)
            }
        }
        .navigationTitle(title)
    }
}

/// Shuffle, then the tracks: tapping one plays the list from there and turns to Now Playing.
struct WatchTrackList: View {
    let title: String
    let tracks: [Track]
    let source: Remote.Source
    let playback: any Playback
    @Environment(\.played) private var played

    var body: some View {
        List {
            Button { playback.shufflePlay(tracks, source: source); played(playback) } label: { Label("Shuffle", systemImage: "shuffle") }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    playback.play(tracks, from: index, source: source)
                    played(playback)
                } label: {
                    VStack(alignment: .leading) {
                        Text(track.displayTitle).lineLimit(2)
                        Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

import SwiftUI

/// The Music tab: every track on the phone, grouped by artist and album (so an album's tracks sit together, in order). Search narrows
/// it by title, artist or album. Long-press a track to go to its album, artist or playlists. The cog at the top right holds the rest.
struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @State private var search = ""

    var body: some View {
        let tracks = library.tracksInAlbumOrder.filter {
            search.isEmpty || [$0.displayTitle, $0.artist, $0.albumArtist, $0.album].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        Group {
            if library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("No Music Yet", systemImage: "music.note")
                } description: {
                    Text(library.problem ?? String(localized: "Plug your iPhone into your computer, open Legato there, and choose the playlists, artists and albums to put on it."))
                }
            } else {
                TrackList(tracks: tracks, style: .artwork) {
                    PlayShuffleButtons(tracks: tracks)
                }
                .overlay {
                    if tracks.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists, albums")
        .navigationTitle("Music")
        .withAppMenu()
    }
}

/// The Playlists tab: the playlists synced from the desktop (its .m3u files), each opening its tracks in its own order. + makes a new
/// one; swiping or long-pressing one renames or deletes it. The desktop gets the changes at the next sync.
struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var naming: PlaylistNaming?
    @State private var deleting: Playlist?

    var body: some View {
        List(library.playlists) { playlist in
            Button { navigator.go(.playlist(playlist.name)) } label: {
                HStack(spacing: 12) {
                    CoverImage(path: library.tracks(of: playlist).first?.cover, size: 120).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                        Text(library.tracks(of: playlist).count == 1 ? "1 song" : "\(library.tracks(of: playlist).count) songs")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { naming = .rename(playlist.name) } label: { Label("Rename…", systemImage: "pencil") }
                Button(role: .destructive) { deleting = playlist } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions {
                Button(role: .destructive) { deleting = playlist } label: { Label("Delete", systemImage: "trash") }
                Button { naming = .rename(playlist.name) } label: { Label("Rename", systemImage: "pencil") }
            }
        }
        .listStyle(.plain)
        .overlay {
            if library.playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                                       description: Text("Make one with +, or choose playlists to put on your iPhone in Legato on your computer."))
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { naming = .create } label: { Image(systemName: "plus") }.accessibilityLabel("New Playlist")
            }
        }
        .playlistNaming($naming)
        .playlistDeleting($deleting)
        .withAppMenu()
    }
}

/// Naming a playlist: a new one, or a new name for one.
enum PlaylistNaming: Identifiable {
    case create
    case rename(String)
    var id: String { if case .rename(let name) = self { "rename:" + name } else { "create" } }
}

private struct PlaylistNamingAlert: ViewModifier {
    @Binding var naming: PlaylistNaming?
    var renamed: (String) -> Void
    @Environment(LibraryStore.self) private var library
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(naming.map { if case .create = $0 { "New Playlist" } else { "Rename Playlist" } } ?? "",
                   isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) { naming = nil }
                Button(naming.map { if case .create = $0 { "Create" } else { "Rename" } } ?? "") {
                    switch naming {
                    case .create:
                        library.change(PlaylistChange(op: .create, playlist: library.freeName(name)))
                    case .rename(let old):
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && trimmed != old {
                            let new = library.freeName(trimmed)
                            library.change(PlaylistChange(op: .rename, playlist: old, to: new))
                            renamed(new)
                        }
                    case nil: break
                    }
                    naming = nil
                }
            }
            .onChange(of: naming?.id) { _, _ in
                if case .rename(let old) = naming { name = old } else { name = "" }
            }
    }
}

private struct PlaylistDeletingAlert: ViewModifier {
    @Binding var deleting: Playlist?
    var deleted: () -> Void
    @Environment(LibraryStore.self) private var library

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                   titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                if let p = deleting { library.change(PlaylistChange(op: .delete, playlist: p.name)); deleted() }
                deleting = nil
            }
        } message: {
            Text("The songs stay. Your computer moves the playlist to the Trash at the next sync.")
        }
    }
}

extension View {
    func playlistNaming(_ naming: Binding<PlaylistNaming?>, renamed: @escaping (String) -> Void = { _ in }) -> some View {
        modifier(PlaylistNamingAlert(naming: naming, renamed: renamed))
    }
    func playlistDeleting(_ deleting: Binding<Playlist?>, deleted: @escaping () -> Void = {}) -> some View {
        modifier(PlaylistDeletingAlert(deleting: deleting, deleted: deleted))
    }
}

/// One album's tracks, in album order, under its cover.
struct AlbumView: View {
    let key: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let album = library.albums.first(where: { $0.id == key }) {
            TrackList(tracks: album.tracks, style: .numbered, here: .album(key)) {
                VStack(spacing: 6) {
                    CoverImage(path: album.cover, size: 600)
                        .frame(width: 240, height: 240)
                        .shadow(radius: 8, y: 4)
                        .padding(.bottom, 8)
                    Text(album.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(album.artist).font(.title3).foregroundStyle(.tint)
                    Text([album.genre, album.year > 0 ? String(album.year) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    PlayShuffleButtons(tracks: album.tracks).padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This album is no longer on your iPhone", systemImage: "square.stack")
        }
    }
}

/// One artist's tracks: their albums in order, oldest first.
struct ArtistView: View {
    let name: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let artist = library.artists.first(where: { $0.name.lowercased() == name }) {
            TrackList(tracks: artist.tracks, style: .artwork, here: .artist(name)) {
                PlayShuffleButtons(tracks: artist.tracks)
            }
            .navigationTitle(artist.name)
        } else {
            ContentUnavailableView("This artist is no longer on your iPhone", systemImage: "music.mic")
        }
    }
}

/// One playlist's tracks, in its own order. Edit puts them in a new one; the menu renames or deletes the playlist.
struct PlaylistView: View {
    let name: String
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var naming: PlaylistNaming?
    @State private var deleting: Playlist?

    var body: some View {
        if let playlist = library.playlists.first(where: { $0.name == name }) {
            let tracks = library.tracks(of: playlist)
            TrackList(tracks: tracks, style: .artwork, here: .playlist(name)) {
                PlayShuffleButtons(tracks: tracks)
            }
            .navigationTitle(playlist.name)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !tracks.isEmpty { EditButton() }
                    Menu {
                        Button { naming = .rename(name) } label: { Label("Rename…", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = playlist } label: { Label("Delete Playlist", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Playlist")
                }
            }
            // the page follows the playlist to its new name, and closes when it's gone
            .playlistNaming($naming) { new in
                if let last = navigator.path.indices.last { navigator.path[last] = .playlist(new) }
            }
            .playlistDeleting($deleting) { navigator.path.removeLast() }
        } else {
            ContentUnavailableView("This playlist is no longer on your iPhone", systemImage: "music.note.list")
        }
    }
}

/// Room for settings to come.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
            Section {
                LabeledContent("Songs", value: "\(library.tracks.count)")
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
                if let generated = library.manifest?.generated {
                    LabeledContent("Last synced", value: generated.formatted(.relative(presentation: .named)))
                }
            } header: {
                Text("On This iPhone")
            } footer: {
                if let source = library.manifest?.source { Text("From \(source).") }
            }
        }
        .navigationTitle("Settings")
    }
}

/// Not built yet: an equaliser needs the player moved onto AVAudioEngine, where the sound can be shaped before it plays.
struct EqualiserView: View {
    var body: some View {
        ContentUnavailableView("Equaliser", systemImage: "slider.vertical.3", description: Text("Coming soon."))
            .navigationTitle("Equaliser")
    }
}

/// Play from the top, or shuffle everything.
struct PlayShuffleButtons: View {
    let tracks: [Track]
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Button { player.shuffle = false; player.play(tracks) } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            Button { player.shufflePlay(tracks) } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(tracks.isEmpty)
    }
}

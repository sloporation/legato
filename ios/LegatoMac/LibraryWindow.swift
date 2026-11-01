import SwiftUI

/// The window: songs, albums, artists and playlists down the side with the phones, the tracks in a table, the player along the bottom.
/// The music folders are in Settings.
struct LibraryWindow: View {
    @Environment(MusicFolders.self) private var library
    @Environment(Phones.self) private var phones
    @Environment(\.openSettings) private var openSettings
    @State private var pane: Pane? = .songs
    @State private var naming: Naming?
    @State private var search = ""

    enum Pane: Hashable {
        case songs, albums, artists
        case playlist(String)       // its name
        case phone(String)          // its id
    }

    /// Making or renaming a playlist: what it is called now (nil: a new one).
    struct Naming: Identifiable {
        var playlist: String?
        var name: String
        var id: String { playlist ?? "" }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                content
            }
            Divider()
            PlayerBar()
        }
        .onChange(of: pane) { search = "" }
        .toolbar {
            if library.scanning {
                ToolbarItem { ProgressView().controlSize(.small) }
            }
        }
        .alert(naming?.playlist == nil ? "New Playlist" : "Rename Playlist", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: Binding(get: { naming?.name ?? "" }, set: { naming?.name = $0 }))
            Button(naming?.playlist == nil ? "Make" : "Rename") { finishNaming() }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .alert("“\(phones.asking?.name ?? "")” wants to sync with this Mac", isPresented: Binding(get: { phones.asking != nil }, set: { _ in })) {
            Button("Allow") { if let id = phones.asking?.id { phones.allow(id); pane = .phone(id) } }
            Button("Don't Allow", role: .cancel) { if let id = phones.asking?.id { phones.refuse(id) } }
        } message: {
            Text("Check that the phone shows this code:\n\n\((phones.asking?.code ?? "").replacingOccurrences(of: " ", with: "\u{00A0}"))\n\nIf it doesn't, don't allow it. Once allowed, it will get the music you choose here, and its playlist changes will come back into your playlists.")
        }
        .alert("Legato", isPresented: Binding(get: { library.problem != nil }, set: { if !$0 { library.problem = nil } })) {
            Button("OK") { library.problem = nil }
        } message: {
            Text(library.problem ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $pane) {
            Section("Library") {
                Label("Songs", systemImage: "music.note").tag(Pane.songs)
                Label("Albums", systemImage: "square.stack").tag(Pane.albums)
                Label("Artists", systemImage: "music.mic").tag(Pane.artists)
            }
            Section {
                ForEach(library.playlists) { list in
                    Label(list.name, systemImage: "music.note.list")
                        .tag(Pane.playlist(list.name))
                        .dropDestination(for: String.self) { items, _ in
                            let dropped = TrackDrag.tracks(items, in: library)
                            guard !dropped.isEmpty else { return false }
                            library.add(dropped, to: list.name)
                            return true
                        }
                        .contextMenu {
                            Button("Rename…") { naming = Naming(playlist: list.name, name: list.name) }
                            Button("Delete", role: .destructive) {
                                if library.deletePlaylist(list.name), pane == .playlist(list.name) { pane = .songs }
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button("New Playlist", systemImage: "plus") { naming = Naming(playlist: nil, name: "") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            Section("Phones") {
                ForEach(phones.phones.filter { $0.allowed || pane == .phone($0.id) }) { phone in
                    Label(phone.name, systemImage: "iphone")
                        .tag(Pane.phone(phone.id))
                }
                if !phones.phones.contains(where: \.allowed) {
                    Text("Open Legato on your iPhone and choose Sync with Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(height: 44, alignment: .topLeading)
                        .selectionDisabled()
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if library.folders.isEmpty && pane.map({ if case .phone = $0 { false } else { true } }) ?? true {
            ContentUnavailableView {
                Label("No Music Yet", systemImage: "music.note.list")
            } description: {
                Text("Choose the folders your music is in, in Settings.")
            } actions: {
                Button("Open Settings…") { openSettings() }
            }
        } else {
            switch pane ?? .songs {
            case .songs:
                let shown = TrackFilter(search)(library.songsByTitle)
                TrackTable(tracks: shown)
                    .overlay { if shown.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
                    .searchable(text: $search, placement: .toolbar, prompt: "Search, or field:text")
                    .navigationTitle("Songs")
                    .navigationSubtitle(search.isEmpty ? "\(library.tracks.count) songs" : "\(shown.count) of \(library.tracks.count) songs")
            case .albums:
                AlbumsPane()
                    .navigationTitle("Albums")
            case .artists:
                ArtistsPane()
                    .navigationTitle("Artists")
            case .playlist(let name):
                if let list = library.playlists.first(where: { $0.name == name }) {
                    TrackTable(tracks: library.tracks(of: list), playlist: name)
                        .navigationTitle(name)
                        .navigationSubtitle("\(list.tracks.count) songs")
                }
            case .phone(let id):
                if phones.phone(id) != nil {
                    PhoneView(id: id) { pane = .songs }
                }
            }
        }
    }

    private func finishNaming() {
        guard let n = naming else { return }
        naming = nil
        if let old = n.playlist {
            if library.renamePlaylist(old, to: n.name) { pane = .playlist(n.name.trimmingCharacters(in: .whitespaces)) }
        } else if let made = library.createPlaylist(n.name) {
            pane = .playlist(made)
        }
    }
}

/// Albums as covers; the one clicked shows its songs in the inspector at the right.
struct AlbumsPane: View {
    @Environment(MusicFolders.self) private var library
    @State private var chosen: String?          // Album.id

    var body: some View {
        let album = library.albums.first { $0.id == chosen }
        AlbumGrid(albums: library.albums, chosen: $chosen)
            .inspector(isPresented: Binding(get: { album != nil }, set: { if !$0 { chosen = nil } })) {
                Group {
                    if let album { AlbumTracks(album: album) { chosen = nil } }
                }
                .inspectorColumnWidth(min: 320, ideal: 400, max: 600)
            }
    }
}

/// The artists in a column; the one chosen at the right with each of their albums and its songs under it (their own albums whole,
/// just their songs on someone else's).
struct ArtistsPane: View {
    @Environment(MusicFolders.self) private var library
    @State private var artist: String?

    var body: some View {
        let name = artist ?? library.artists.first?.name
        HSplitView {
            List(library.artists, selection: Binding(get: { name }, set: { artist = $0 })) { a in
                Text(a.name).tag(a.name)
            }
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 320, maxHeight: .infinity)
            Group {
                if let name { ArtistAlbums(name: name).id(name) }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// An artist's albums, each with its songs under it, in one list: select across them, drag to a playlist, double-click to play.
struct ArtistAlbums: View {
    let name: String
    @Environment(MusicFolders.self) private var library
    @Environment(Player.self) private var player
    @State private var selection = Set<Track.ID>()
    @State private var editing: TrackTable.Editing?

    var body: some View {
        let theirs = Set(library.tracks(ofArtist: name).map(\.id))
        let groups: [(album: Album, tracks: [Track])] = library.albums.compactMap { album in
            guard album.tracks.contains(where: { theirs.contains($0.id) }) else { return nil }
            let own = album.artist.caseInsensitiveCompare(name) == .orderedSame || album.tracks.allSatisfy { theirs.contains($0.id) }
            return (album, own ? album.tracks : album.tracks.filter { theirs.contains($0.id) })
        }
        let all = groups.flatMap(\.tracks)
        List(selection: $selection) {
            ForEach(groups, id: \.album.id) { group in
                Section {
                    ForEach(group.tracks) { track in
                        AlbumTrackRow(track: track)
                            .tag(track.id)
                            .draggable(TrackDrag.payload(track, selection: selection, in: all))
                    }
                } header: {
                    AlbumHeader(album: group.album, tracks: group.tracks, coverSize: 72)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
            }
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            TrackMenu(chosen: all.filter { ids.contains($0.id) }, list: all,
                      play: { play(ids, in: all) }, getInfo: { editing = .init(tracks: all.filter { ids.contains($0.id) }) })
        } primaryAction: { ids in
            play(ids, in: all)
        }
        .sheet(item: $editing) { TagEditor(tracks: $0.tracks) }
        .focusedValue(\.songs, SongActions(chosen: all.filter { selection.contains($0.id) }) { editing = .init(tracks: $0) })
        .navigationSubtitle(name)
    }

    private func play(_ ids: Set<Track.ID>, in all: [Track]) {
        guard let index = all.firstIndex(where: { ids.contains($0.id) }) else { return }
        player.play(all, from: index)
    }
}

/// A song under its album: number, title (with the speaker when it's playing), time.
struct AlbumTrackRow: View {
    let track: Track
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            Text(track.trackNumber > 0 ? String(track.trackNumber) : "")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.tint)
                .opacity(player.current?.id == track.id ? 1 : 0)
            Text(track.displayTitle).lineLimit(1)
            Spacer()
            Text(minutesAndSeconds(track.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// An album's cover, name, artist, year and length, and buttons to play it.
struct AlbumHeader: View {
    let album: Album
    let tracks: [Track]
    var coverSize: CGFloat = 96
    @Environment(Player.self) private var player

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(path: album.cover)
                .frame(width: coverSize, height: coverSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title).font(.title3.bold()).foregroundStyle(.primary).lineLimit(2)
                Text(album.artist).foregroundStyle(.secondary).lineLimit(1)
                Text([album.year > 0 ? String(album.year) : nil, album.genre.isEmpty ? nil : album.genre,
                      String(localized: "\(tracks.count) songs"), minutesAndSeconds(tracks.reduce(0) { $0 + $1.duration })]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HStack {
                    Button("Play", systemImage: "play.fill") { player.play(tracks) }
                        .buttonStyle(.borderedProminent)
                    Button("Shuffle", systemImage: "shuffle") { player.shufflePlay(tracks) }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }
}

/// An album's songs, with its header above them (in the Albums inspector).
struct AlbumTracks: View {
    let album: Album
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AlbumHeader(album: album, tracks: album.tracks)
                .overlay(alignment: .topTrailing) {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(14)
            Divider()
            TrackTable(tracks: album.tracks, style: .album)
        }
    }
}

/// Albums as covers: a click picks one (`chosen`).
struct AlbumGrid: View {
    let albums: [Album]
    @Binding var chosen: String?
    var minimum: CGFloat = 150

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: minimum + 50), spacing: 18)], spacing: 22) {
                ForEach(albums) { album in
                    Button { chosen = album.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            CoverImage(path: album.cover)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.accentColor, lineWidth: 3)
                                        .opacity(chosen == album.id ? 1 : 0)
                                }
                            Text(album.title).lineLimit(1)
                            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

/// An album cover from the cover cache, loaded off the main thread; a placeholder when there is none.
struct CoverImage: View {
    let path: String?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .task(id: path) {
            guard let path else { image = nil; return }
            image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: path) }.value
        }
    }
}

/// Tracks; double-click (or Return) plays from there to the end of the list. Shift- and ⌘-click select several; dragging takes the
/// selected ones (to a playlist in the sidebar). In a playlist, songs can also be taken out and moved.
struct TrackTable: View {
    enum Style { case full, album }
    let tracks: [Track]
    var playlist: String? = nil
    var style = Style.full
    @Environment(Player.self) private var player
    @State private var selection = Set<Track.ID>()
    @State private var editing: Editing?

    struct Editing: Identifiable {
        let id = UUID()
        var tracks: [Track]
    }

    var body: some View {
        table
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            TrackMenu(chosen: tracks.filter { ids.contains($0.id) }, list: tracks, playlist: playlist,
                      play: { play(ids) }, getInfo: { editing = Editing(tracks: tracks.filter { ids.contains($0.id) }) })
        } primaryAction: { ids in
            play(ids)
        }
        .sheet(item: $editing) { TagEditor(tracks: $0.tracks) }
        .focusedValue(\.songs, SongActions(chosen: tracks.filter { selection.contains($0.id) }) { editing = Editing(tracks: $0) })
    }

    @ViewBuilder private var table: some View {
        switch style {
        case .full:
            Table(of: Track.self, selection: $selection) {
                TableColumn("Title") { title($0) }
                TableColumn("Artist", value: \.artist)
                TableColumn("Album", value: \.album)
                TableColumn("Time") { time($0) }.width(56)
            } rows: {
                ForEach(tracks) { TableRow($0).draggable(TrackDrag.payload($0, selection: selection, in: tracks)) }
            }
        case .album:
            Table(of: Track.self, selection: $selection) {
                TableColumn("#") { track in
                    Text(track.trackNumber > 0 ? String(track.trackNumber) : "").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(28)
                TableColumn("Title") { title($0) }
                TableColumn("Time") { time($0) }.width(56)
            } rows: {
                ForEach(tracks) { TableRow($0).draggable(TrackDrag.payload($0, selection: selection, in: tracks)) }
            }
        }
    }

    private func title(_ track: Track) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.tint)
                .opacity(player.current?.id == track.id ? 1 : 0)
            Text(track.displayTitle)
        }
    }

    private func time(_ track: Track) -> some View {
        Text(minutesAndSeconds(track.duration)).monospacedDigit().foregroundStyle(.secondary)
    }

    private func play(_ ids: Set<Track.ID>) {
        guard let index = tracks.firstIndex(where: { ids.contains($0.id) }) else { return }
        player.play(tracks, from: index)
    }
}

/// The songs' menu: play, add to a playlist, Get Info, Show in Finder; in a playlist, move and remove.
struct TrackMenu: View {
    let chosen: [Track]
    let list: [Track]                   // the songs shown, in order
    var playlist: String? = nil
    var play: () -> Void
    var getInfo: () -> Void
    @Environment(MusicFolders.self) private var library

    var body: some View {
        if !chosen.isEmpty {
            Button("Play", action: play)
            Menu("Add to Playlist") {
                ForEach(library.playlists.filter { $0.name != playlist }) { list in
                    Button(list.name) { library.add(chosen, to: list.name) }
                }
                Divider()
                Button("New Playlist") {
                    if let name = library.createPlaylist(chosen.count == 1 ? chosen[0].album : "") { library.add(chosen, to: name) }
                }
            }
            Button("Get Info…", action: getInfo)
            Button("Show in Finder") { library.reveal(chosen) }
            if let playlist {
                Divider()
                if chosen.count == 1, let i = list.firstIndex(of: chosen[0]) {
                    Button("Move Up") { library.move(chosen[0], after: i >= 2 ? list[i - 2] : nil, in: playlist) }
                        .disabled(i == 0)
                    Button("Move Down") { library.move(chosen[0], after: list[i + 1], in: playlist) }
                        .disabled(i == list.count - 1)
                }
                Button("Remove from Playlist") { library.remove(chosen, from: playlist) }
            }
        }
    }
}

/// The selected songs of the list that has the focus, for the Song menu (Get Info ⌘I, Show in Finder).
struct SongActions {
    var chosen: [Track]
    var getInfo: ([Track]) -> Void
}

extension FocusedValues {
    @Entry var songs: SongActions?
}

/// The menu bar's Song menu: what the songs' right-click menu has, for the selected songs, with shortcuts.
struct SongCommands: Commands {
    @FocusedValue(\.songs) private var songs
    let library: MusicFolders

    var body: some Commands {
        CommandMenu("Song") {
            let chosen = songs?.chosen ?? []
            Button("Get Info") { songs?.getInfo(chosen) }
                .keyboardShortcut("i")
                .disabled(chosen.isEmpty)
            Button("Show in Finder") { library.reveal(chosen) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(chosen.isEmpty)
        }
    }
}

/// Songs being dragged: their ids, as text with a prefix so other text dropped on a playlist is left alone.
enum TrackDrag {
    private static let prefix = "legato-tracks:"

    /// What dragging `track` takes: the selection when it's in it (in the order shown), else just it.
    static func payload(_ track: Track, selection: Set<Track.ID>, in list: [Track]) -> String {
        let ids = selection.contains(track.id) ? list.filter { selection.contains($0.id) }.map(\.id) : [track.id]
        return prefix + ids.joined(separator: ",")
    }

    @MainActor static func tracks(_ items: [String], in library: MusicFolders) -> [Track] {
        items.filter { $0.hasPrefix(prefix) }
            .flatMap { $0.dropFirst(prefix.count).split(separator: ",") }
            .compactMap { library.byId[String($0)] }
    }
}

/// What's playing, where it is in it, and the controls. Space plays and pauses.
struct PlayerBar: View {
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Group {
                    Button("Previous", systemImage: "backward.fill") { player.previous() }
                    Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.toggle() }
                        .font(.title2)
                        .keyboardShortcut(.space, modifiers: [])
                    Button("Next", systemImage: "forward.fill") { player.next() }
                }
                .disabled(player.current == nil)

                CoverImage(path: player.current?.cover)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.displayTitle ?? "").lineLimit(1)
                    Text([player.current?.artist, player.current?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)

                Group {
                    Text(minutesAndSeconds(player.position)).monospacedDigit().foregroundStyle(.secondary)
                    Slider(value: Binding(get: { min(player.position, player.duration) }, set: { player.seek(to: $0) }),
                           in: 0...max(player.duration, 1))
                    Text(minutesAndSeconds(player.duration)).monospacedDigit().foregroundStyle(.secondary)

                    Button("Shuffle", systemImage: "shuffle") { player.shuffle.toggle() }
                        .foregroundStyle(player.shuffle ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .disabled(player.current == nil)
                Button("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat") { player.cycleRepeat() }
                    .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .disabled(player.current == nil)
                VolumeControl()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            if let problem = player.problem {
                Text(problem).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// The volume: a click on the speaker mutes (and unmutes); with the pointer over it, a slider stands up above it, so the speaker
/// itself never moves. Kept between launches.
struct VolumeControl: View {
    @Environment(Player.self) private var player
    @AppStorage("volume") private var saved = 1.0
    @State private var overIcon = false
    @State private var overSlider = false
    @State private var shown = false

    var body: some View {
        Button(player.muted ? "Unmute" : "Mute", systemImage: icon) { player.muted.toggle() }
            .frame(width: 22, height: 22)
            .contentTransition(.symbolEffect(.replace))
            .help(player.muted ? "Unmute" : "Mute")
            .onHover { overIcon = $0; hover() }
            .overlay(alignment: .bottom) {
                if shown {
                    VerticalSlider(value: Binding(get: { Double(player.volume) }, set: {
                        player.volume = Float($0)
                        player.muted = false
                        saved = $0
                    }))
                    .frame(width: 6, height: 96)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 11)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    .padding(.bottom, 6)                // (a little space, hovered too, so the pointer can move up into it)
                    .contentShape(Rectangle())
                    .onHover { overSlider = $0; hover() }
                    .offset(y: -22)
                    .transition(.opacity)
                }
            }
            .onAppear { player.volume = Float(saved) }
    }

    /// Shown while the pointer is over either; hidden a moment after it leaves both.
    private func hover() {
        if overIcon || overSlider {
            withAnimation(.easeOut(duration: 0.12)) { shown = true }
        } else {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !overIcon && !overSlider { withAnimation(.easeIn(duration: 0.12)) { shown = false } }
            }
        }
    }

    private var icon: String {
        if player.muted || player.volume == 0 { return "speaker.slash.fill" }
        return player.volume < 0.34 ? "speaker.wave.1.fill" : player.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// A slider standing up: 0 at the bottom, 1 at the top; click or drag anywhere along it.
struct VerticalSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(height: max(g.size.width, h * value))
                Circle().fill(.white).shadow(radius: 1)
                    .frame(width: 14, height: 14)
                    .offset(y: -(h - 14) * value + 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, 1 - drag.location.y / h))
            })
        }
    }
}

/// 3:07
func minutesAndSeconds(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}

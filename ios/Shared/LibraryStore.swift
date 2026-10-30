import Foundation
import Observation

/// The synced music: `Documents/Legato/manifest.json` and the files beside it. On the iPhone, Legato Desktop writes them over USB; on
/// the watch, the iPhone does. Either way this only reads them. Tracks whose file is missing (still arriving on the watch, or deleted)
/// are left out.
@MainActor
@Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var manifest: Manifest?
    /// Why the manifest couldn't be read, if it couldn't.
    private(set) var problem: String?

    let root: URL
    private var byId: [String: Track] = [:]
    private var lastLoaded: Date?

    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Legato", directoryHint: .isDirectory)
    }
    var manifestURL: URL { root.appending(path: "manifest.json") }

    init(root: URL = LibraryStore.defaultRoot) {
        self.root = root
        reload()
    }

    /// Reads the manifest again if it changed since the last time (or always, with `force`).
    func reload(force: Bool = false) {
        let modified = (try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if !force, let modified, modified == lastLoaded { return }
        lastLoaded = modified
        guard let data = try? Data(contentsOf: manifestURL) else {
            set(Manifest(), problem: nil)
            manifest = nil
            return
        }
        do {
            set(try Manifest.decode(data), problem: nil)
        } catch {
            set(Manifest(), problem: String(localized: "The synced library couldn't be read. Sync again from Legato on your computer."))
        }
    }

    private func set(_ m: Manifest, problem: String?) {
        manifest = m
        self.problem = problem
        let fm = FileManager.default
        tracks = m.tracks.filter { fm.fileExists(atPath: url(for: $0).path) }
        byId = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        playlists = m.playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        albums = Grouping.albums(tracks)
        artists = Grouping.artists(albums)
    }

    func url(for track: Track) -> URL { root.appending(path: track.file) }

    func coverURL(_ relative: String?) -> URL? {
        guard let relative else { return nil }
        let url = root.appending(path: relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The tracks of a playlist, in its order, leaving out any that aren't here.
    func tracks(of playlist: Playlist) -> [Track] { playlist.tracks.compactMap { byId[$0] } }
    func track(id: String) -> Track? { byId[id] }
    /// The playlists a track is in, by name.
    func playlists(containing track: Track) -> [Playlist] { playlists.filter { $0.tracks.contains(track.id) } }

    /// Every track by artist, then album, then album order: how the home list shows them, so an album's tracks sit together.
    var tracksInAlbumOrder: [Track] { albums.flatMap(\.tracks) }

    /// Songs, by title.
    var songsByTitle: [Track] {
        tracks.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    var totalSize: Int64 { tracks.reduce(0) { $0 + $1.size } }
}

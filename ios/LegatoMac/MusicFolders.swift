import AppKit
import Foundation
import Observation

/// The Mac's music: the folders chosen in the open panel, read for tags with TagLib, and the playlist files in them. The sandbox lets
/// Legato into a folder only once it has been picked, and only until it quits, so each one is kept as a security-scoped bookmark and
/// opened again at launch. A folder that isn't there now (a drive that isn't plugged in) keeps its bookmark, and is back when it is.
@MainActor
@Observable
final class MusicFolders: TrackFiles {
    struct Folder: Identifiable {
        var bookmark: Data
        var url: URL?           // nil: not there now
        var name: String
        /// false: Legato may only read it (a bookmark made while it could only read), so tags and playlists can't be changed there
        /// until the folder is chosen again
        var writable = true
        var id: Data { bookmark }
    }

    /// A playlist with the file it is kept in.
    struct ListFile {
        var url: URL
        var file: PlaylistFile
    }

    private(set) var folders: [Folder] = []
    private(set) var tracks: [Track] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var playlists: [Playlist] = []
    private(set) var scanning = false
    /// what went wrong last (a folder that couldn't be kept, a playlist that couldn't be saved)
    var problem: String?

    private(set) var byId: [String: Track] = [:]
    private var listFiles: [String: ListFile] = [:]     // playlist name → its file
    private var scan: Task<Void, Never>?
    private var rescanAgain = false
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let coversDir: URL
    @ObservationIgnored private lazy var watcher = FolderWatcher { [weak self] in self?.rescan() }

    private static let bookmarksKey = "musicFolders"

    init(defaults: UserDefaults = .standard, caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        self.defaults = defaults
        cacheURL = caches.appending(path: "library.json")
        coversDir = caches.appending(path: "Covers", directoryHint: .isDirectory)
        Tags.setUp()
        let saved = defaults.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        folders = saved.map(Self.open)
        if folders.map(\.bookmark) != saved { save() }      // stale bookmarks were made again
        rescan()
    }

    /// For the tests: these folders, as they are (no bookmarks, no watching).
    init(testing roots: [URL], caches: URL) {
        defaults = UserDefaults(suiteName: "legato.tests.\(UUID().uuidString)")!
        cacheURL = caches.appending(path: "library.json")
        coversDir = caches.appending(path: "Covers", directoryHint: .isDirectory)
        Tags.setUp()
        folders = roots.map { Folder(bookmark: Data($0.path.utf8), url: $0, name: $0.lastPathComponent) }
    }

    // MARK: folders

    /// A folder from the open panel (or fileImporter), which may only be read while it is "accessed". Choosing a folder Legato may
    /// only read again makes its bookmark again, now with leave to change it.
    func add(_ url: URL) {
        let same = folders.firstIndex { $0.url?.standardizedFileURL == url.standardizedFileURL }
        if let same, folders[same].writable { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
            if let same {
                folders[same].url?.stopAccessingSecurityScopedResource()
                folders[same] = Self.open(bookmark)
            } else {
                folders.append(Self.open(bookmark))
            }
            save()
            rescan()
        } catch {
            problem = String(localized: "Legato couldn't keep “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    func remove(_ folder: Folder) {
        folder.url?.stopAccessingSecurityScopedResource()
        folders.removeAll { $0.id == folder.id }
        save()
        rescan()
    }

    private static func open(_ bookmark: Data) -> Folder {
        var stale = false
        let name = URL.resourceValues(forKeys: [.nameKey], fromBookmarkData: bookmark)?.name ?? ""
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            return Folder(bookmark: bookmark, url: nil, name: name)
        }
        // stale: the folder moved or was renamed, and is still found; make the bookmark again so it keeps being found
        let fresh = stale ? (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: [.nameKey], relativeTo: nil)) : nil
        return Folder(bookmark: fresh ?? bookmark, url: url, name: url.lastPathComponent,
                      writable: FileManager.default.isWritableFile(atPath: url.path))
    }

    private func save() {
        defaults.set(folders.map(\.bookmark), forKey: Self.bookmarksKey)
    }

    // MARK: reading the folders

    /// Reads the folders again: only files that changed since the last time (by size and modification date) are read for tags.
    func rescan() {
        if scanning {
            rescanAgain = true
            return
        }
        let roots = folders.compactMap(\.url)
        watcher.watch(roots)
        scanning = true
        let known = Dictionary(tracks.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        let cacheURL = cacheURL, coversDir = coversDir
        scan = Task {
            let found = await Task.detached(priority: .utility) {
                Self.read(roots, known: known.isEmpty ? Self.loadCache(cacheURL) : known, coversDir: coversDir)
            }.value
            show(found.tracks, playlists: found.playlists)
            scanning = false
            Self.saveCache(found.tracks, to: cacheURL)
            if rescanAgain {
                rescanAgain = false
                rescan()
            }
        }
    }

    /// Waits for the scan under way, if there is one (the tests).
    func settled() async {
        while scanning { await scan?.value }
    }

    private func show(_ found: [Track], playlists files: [URL: String]) {
        tracks = found
        byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        albums = Grouping.albums(found)
        artists = Grouping.artists(albums)
        let idOfPath = Dictionary(found.map { (pathKey($0.file), $0.id) }, uniquingKeysWith: { a, _ in a })
        var lists: [String: ListFile] = [:]
        for (url, text) in files.sorted(by: { $0.key.path < $1.key.path }) {
            let file = PlaylistFile(text: text, dir: url.deletingLastPathComponent()) { idOfPath[pathKey($0)] }
            var name = url.deletingPathExtension().lastPathComponent
            if lists[name] != nil { name += " (\(url.deletingLastPathComponent().lastPathComponent))" }     // (the same name twice)
            lists[name] = ListFile(url: url, file: file)
        }
        listFiles = lists
        showPlaylists()
    }

    private func showPlaylists() {
        playlists = listFiles.map { Playlist(name: $0.key, tracks: $0.value.file.ids) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "alac", "flac", "wav", "aif", "aiff", "caf", "opus"]

    nonisolated private static func read(_ roots: [URL], known: [String: Track], coversDir: URL) -> (tracks: [Track], playlists: [URL: String]) {
        var tracks: [Track] = []
        var playlists: [URL: String] = [:]
        var covers: [String: String?] = [:]     // folder + album → its cover
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walk {
                let suffix = url.pathExtension.lowercased()
                if PlaylistFile.suffixes.contains(suffix) {
                    playlists[url] = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                    continue
                }
                guard audioExtensions.contains(suffix) else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0), modified = values?.contentModificationDate
                let path = url.standardized.path
                if var cached = known[path], cached.size == size, cached.modified == modified {
                    if let cover = cached.cover, !FileManager.default.fileExists(atPath: cover) { cached.cover = nil }
                    tracks.append(cached)
                    continue
                }
                var track = Tags.track(at: url) ?? Track(id: "", file: path)
                track.id = syncId(path)
                track.file = path
                track.size = size
                track.modified = modified
                let coverKey = url.deletingLastPathComponent().path + "\u{1f}" + track.albumKey
                if covers[coverKey] == nil { covers[coverKey] = Covers.cover(for: url, in: coversDir) }
                track.cover = covers[coverKey] ?? nil
                tracks.append(track)
            }
        }
        return (tracks, playlists)
    }

    // the tags, kept between launches, so a big library isn't read again each time
    nonisolated private static func loadCache(_ url: URL) -> [String: Track] {
        guard let data = try? Data(contentsOf: url), let tracks = try? Self.decoder.decode([Track].self, from: data) else { return [:] }
        return Dictionary(tracks.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
    }

    nonisolated private static func saveCache(_ tracks: [Track], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(tracks).write(to: url, options: .atomic)
    }

    nonisolated private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: what the window shows

    /// Songs, by title.
    var songsByTitle: [Track] {
        tracks.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    func tracks(of playlist: Playlist) -> [Track] { playlist.tracks.compactMap { byId[$0] } }

    /// An artist's songs: their albums', and the songs on others' albums that are theirs.
    func tracks(ofArtist name: String) -> [Track] {
        let own = artists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.tracks ?? []
        let ids = Set(own.map(\.id))
        let guest = albums.flatMap(\.tracks).filter { !ids.contains($0.id) && $0.artist.caseInsensitiveCompare(name) == .orderedSame }
        return own + guest
    }

    // TrackFiles: on the Mac a track's file and cover are full paths

    func url(for track: Track) -> URL { URL(filePath: track.file) }

    /// The music folder a track is in.
    func folder(of track: Track) -> Folder? {
        folders.first { folder in
            guard let path = folder.url?.standardizedFileURL.path(percentEncoded: false) else { return false }
            return track.file.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        }
    }

    func coverURL(_ path: String?) -> URL? { path.map { URL(filePath: $0) } }

    func reveal(_ tracks: [Track]) {
        NSWorkspace.shared.activateFileViewerSelecting(tracks.map(url(for:)))
    }

    // MARK: editing tags

    /// Writes the fields given into each file, then shows them. Nil, or why some couldn't be changed.
    func writeTags(_ fields: [Tags.Field: String], to edited: [Track]) -> String? {
        if let locked = edited.lazy.compactMap({ self.folder(of: $0) }).first(where: { !$0.writable }) {
            return String(localized: "Legato can only read “\(locked.name)”, as it was added before Legato could change files. Choose Allow Changes next to it in Settings (⌘,), then save again.")
        }
        var failed: [String] = []
        var why = ""
        for track in edited {
            do {
                try Tags.write(fields, to: url(for: track))
            } catch {
                failed.append((track.file as NSString).lastPathComponent)
                why = error.localizedDescription
            }
        }
        rescan()
        if failed.isEmpty { return nil }
        return failed.count == 1 ? "\(failed[0]): \(why)" : String(localized: "\(failed.count) files couldn't be changed (\(failed[0]), …): \(why)")
    }

    // MARK: playlists

    /// Makes an empty playlist in the first music folder; its name, or nil if it couldn't be made.
    @discardableResult
    func createPlaylist(_ wanted: String) -> String? {
        guard let dir = folders.compactMap(\.url).first else {
            problem = String(localized: "Choose a music folder first: playlists are kept in it.")
            return nil
        }
        let base = wanted.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "New Playlist") : wanted.trimmingCharacters(in: .whitespaces)
        var name = base, n = 2
        while listFiles[name] != nil || FileManager.default.fileExists(atPath: dir.appending(path: name + ".m3u8").path) {
            name = "\(base) \(n)"
            n += 1
        }
        let list = ListFile(url: dir.appending(path: name + ".m3u8"), file: PlaylistFile())
        guard write(list) else { return nil }
        listFiles[name] = list
        showPlaylists()
        return name
    }

    /// Adds the tracks at the end of the playlist, leaving out those already in it.
    func add(_ added: [Track], to name: String) {
        guard var list = listFiles[name] else { return }
        let dir = list.url.deletingLastPathComponent()
        var any = false
        for t in added { any = list.file.add(id: t.id, path: t.file, dir: dir) || any }
        if any { commit(list, as: name) }
    }

    func remove(_ removed: [Track], from name: String) {
        guard var list = listFiles[name] else { return }
        removed.forEach { list.file.remove(id: $0.id) }
        commit(list, as: name)
    }

    func move(_ track: Track, after: Track?, in name: String) {
        guard var list = listFiles[name], list.file.move(id: track.id, after: after?.id) else { return }
        commit(list, as: name)
    }

    @discardableResult
    func renamePlaylist(_ name: String, to wanted: String) -> Bool {
        let to = wanted.trimmingCharacters(in: .whitespaces)
        guard var list = listFiles[name], !to.isEmpty, to != name, listFiles[to] == nil else { return false }
        let target = list.url.deletingLastPathComponent().appending(path: to + "." + list.url.pathExtension)
        do {
            try FileManager.default.moveItem(at: list.url, to: target)
        } catch {
            problem = String(localized: "Couldn't rename “\(name)”: \(error.localizedDescription)")
            return false
        }
        list.url = target
        listFiles[name] = nil
        listFiles[to] = list
        showPlaylists()
        return true
    }

    /// Moves the playlist's file to the Trash.
    @discardableResult
    func deletePlaylist(_ name: String) -> Bool {
        guard let list = listFiles[name] else { return false }
        do {
            try FileManager.default.trashItem(at: list.url, resultingItemURL: nil)
        } catch {
            problem = String(localized: "Couldn't delete “\(name)”: \(error.localizedDescription)")
            return false
        }
        listFiles[name] = nil
        showPlaylists()
        return true
    }

    /// A phone's playlist changes (docs/sync.md), each made as far as it still can be. How many were made.
    @discardableResult
    func apply(_ changes: [PlaylistChange]) -> Int {
        var made = 0
        for c in changes {
            let track = c.track.flatMap { byId[$0] }
            switch c.op {
            case .create:
                if listFiles[c.playlist] == nil, let name = createPlaylist(c.playlist), name == c.playlist { made += 1 }
            case .rename:
                if let to = c.to, renamePlaylist(c.playlist, to: to) { made += 1 }
            case .delete:
                if deletePlaylist(c.playlist) { made += 1 }
            case .add:
                guard let track, var list = listFiles[c.playlist] else { continue }
                if list.file.add(id: track.id, path: track.file, dir: list.url.deletingLastPathComponent()) {
                    commit(list, as: c.playlist)
                    made += 1
                }
            case .remove:
                guard let id = c.track, var list = listFiles[c.playlist], list.file.remove(id: id) else { continue }
                commit(list, as: c.playlist)
                made += 1
            case .move:
                guard let id = c.track, var list = listFiles[c.playlist], list.file.move(id: id, after: c.after) else { continue }
                commit(list, as: c.playlist)
                made += 1
            }
        }
        return made
    }

    private func commit(_ list: ListFile, as name: String) {
        guard write(list) else { return }
        listFiles[name] = list
        showPlaylists()
    }

    private func write(_ list: ListFile) -> Bool {
        do {
            try list.file.text.write(to: list.url, atomically: true, encoding: .utf8)
            return true
        } catch {
            problem = String(localized: "Couldn't save “\(list.url.lastPathComponent)”: \(error.localizedDescription)")
            return false
        }
    }
}

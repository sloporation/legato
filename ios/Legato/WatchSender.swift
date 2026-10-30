import Foundation
import Observation
import WatchConnectivity

/// Puts music on the watch: the playlists, albums and artists chosen for it (kept between launches), sent with WatchConnectivity file
/// transfers, which carry on in the background. The watch says what it already has, so nothing is sent twice; a manifest of just the
/// chosen music goes last, and the watch deletes whatever it no longer names. (docs/sync.md)
@MainActor
@Observable
final class WatchSender: NSObject {
    enum Item: Hashable, Codable {
        case playlist(String)     // by name
        case album(String)        // by Album.id
        case artist(String)       // by name, lowercased
    }

    private(set) var isSupported = WCSession.isSupported()
    private(set) var isPaired = false
    private(set) var isAppInstalled = false
    private(set) var pendingTransfers = 0
    private(set) var problem: String?
    private(set) var selection: Set<Item> = [] { didSet { save() } }
    /// Track ids the watch says it has.
    private(set) var onWatch: Set<String> = [] { didSet { save() } }

    private let library: LibraryStore
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let defaults = UserDefaults.standard

    init(library: LibraryStore) {
        self.library = library
        super.init()
        if let data = defaults.data(forKey: "watch.selection"), let items = try? JSONDecoder().decode(Set<Item>.self, from: data) { selection = items }
        onWatch = Set(defaults.stringArray(forKey: "watch.has") ?? [])
        session?.delegate = self
        session?.activate()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(selection), forKey: "watch.selection")
        defaults.set(Array(onWatch), forKey: "watch.has")
    }

    func isSelected(_ item: Item) -> Bool { selection.contains(item) }
    func toggle(_ item: Item) {
        if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
    }

    /// The tracks the selection adds up to (each once), still in the library.
    var wantedTracks: [Track] {
        var seen = Set<String>(), out: [Track] = []
        func add(_ tracks: [Track]) { for t in tracks where seen.insert(t.id).inserted { out.append(t) } }
        for item in selection {
            switch item {
            case .playlist(let name): if let p = library.playlists.first(where: { $0.name == name }) { add(library.tracks(of: p)) }
            case .album(let key): if let a = library.albums.first(where: { $0.id == key }) { add(a.tracks) }
            case .artist(let name): if let a = library.artists.first(where: { $0.name.lowercased() == name }) { add(a.tracks) }
            }
        }
        return out
    }
    var wantedSize: Int64 { wantedTracks.reduce(0) { $0 + $1.size } }
    /// How many of the chosen tracks the watch has.
    var syncedCount: Int { wantedTracks.filter { onWatch.contains($0.id) }.count }

    /// Sends what the watch doesn't have, then the manifest.
    func send() {
        guard let session, session.activationState == .activated else {
            problem = String(localized: "The watch isn't connected.")
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            problem = String(localized: "Install Legato on your Apple Watch first (in the Watch app, under Available Apps).")
            return
        }
        problem = nil
        let tracks = wantedTracks
        let inFlight = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["file"] as? String })
        // a newer manifest replaces any still waiting to go
        for transfer in session.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == "manifest" { transfer.cancel() }

        var covers = Set<String>()
        for t in tracks {
            if !onWatch.contains(t.id) && !inFlight.contains(t.file) {
                session.transferFile(library.url(for: t), metadata: ["kind": "track", "file": t.file])
            }
            if let cover = t.cover, covers.insert(cover).inserted, !inFlight.contains(cover), let url = library.coverURL(cover) {
                session.transferFile(url, metadata: ["kind": "cover", "file": cover])
            }
        }
        // the manifest: just the chosen music, and the chosen playlists (each keeping only tracks that are going)
        let ids = Set(tracks.map(\.id))
        let playlists: [Playlist] = selection.compactMap {
            guard case .playlist(let name) = $0, var p = library.playlists.first(where: { $0.name == name }) else { return nil }
            p.tracks = p.tracks.filter(ids.contains)
            return p
        }
        let manifest = Manifest(generated: .now, source: String(localized: "Legato on iPhone"), tracks: tracks, playlists: playlists)
        do {
            let url = FileManager.default.temporaryDirectory.appending(path: "watch-manifest-\(UUID().uuidString).json")
            try manifest.encoded().write(to: url)
            session.transferFile(url, metadata: ["kind": "manifest"])
        } catch {
            problem = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        guard let session else { return }
        isPaired = session.isPaired
        isAppInstalled = session.isWatchAppInstalled
        pendingTransfers = session.outstandingFileTransfers.filter { $0.isTransferring || !$0.progress.isFinished }.count
    }
}

extension WatchSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }      // a different watch was paired
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // (manifests are cancelled on purpose when a newer one replaces them)
        let replaced = fileTransfer.file.metadata?["kind"] as? String == "manifest"
        let message = error?.localizedDescription
        Task { @MainActor in
            if let message, !replaced { self.problem = message }
            self.refresh()
        }
    }

    /// The watch says what it has: `{"have": [track ids]}`.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let have = userInfo["have"] as? [String] else { return }
        Task { @MainActor in
            self.onWatch = Set(have)
            self.refresh()
        }
    }
}

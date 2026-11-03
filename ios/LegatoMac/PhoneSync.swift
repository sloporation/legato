import Foundation
import Observation
import Tether

/// The phones that sync with this Mac over Wi-Fi, and what each is to have. Tether pairs them (both show a code, and the phone is
/// allowed here) and keeps their keys; this keeps, in the app's settings, what each phone is to have and how its last sync went.
@MainActor
@Observable
final class Phones {
    /// A phone as the Mac's pages show it: Tether's peer, with Legato's settings for it.
    struct Phone: Identifiable, Equatable {
        var id: String
        var name: String
        var allowed = false
        var refused = false
        var code: String?           // pairing now: the code both show
        var chosen = Chosen.all
        var lastSync: Date?
        var batch: String?
        var batchMade = 0
    }

    /// What Legato keeps for a phone.
    struct Settings: Codable, Equatable {
        var chosen = Chosen.all
        var lastSync: Date?
        var batch: String?          // the last lot of playlist changes it sent, and
        var batchMade = 0           // how many of those have been made here
    }

    /// What's happening with a phone now.
    struct Activity: Equatable {
        var done: Int64 = 0
        var total: Int64 = 0
        var what = ""
    }

    let host: TetherHost
    private(set) var settings: [String: Settings] = [:] { didSet { save() } }
    private(set) var activity: [String: Activity] = [:]     // phone id → its sync under way
    var serverProblem: String? { host.problem }
    private let defaults: UserDefaults
    private static let key = "phones.settings"

    init(defaults: UserDefaults = .standard, keyStore: TetherKeyStore? = nil, name: String = Host.current().localizedName ?? "Mac") {
        self.defaults = defaults
        host = TetherHost(configuration: SyncWire.configuration, name: name, keyStore: keyStore, defaults: defaults)
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([String: Settings].self, from: data) {
            settings = saved
        }
    }

    var phones: [Phone] {
        var all = host.peers.map { phone(id: $0.id, name: $0.name, allowed: $0.allowed, refused: $0.refused) }
        if let request = host.pairingRequest, !all.contains(where: { $0.id == request.id }) {
            all.append(phone(id: request.id, name: request.name, allowed: false, refused: false))
        }
        return all
    }

    /// The phone pairing now, waiting to be allowed or refused.
    var asking: Phone? { host.pairingRequest.flatMap { phone($0.id) } }

    func phone(_ id: String) -> Phone? { phones.first { $0.id == id } }

    private func phone(id: String, name: String, allowed: Bool, refused: Bool) -> Phone {
        let s = settings[id] ?? Settings()
        let request = host.pairingRequest?.id == id ? host.pairingRequest : nil
        return Phone(id: id, name: request?.name ?? name, allowed: allowed, refused: refused, code: request?.code,
                     chosen: s.chosen, lastSync: s.lastSync, batch: s.batch, batchMade: s.batchMade)
    }

    func update(_ id: String, _ change: (inout Settings) -> Void) {
        var s = settings[id] ?? Settings()
        change(&s)
        settings[id] = s
    }

    func allow(_ id: String) { host.allow(id) }
    func refuse(_ id: String) { host.refuse(id) }
    func choose(_ chosen: Chosen, for id: String) { update(id) { $0.chosen = chosen } }

    func forget(_ id: String) {
        host.forget(id)
        settings[id] = nil
    }

    fileprivate func setActivity(_ id: String, _ a: Activity?) { activity[id] = a }

    private func save() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}

/// Answers the phones Tether lets in (docs/sync.md): the manifest of what a phone is to have, and the files it asks for.
@MainActor
final class SyncServer {
    private let library: MusicFolders
    private let phones: Phones
    let source: String
    /// the port, once listening (the tests connect to it)
    var port: UInt16? { phones.host.port }

    init(library: MusicFolders, phones: Phones, source: String = "Legato on \(Host.current().localizedName ?? "Mac")") {
        self.library = library
        self.phones = phones
        self.source = source
        phones.host.onSession = { [weak self] session in await self?.serve(session) }
    }

    /// Starts listening; `advertise` false for the tests (no Bonjour). Returns once it is listening, or failed to.
    func start(advertise: Bool = true) async {
        await phones.host.start(advertise: advertise)
    }

    func stop() { phones.host.stop() }

    private func serve(_ session: TetherSession) async {
        let id = session.peerID
        var files: [String: URL] = [:]      // what this phone may ask for: its manifest's files
        defer { phones.setActivity(id, nil) }
        do {
            while true {
                let request = try await session.receive(SyncWire.Request.self)
                switch request.op {
                case .hello:
                    let (reply, offered) = await hello(request, from: id)
                    files = offered
                    try await session.send(reply)
                case .file:
                    guard let path = request.path, let url = files[path],
                          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                        try await session.send(SyncWire.Reply(ok: false, why: String(localized: "This Mac hasn't got \(request.path ?? "that").")))
                        continue
                    }
                    try await session.send(SyncWire.Reply(ok: true, size: Int64(size)))
                    var a = phones.activity[id] ?? Phones.Activity()
                    a.what = (path as NSString).lastPathComponent
                    phones.setActivity(id, a)
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty {
                        try await session.send(bytes: piece)
                        a.done += Int64(piece.count)
                        phones.setActivity(id, a)
                    }
                case .done:
                    phones.update(id) { $0.lastSync = .now }
                    try await session.send(SyncWire.Reply(ok: true))
                    return
                }
            }
        } catch {
            return      // the phone went away: it keeps what it has, and asks again next time
        }
    }

    /// A phone saying hello: its playlist changes made there, and what it is to have.
    private func hello(_ r: SyncWire.Request, from id: String) async -> (SyncWire.Reply, [String: URL]) {
        await library.settled()
        // its playlist changes, those after any of this lot already made
        if let batch = r.batch, let changes = r.changes {
            let phone = phones.phone(id)
            let skip = phone?.batch == batch ? phone?.batchMade ?? 0 : 0
            if changes.count > skip {
                library.apply(Array(changes.dropFirst(skip)))
            }
            phones.update(id) { $0.batch = batch; $0.batchMade = max(skip, changes.count) }
        }
        let (manifest, files) = Self.manifest(of: library, for: phones.phone(id)?.chosen ?? .all, source: source)
        phones.setActivity(id, Phones.Activity(total: Int64(manifest.tracks.reduce(0) { $0 + $1.size }), what: String(localized: "Starting")))
        return (SyncWire.Reply(ok: true, manifest: manifest), files)
    }

    /// What a phone is to have (as Legato Desktop works it out, qt/devices.cpp): everything, or the chosen playlists', artists' and
    /// albums' songs; with the playlists it gets (all of them with everything, else those chosen), and the files it may fetch.
    static func manifest(of library: MusicFolders, for chosen: Chosen, source: String) -> (Manifest, [String: URL]) {
        var ids = Set<String>()
        let lists = library.playlists.filter { chosen.everything || chosen.playlists.contains($0.name) }
        for list in lists { ids.formUnion(list.tracks) }
        if !chosen.everything {
            for key in chosen.albums {
                if let album = library.albums.first(where: { $0.id == key }) { ids.formUnion(album.tracks.map(\.id)) }
            }
            for name in chosen.artists { ids.formUnion(library.tracks(ofArtist: name).map(\.id)) }
        }
        var files: [String: URL] = [:]
        var tracks: [Track] = []
        for t in library.tracks where chosen.everything || ids.contains(t.id) {
            var entry = t
            entry.file = "Music/\(t.id).\((t.file as NSString).pathExtension.lowercased())"
            files[entry.file] = URL(filePath: t.file)
            entry.cover = t.cover.map { "Covers/" + ($0 as NSString).lastPathComponent }
            if let cover = t.cover, let name = entry.cover { files[name] = URL(filePath: cover) }
            tracks.append(entry)
        }
        let present = Set(tracks.map(\.id))
        let playlists = lists.map { Playlist(name: $0.name, tracks: $0.tracks.filter(present.contains)) }
        return (Manifest(generated: .now, source: source, tracks: tracks, playlists: playlists, chosen: chosen), files)
    }
}

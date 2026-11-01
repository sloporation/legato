import CryptoKit
import Foundation
import Network
import Observation

/// The phones that sync with this Mac over Wi-Fi, and what each is to have. A phone pairs the first time (both show a code, and it's
/// allowed here); after that it syncs with the key they agreed. Kept in the app's settings.
@MainActor
@Observable
final class Phones {
    struct Phone: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var key: Data?              // for TLS and the hello's proof, once allowed
        var allowed = false
        var refused = false
        var chosen = Chosen.all
        var lastSync: Date?
        var batch: String?          // the last lot of playlist changes it sent, and
        var batchMade = 0           // how many of those have been made here
        // pairing now: the key it would have, and the code both show
        var offeredKey: Data?
        var code: String?
    }

    /// What's happening with a phone now.
    struct Activity: Equatable {
        var done: Int64 = 0
        var total: Int64 = 0
        var what = ""
    }

    private(set) var phones: [Phone] = []
    private(set) var activity: [String: Activity] = [:]     // phone id → its sync under way
    var serverProblem: String?
    /// This Mac, to the phones (in the Bonjour TXT record): made once, kept.
    let macId: String
    /// Called when the keys the Mac accepts have changed (a phone allowed or forgotten).
    @ObservationIgnored var keysChanged: () -> Void = {}
    private let defaults: UserDefaults
    private static let key = "phones"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let id = defaults.string(forKey: "mac.id") {
            macId = id
        } else {
            macId = UUID().uuidString
            defaults.set(macId, forKey: "mac.id")
        }
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Phone].self, from: data) {
            phones = saved.filter { $0.key != nil || $0.refused }      // (a pairing that never finished, or a phone from before keys)
                .map { var p = $0; p.offeredKey = nil; p.code = nil; return p }
        }
    }

    /// The first phone pairing now, waiting to be allowed or refused.
    var asking: Phone? { phones.first { $0.code != nil && !$0.refused } }

    func phone(_ id: String) -> Phone? { phones.first { $0.id == id } }

    func update(_ id: String, _ change: (inout Phone) -> Void) {
        guard let i = phones.firstIndex(where: { $0.id == id }) else { return }
        change(&phones[i])
        save()
    }

    func allow(_ id: String) {
        guard let offered = phone(id)?.offeredKey else { return }
        update(id) {
            $0.key = offered
            $0.allowed = true
            $0.refused = false
            $0.offeredKey = nil
            $0.code = nil
        }
        keysChanged()
    }

    func refuse(_ id: String) {
        let had = phone(id)?.allowed == true
        update(id) {
            $0.allowed = false
            $0.refused = true
            $0.key = nil
            $0.offeredKey = nil
            $0.code = nil
        }
        if had { keysChanged() }
    }

    func choose(_ chosen: Chosen, for id: String) { update(id) { $0.chosen = chosen } }

    func forget(_ id: String) {
        phones.removeAll { $0.id == id }
        save()
        keysChanged()
    }

    /// A phone pairing: it's shown (with the code) until it's allowed or refused, or it stops pairing.
    fileprivate func pairing(_ id: String, name: String, key: Data, code: String) {
        if phone(id) == nil { phones.append(Phone(id: id, name: name)) }
        update(id) {
            $0.name = name
            $0.offeredKey = key
            $0.code = code
        }
    }

    /// It stopped pairing (went away, or paired again with another code) before being allowed or refused.
    fileprivate func stopPairing(_ id: String, code: String) {
        guard let p = phone(id), p.code == code else { return }
        if p.key == nil && !p.refused {
            phones.removeAll { $0.id == id }
            save()
        } else {
            update(id) { $0.offeredKey = nil; $0.code = nil }
        }
    }

    fileprivate func setActivity(_ id: String, _ a: Activity?) { activity[id] = a }

    private func save() {
        defaults.set(try? JSONEncoder().encode(phones.filter { $0.key != nil || $0.refused }), forKey: Self.key)
    }
}

/// Listens for phones on the local network (Bonjour, `_legato._tcp`, over TLS with each allowed phone's key) and answers them: a
/// pairing, or the manifest of what a phone is to have and the files it asks for (docs/sync.md).
@MainActor
final class SyncServer {
    private let library: MusicFolders
    private let phones: Phones
    private var listener: NWListener?
    private var advertise = true
    private var restarting = false, restartAgain = false
    private var listening: [String: Data] = [:]     // the phones whose keys the listener has: id → key
    let source: String
    /// the port, once listening (the tests connect to it)
    private(set) var port: NWEndpoint.Port?

    init(library: MusicFolders, phones: Phones, source: String = "Legato on \(Host.current().localizedName ?? "Mac")") {
        self.library = library
        self.phones = phones
        self.source = source
        phones.keysChanged = { [weak self] in Task { await self?.restart() } }
    }

    /// Starts listening; `advertise` false for the tests (no Bonjour). Returns once it is listening, or failed to.
    func start(advertise: Bool = true) async {
        self.advertise = advertise
        if !(await listen(on: nil)) {
            phones.serverProblem = phones.serverProblem ?? String(localized: "Phones can't find this Mac.")
        }
    }

    /// Listens again with the keys as they are now (TLS's keys are fixed when it starts listening), on the same port if it can.
    /// Connections already open go on as they are.
    func restart() async {
        restartAgain = true
        guard !restarting else { return }
        restarting = true
        defer { restarting = false }
        while restartAgain {
            restartAgain = false
            let port = self.port
            listener?.cancel()
            listener = nil
            if await listen(on: port) { continue }
            _ = await listen(on: nil)
        }
    }

    func stop() { listener?.cancel() }

    private func listen(on port: NWEndpoint.Port?) async -> Bool {
        let keys = phones.phones.compactMap { p in p.allowed ? p.key.map { (identity: p.id, key: $0) } : nil }
        let parameters = Wire.macParameters(keys: keys.map { ($0.identity, SymmetricKey(data: $0.key)) })
        do {
            let listener = try port.map { try NWListener(using: parameters, on: $0) } ?? NWListener(using: parameters)
            if advertise {
                listener.service = NWListener.Service(type: Wire.service, txtRecord: NWTXTRecord(["mac": phones.macId]).data)
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in await self?.serve(WireConnection(connection)) }
            }
            self.listener = listener
            return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                let resumed = Flag()
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        let ok: Bool
                        switch state {
                        case .ready:
                            self?.port = listener.port
                            self?.listening = Dictionary(keys.map { ($0.identity, $0.key) }, uniquingKeysWith: { a, _ in a })
                            self?.phones.serverProblem = nil
                            ok = true
                        case .failed(let error):
                            self?.phones.serverProblem = String(localized: "Phones can't find this Mac: \(error.localizedDescription)")
                            ok = false
                        case .cancelled:
                            ok = false
                        default:
                            return
                        }
                        if !resumed.set { resumed.set = true; c.resume(returning: ok) }
                    }
                }
                listener.start(queue: .main)
            }
        } catch {
            phones.serverProblem = String(localized: "Phones can't find this Mac: \(error.localizedDescription)")
            return false
        }
    }

    private func serve(_ wire: WireConnection) async {
        do {
            try await wire.start()
        } catch {
            return
        }
        var phoneId: String?
        var files: [String: URL] = [:]      // what this phone may ask for: its manifest's files
        defer {
            if let phoneId { phones.setActivity(phoneId, nil) }
            wire.cancel()
        }
        do {
            let challenge = Pairing.challenge()
            try await wire.send(Wire.Reply(ok: true, challenge: challenge))
            while true {
                let request = try await wire.receive(Wire.Request.self)
                switch request.op {
                case .pair:
                    try await pair(request, over: wire)
                    return
                case .hello:
                    let (reply, id, offered) = await hello(request, challenge: challenge)
                    phoneId = id
                    files = offered
                    try await wire.send(reply)
                    if !reply.ok { return }
                case .file:
                    guard let id = phoneId, let path = request.path, let url = files[path],
                          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                        try await wire.send(Wire.Reply(ok: false, why: String(localized: "This Mac hasn't got \(request.path ?? "that").")))
                        continue
                    }
                    try await wire.send(Wire.Reply(ok: true, size: Int64(size)))
                    var a = phones.activity[id] ?? Phones.Activity()
                    a.what = (path as NSString).lastPathComponent
                    phones.setActivity(id, a)
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty {
                        try await wire.send(piece)
                        a.done += Int64(piece.count)
                        phones.setActivity(id, a)
                    }

                case .done:
                    if let id = phoneId { phones.update(id) { $0.lastSync = .now } }
                    try await wire.send(Wire.Reply(ok: true))
                    return
                }
            }
        } catch {
            return      // the phone went away: it keeps what it has, and asks again next time
        }
    }

    /// A phone pairing (Pairing): its commitment, this Mac's half, its half; then both show the code, and the phone waits, connected,
    /// for it to be allowed or refused here.
    private func pair(_ first: Wire.Request, over wire: WireConnection) async throws {
        guard let id = first.phone, !id.isEmpty, let commitment = first.commitment else {
            try await wire.send(Wire.Reply(ok: false, why: String(localized: "Legato on this Mac didn't understand the phone.")))
            return
        }
        if phones.phone(id)?.refused == true {
            try await wire.send(Wire.Reply(ok: false, why: String(localized: "This Mac doesn't sync with this phone. To change that, forget it in Legato on the Mac.")))
            return
        }
        let mine = Curve25519.KeyAgreement.PrivateKey()
        let macKey = mine.publicKey.rawRepresentation
        try await wire.send(Wire.Reply(ok: true, mac: phones.macId, key: macKey))
        let reveal = try await wire.receive(Wire.Request.self)
        guard reveal.op == .pair, let phoneKey = reveal.key, Pairing.commitment(to: phoneKey) == commitment,
              let agreed = try? Pairing.agree(mine, with: phoneKey, phoneKey: phoneKey, macKey: macKey) else {
            try await wire.send(Wire.Reply(ok: false, why: String(localized: "Legato on this Mac didn't understand the phone.")))
            return
        }
        phones.pairing(id, name: first.name ?? String(localized: "iPhone"), key: agreed.key.data, code: agreed.code)
        defer { phones.stopPairing(id, code: agreed.code) }
        try await wire.send(Wire.Reply(ok: true, waiting: true))

        // the answer, while the phone stays connected (it hangs up if the page is closed)
        let gone = Flag()
        Task { @MainActor in
            _ = try? await wire.receive(exactly: 1)
            gone.set = true
        }
        let deadline = Date.now.addingTimeInterval(10 * 60)
        while !gone.set {
            guard let p = phones.phone(id), Date.now < deadline else { break }
            if p.refused {
                try await wire.send(Wire.Reply(ok: false, why: String(localized: "The Mac didn't allow this iPhone.")))
                return
            }
            if p.allowed && p.key == agreed.key.data {
                if listening[id] == p.key {     // (once listening with its key: keysChanged)
                    try await wire.send(Wire.Reply(ok: true))
                    return
                }
            } else if p.code != agreed.code {
                return      // it's pairing again on another connection
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try? await wire.send(Wire.Reply(ok: false, why: String(localized: "The Mac didn't answer.")))
    }

    /// A phone saying hello: who it is (proved with its key), its playlist changes made here, and what it is to have.
    private func hello(_ r: Wire.Request, challenge: Data) async -> (Wire.Reply, String?, [String: URL]) {
        guard let id = r.phone, let proof = r.proof, let phone = phones.phone(id), phone.allowed, let key = phone.key,
              Pairing.check(proof, challenge: challenge, phone: id, key: SymmetricKey(data: key)) else {
            return (Wire.Reply(ok: false, why: String(localized: "This Mac doesn't know this iPhone."), unpaired: true), nil, [:])
        }
        if let name = r.name, phone.name != name { phones.update(id) { $0.name = name } }

        await library.settled()
        // its playlist changes, those after any of this lot already made
        if let batch = r.batch, let changes = r.changes {
            let skip = phone.batch == batch ? phone.batchMade : 0
            if changes.count > skip {
                library.apply(Array(changes.dropFirst(skip)))
            }
            phones.update(id) { $0.batch = batch; $0.batchMade = max(skip, changes.count) }
        }
        let (manifest, files) = Self.manifest(of: library, for: phones.phone(id)?.chosen ?? .all, source: source)
        phones.setActivity(id, Phones.Activity(total: Int64(manifest.tracks.reduce(0) { $0 + $1.size }), what: String(localized: "Starting")))
        return (Wire.Reply(ok: true, manifest: manifest), id, files)
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

@MainActor private final class Flag { var set = false }

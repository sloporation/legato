import CryptoKit
import Foundation
import Network

/// The phone's side of a sync with Legato for Mac: it says hello (with its playlist changes), the Mac answers with the manifest of
/// what the phone is to have, and the phone fetches the files it hasn't got, writes the manifest last, and deletes what is no longer
/// wanted. The same Legato/ folder as a sync from Legato Desktop over USB, kept the same way (docs/sync.md).
struct SyncClient {
    /// Who the phone is, to the Mac.
    struct Identity: Codable {
        var phone: String
        var name: String
    }

    enum Outcome: Equatable {
        case synced(copied: Int, removed: Int)
    }

    enum Failure: LocalizedError {
        case refused(String), unpaired, space(Int64)
        var errorDescription: String? {
            switch self {
            case .refused(let why): why
            case .unpaired: String(localized: "This Mac doesn't know this iPhone.")
            case .space(let needed): String(localized: "Not enough space on the phone: this needs \(needed / 1_000_000) MB more")
            }
        }
    }

    let root: URL                           // Documents/Legato
    let identity: Identity
    let key: SymmetricKey                   // agreed with this Mac when the phone was paired
    var progress: @Sendable (_ done: Int64, _ total: Int64, _ what: String) -> Void = { _, _, _ in }

    private var manifestURL: URL { root.appending(path: "manifest.json") }
    private var changesURL: URL { root.appending(path: "changes.json") }
    private var applyingURL: URL { root.appending(path: "changes.applying.json") }

    /// Pairs with a Mac, over a connection made with `Wire.pairingParameters()`: `code` is called with the code to show, which the
    /// Mac shows too, and this returns once the Mac has allowed the phone, with the Mac's id and the key for syncing with it.
    static func pair(_ wire: WireConnection, as identity: Identity, code: @Sendable (String) -> Void) async throws -> (mac: String, key: SymmetricKey) {
        _ = try await wire.receive(Wire.Reply.self)        // (the challenge, which pairing has no use for)
        let mine = Curve25519.KeyAgreement.PrivateKey()
        let phoneKey = mine.publicKey.rawRepresentation
        try await wire.send(Wire.Request(op: .pair, phone: identity.phone, name: identity.name, commitment: Pairing.commitment(to: phoneKey)))
        let theirs = try await wire.receive(Wire.Reply.self)
        guard theirs.ok, let mac = theirs.mac, let macKey = theirs.key else { throw Failure.refused(theirs.why ?? String(localized: "The Mac said no.")) }
        let agreed = try Pairing.agree(mine, with: macKey, phoneKey: phoneKey, macKey: macKey)
        try await wire.send(Wire.Request(op: .pair, key: phoneKey))
        let asking = try await wire.receive(Wire.Reply.self)
        guard asking.ok else { throw Failure.refused(asking.why ?? String(localized: "The Mac said no.")) }
        code(agreed.code)
        let answer = try await wire.receive(Wire.Reply.self)
        guard answer.ok else { throw Failure.refused(answer.why ?? String(localized: "The Mac didn't allow this iPhone.")) }
        return (mac, agreed.key)
    }

    /// Syncs, over a connection made with `Wire.phoneParameters` and this phone's key.
    func sync(_ wire: WireConnection) async throws -> Outcome {
        let fm = FileManager.default
        for dir in ["Music", "Covers"] { try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true) }
        let old = (try? Data(contentsOf: manifestURL)).flatMap { try? Manifest.decode($0) }
        let pending = try takeChanges()

        let challenge = try await wire.receive(Wire.Reply.self).challenge ?? Data()
        try await wire.send(Wire.Request(op: .hello, phone: identity.phone, name: identity.name,
                                         proof: Pairing.proof(challenge: challenge, phone: identity.phone, key: key),
                                         chosen: old?.chosen, batch: pending.batch, changes: pending.changes))
        let hello = try await wire.receive(Wire.Reply.self)
        if hello.unpaired == true { throw Failure.unpaired }
        guard hello.ok, let manifest = hello.manifest else { throw Failure.refused(hello.why ?? String(localized: "The Mac said no.")) }

        let have = Set((try? fm.contentsOfDirectory(atPath: root.appending(path: "Music").path)) ?? [])
        let plan = Self.plan(old: old, new: manifest, have: have)
        let freed = plan.remove.reduce(Int64(0)) { sum, name in
            sum + Int64((try? root.appending(path: "Music/" + name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        if let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,
           plan.bytes > free + freed - 50_000_000 {
            throw Failure.space(plan.bytes - free - freed + 50_000_000)
        }

        // the files that are new or changed, each as .part, renamed into place once it is all there
        var done: Int64 = 0
        for track in plan.fetch {
            let start = done
            try await fetch(track.file, over: wire) { got in progress(start + got, plan.bytes, track.displayTitle) }
            done = start + track.size
        }
        let haveCovers = Set((try? fm.contentsOfDirectory(atPath: root.appending(path: "Covers").path)) ?? [])
        let covers = Set(manifest.tracks.compactMap(\.cover))
        for cover in covers.sorted() where !haveCovers.contains((cover as NSString).lastPathComponent) {
            progress(plan.bytes, plan.bytes, String(localized: "Covers"))
            try? await fetch(cover, over: wire)       // no cover is better than no sync
        }

        // the manifest, last; then what it no longer names
        try manifest.encoded().write(to: manifestURL, options: .atomic)
        if pending.batch != nil { try? fm.removeItem(at: applyingURL) }
        for name in plan.remove { try? fm.removeItem(at: root.appending(path: "Music/" + name)) }
        let wantedCovers = Set(covers.map { ($0 as NSString).lastPathComponent })
        for name in haveCovers where !wantedCovers.contains(name) { try? fm.removeItem(at: root.appending(path: "Covers/" + name)) }

        try await wire.send(Wire.Request(op: .done, copied: plan.fetch.count))
        _ = try? await wire.receive(Wire.Reply.self)     // (the Mac has noted it)
        return .synced(copied: plan.fetch.count, removed: plan.remove.filter { !$0.hasSuffix(".part") }.count)
    }

    private func fetch(_ path: String, over wire: WireConnection, progress: (Int64) -> Void = { _ in }) async throws {
        try await wire.send(Wire.Request(op: .file, path: path))
        let reply = try await wire.receive(Wire.Reply.self)
        guard reply.ok, let size = reply.size else { throw Failure.refused(reply.why ?? String(localized: "The Mac couldn't send \(path).")) }
        let target = root.appending(path: path)
        let part = root.appending(path: path + ".part")
        try await wire.receiveFile(size: size, to: part, progress: progress)
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: part, to: target)
    }

    /// The playlist changes made here, to send: changes.json goes onto the end of changes.applying.json (after any left from a sync
    /// that didn't finish), which keeps its batch name until a sync finishes. The Mac remembers how many of a batch it has made, and
    /// makes only the ones after those.
    private func takeChanges() throws -> (batch: String?, changes: [PlaylistChange]?) {
        let fm = FileManager.default
        let fresh = ChangeLog.read(changesURL)
        var applying = Self.readLog(applyingURL)
        if !fm.fileExists(atPath: applyingURL.path) && fresh.isEmpty { return (nil, nil) }
        if applying.batch == nil || applying.applied != nil {
            // (one Legato Desktop left: it has made `applied` of them; a new batch for the rest)
            applying = ChangeLog(changes: Array(applying.changes.dropFirst(applying.applied ?? 0)), batch: UUID().uuidString)
        }
        applying.changes += fresh
        try applying.write(applyingURL)
        if fm.fileExists(atPath: changesURL.path) { try fm.removeItem(at: changesURL) }
        return (applying.batch, applying.changes)
    }

    private static func readLog(_ url: URL) -> ChangeLog {
        guard let data = try? Data(contentsOf: url) else { return ChangeLog() }
        return (try? Wire.decoder.decode(ChangeLog.self, from: data)) ?? ChangeLog()
    }

    /// What to fetch and what to delete: a track is kept when its file is there and the old manifest has it the same (file, size and
    /// modification date); anything in Music/ the new manifest doesn't name goes.
    static func plan(old: Manifest?, new: Manifest, have: Set<String>) -> (fetch: [Track], remove: [String], bytes: Int64) {
        let before = Dictionary((old?.tracks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var fetch: [Track] = []
        for t in new.tracks {
            let name = (t.file as NSString).lastPathComponent
            if let b = before[t.id], have.contains(name), b.file == t.file, b.size == t.size, b.modified == t.modified { continue }
            fetch.append(t)
        }
        let wanted = Set(new.tracks.map { ($0.file as NSString).lastPathComponent })
        let remove = have.filter { !wanted.contains($0) }.sorted()
        return (fetch, remove, fetch.reduce(0) { $0 + $1.size })
    }
}

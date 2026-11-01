import CryptoKit
import Network
import XCTest

/// A sync from end to end: the Mac's server on a local port, a phone's SyncClient connecting to it, both in this process.
@MainActor
final class SyncTests: XCTestCase {
    private var root: URL!
    private var music: URL!
    private var phoneRoot: URL!
    private var library: MusicFolders!
    private var phones: Phones!
    private var server: SyncServer!
    private let identity = SyncClient.Identity(phone: "phone-1", name: "Test iPhone")
    private var key: SymmetricKey?          // phone-1's, once paired

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "legato-sync-\(UUID().uuidString)")
        music = root.appending(path: "Music")
        phoneRoot = root.appending(path: "Phone/Legato")
        let fm = FileManager.default
        try fm.createDirectory(at: music.appending(path: "Album"), withIntermediateDirectories: true)
        try fm.createDirectory(at: phoneRoot, withIntermediateDirectories: true)
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        Tags.setUp()
        for (n, suffix) in ["mp3", "m4a", "flac"].enumerated() {
            let url = music.appending(path: "Album/\(n + 1) tone.\(suffix)")
            try fm.copyItem(at: fixtures.appending(path: "tone.\(suffix)"), to: url)
            try Tags.write([.title: "Tone \(suffix)", .artist: "Tester", .album: "Tones", .trackNumber: "\(n + 1)"], to: url)
        }
        try "#EXTM3U\nAlbum/1 tone.mp3\nAlbum/3 tone.flac\n".write(to: music.appending(path: "Rainy Day.m3u8"), atomically: true, encoding: .utf8)

        library = MusicFolders(testing: [music], caches: root.appending(path: "Caches"))
        library.rescan()
        await library.settled()
        phones = Phones(defaults: UserDefaults(suiteName: "legato.tests.\(UUID().uuidString)")!)
        server = SyncServer(library: library, phones: phones, source: "Legato on Test Mac")
        await server.start(advertise: false)
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// Pairs a phone, allowing it here (or not) once it's asking; returns the Mac's id and the key, and the codes each side showed.
    private func pair(_ identity: SyncClient.Identity? = nil, allow: Bool = true) async throws -> (mac: String, key: SymmetricKey, codes: [String]) {
        let identity = identity ?? self.identity
        let port = try XCTUnwrap(server.port)
        let wire = WireConnection(NWConnection(host: "127.0.0.1", port: port, using: Wire.pairingParameters()))
        defer { wire.cancel() }
        try await wire.start()
        let shown = Shown()
        let pairing = Task { try await SyncClient.pair(wire, as: identity) { shown.code = $0 } }
        for _ in 0..<200 where phones.asking?.id != identity.phone || shown.code == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let macCode = try XCTUnwrap(phones.asking?.code)
        if allow { phones.allow(identity.phone) } else { phones.refuse(identity.phone) }
        let paired = try await pairing.value
        return (paired.mac, paired.key, [try XCTUnwrap(shown.code), macCode])
    }

    private func sync(_ identity: SyncClient.Identity? = nil, key: SymmetricKey? = nil, tlsAs tlsIdentity: String? = nil) async throws -> SyncClient.Outcome {
        let identity = identity ?? self.identity
        if self.key == nil && key == nil { self.key = try await pair().key }
        let key = try XCTUnwrap(key ?? self.key)
        let port = try XCTUnwrap(server.port)
        let wire = WireConnection(NWConnection(host: "127.0.0.1", port: port, using: Wire.phoneParameters(identity: tlsIdentity ?? identity.phone, key: key)))
        defer { wire.cancel() }
        try await wire.start()
        return try await SyncClient(root: phoneRoot, identity: identity, key: key).sync(wire)
    }

    private func phoneManifest() throws -> Manifest {
        try Manifest.decode(Data(contentsOf: phoneRoot.appending(path: "manifest.json")))
    }

    func testLibraryReadsTagsAndPlaylists() {
        XCTAssertEqual(library.tracks.count, 3)
        XCTAssertEqual(library.albums.map(\.title), ["Tones"])
        XCTAssertEqual(library.albums.first?.tracks.map(\.trackNumber), [1, 2, 3])
        XCTAssertEqual(library.playlists.map(\.name), ["Rainy Day"])
        XCTAssertEqual(library.playlists.first?.tracks.count, 2)
    }

    func testAPhonePairsThenSyncs() async throws {
        let paired = try await pair()
        XCTAssertEqual(paired.codes[0], paired.codes[1])
        XCTAssertEqual(paired.codes[0].count, 7)
        XCTAssertEqual(paired.mac, phones.macId)
        XCTAssertNil(phones.asking)
        XCTAssertEqual(phones.phone("phone-1")?.key, paired.key.data)
        key = paired.key

        let first = try await sync()
        XCTAssertEqual(first, .synced(copied: 3, removed: 0))
        XCTAssertNotNil(phones.phone("phone-1")?.lastSync)
        let manifest = try phoneManifest()
        XCTAssertEqual(manifest.source, "Legato on Test Mac")
        XCTAssertEqual(manifest.tracks.count, 3)
        XCTAssertEqual(manifest.playlists.map(\.name), ["Rainy Day"])
        for t in manifest.tracks {
            let local = try XCTUnwrap(library.tracks.first { $0.id == t.id })
            XCTAssertEqual(try Data(contentsOf: phoneRoot.appending(path: t.file)), try Data(contentsOf: URL(filePath: local.file)))
            XCTAssertTrue(t.file.hasPrefix("Music/\(t.id)."))
        }

        // nothing changed: nothing copied
        let again = try await sync()
        XCTAssertEqual(again, .synced(copied: 0, removed: 0))
    }

    func testARefusedPhoneCantPairAgain() async throws {
        do {
            _ = try await pair(allow: false)
            XCTFail("paired without being allowed")
        } catch {}
        XCTAssertEqual(phones.phone("phone-1")?.refused, true)
        XCTAssertNil(phones.phone("phone-1")?.key)
        let port = try XCTUnwrap(server.port)
        let wire = WireConnection(NWConnection(host: "127.0.0.1", port: port, using: Wire.pairingParameters()))
        defer { wire.cancel() }
        try await wire.start()
        do {
            _ = try await SyncClient.pair(wire, as: identity) { _ in }
            XCTFail("a refused phone paired")
        } catch SyncClient.Failure.refused {}
    }

    func testAWrongKeyCantConnect() async throws {
        key = try await pair().key
        do {
            _ = try await sync(key: SymmetricKey(size: .bits256))
            XCTFail("synced with the wrong key")
        } catch {}
    }

    /// One allowed phone can't sync as another: its hello's proof is made with its own key.
    func testAPhoneCantSyncAsAnother() async throws {
        key = try await pair().key
        let other = SyncClient.Identity(phone: "phone-2", name: "Other iPhone")
        let otherKey = try await pair(other).key
        do {
            _ = try await sync(identity, key: otherKey, tlsAs: other.phone)
            XCTFail("synced as another phone")
        } catch SyncClient.Failure.unpaired {}
        let fine = try await sync(other, key: otherKey)
        XCTAssertEqual(fine, .synced(copied: 3, removed: 0))
    }

    func testAForgottenPhoneMustPairAgain() async throws {
        _ = try await sync()
        phones.forget("phone-1")
        await server.restart()
        do {
            _ = try await sync()
            XCTFail("synced after being forgotten")
        } catch {}
        key = try await pair().key
        let again = try await sync()
        XCTAssertEqual(again, .synced(copied: 0, removed: 0))
    }

    func testChoosingLessRemovesTheRest() async throws {
        _ = try await sync()
        phones.choose(Chosen(playlists: ["Rainy Day"]), for: "phone-1")
        let outcome = try await sync()
        XCTAssertEqual(outcome, .synced(copied: 0, removed: 1))
        XCTAssertEqual(try phoneManifest().tracks.count, 2)
        XCTAssertEqual(try phoneManifest().chosen, Chosen(playlists: ["Rainy Day"]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: phoneRoot.appending(path: "Music").path).count, 2)
    }

    /// The phone's playlist changes reach the Mac's playlist files, once, and come back in the manifest.
    func testPlaylistChangesGoToTheMac() async throws {
        _ = try await sync()
        let tracks = try phoneManifest().tracks
        let changes = [
            PlaylistChange(op: .create, playlist: "Gym"),
            PlaylistChange(op: .add, playlist: "Gym", track: tracks[1].id),
            PlaylistChange(op: .add, playlist: "Gym", track: tracks[0].id),
            PlaylistChange(op: .rename, playlist: "Rainy Day", to: "Sunny Day"),
        ]
        try ChangeLog(changes: changes).write(phoneRoot.appending(path: "changes.json"))
        _ = try await sync()

        XCTAssertEqual(library.playlists.map(\.name), ["Gym", "Sunny Day"])
        XCTAssertEqual(library.playlists.first?.tracks, [tracks[1].id, tracks[0].id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.appending(path: "Gym.m3u8").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.appending(path: "Sunny Day.m3u8").path))
        XCTAssertEqual(try phoneManifest().playlists.map(\.name), ["Gym", "Sunny Day"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: phoneRoot.appending(path: "changes.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: phoneRoot.appending(path: "changes.applying.json").path))
    }

    /// A sync that didn't finish leaves changes.applying.json; sent again with more after it, only the new ones are made.
    func testABatchIsMadeOnce() async throws {
        _ = try await sync()
        let id = try phoneManifest().tracks[1].id
        var log = ChangeLog(changes: [PlaylistChange(op: .add, playlist: "Rainy Day", track: id)], batch: "lot-1")
        phones.update("phone-1") { $0.batch = "lot-1"; $0.batchMade = 1 }     // (made already, then the connection dropped)
        log.changes.append(PlaylistChange(op: .move, playlist: "Rainy Day", track: id, after: nil))
        try log.write(phoneRoot.appending(path: "changes.applying.json"))
        let before = library.playlists[0].tracks
        _ = try await sync()
        XCTAssertEqual(library.playlists[0].tracks, before.contains(id) ? [id] + before.filter { $0 != id } : before)
        XCTAssertEqual(phones.phone("phone-1")?.batchMade, 2)
    }
}

private final class Shown: @unchecked Sendable {
    var code: String?
}

import Network
import Tether
import XCTest

/// A sync from end to end: the Mac's server on a local port, a phone's TetherClient and SyncClient connecting to it, both in this
/// process. (Pairing itself, refusing and keys are Tether's, and tested there.)
@MainActor
final class SyncTests: XCTestCase {
    private var root: URL!
    private var music: URL!
    private var phoneRoot: URL!
    private var library: MusicFolders!
    private var phones: Phones!
    private var server: SyncServer!
    private var client: TetherClient!
    private var phoneId: String { client.clientID }

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
        phones = Phones(defaults: Self.freshDefaults(), keyStore: MemoryKeyStore(), name: "Test Mac")
        server = SyncServer(library: library, phones: phones, source: "Legato on Test Mac")
        await server.start(advertise: false)
        client = TetherClient(configuration: SyncWire.configuration, name: "Test iPhone", keyStore: MemoryKeyStore(), defaults: Self.freshDefaults())
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "legato.tests.\(UUID().uuidString)")!
    }

    private var endpoint: NWEndpoint {
        get throws { .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: try XCTUnwrap(server.port))!) }
    }

    /// Pairs the phone, allowing it here once it's asking; returns the codes each side showed.
    @discardableResult
    private func pair() async throws -> [String] {
        let shown = Shown()
        let endpoint = try endpoint
        let pairing = Task { try await client.pair(endpoint: endpoint) { shown.code = $0 } }
        for _ in 0..<200 where phones.asking?.id != phoneId || shown.code == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let macCode = try XCTUnwrap(phones.asking?.code)
        phones.allow(phoneId)
        try await pairing.value
        return [try XCTUnwrap(shown.code), macCode]
    }

    private func sync() async throws -> SyncClient.Outcome {
        if !client.isPaired(phones.host.hostID) { try await pair() }
        let session = try await client.connect(endpoint: try endpoint, hostID: phones.host.hostID)
        defer { session.close() }
        return try await SyncClient(root: phoneRoot).sync(session)
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
        let codes = try await pair()
        XCTAssertEqual(codes[0], codes[1])
        XCTAssertEqual(codes[0].count, 7)
        XCTAssertNil(phones.asking)
        XCTAssertEqual(phones.phone(phoneId)?.allowed, true)
        XCTAssertEqual(phones.phone(phoneId)?.name, "Test iPhone")

        let first = try await sync()
        XCTAssertEqual(first, .synced(copied: 3, removed: 0))
        XCTAssertNotNil(phones.phone(phoneId)?.lastSync)
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

    func testAForgottenPhoneMustPairAgain() async throws {
        _ = try await sync()
        phones.forget(phoneId)
        XCTAssertNil(phones.phone(phoneId))
        try await Task.sleep(for: .milliseconds(300))      // (listening again without its key)
        do {
            _ = try await client.connect(endpoint: try endpoint, hostID: phones.host.hostID)
            XCTFail("connected after being forgotten")
        } catch TetherError.unpaired {}
        let again = try await sync()        // pairs again first
        XCTAssertEqual(again, .synced(copied: 0, removed: 0))
    }

    func testChoosingLessRemovesTheRest() async throws {
        _ = try await sync()
        phones.choose(Chosen(playlists: ["Rainy Day"]), for: phoneId)
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
        phones.update(phoneId) { $0.batch = "lot-1"; $0.batchMade = 1 }     // (made already, then the connection dropped)
        log.changes.append(PlaylistChange(op: .move, playlist: "Rainy Day", track: id, after: nil))
        try log.write(phoneRoot.appending(path: "changes.applying.json"))
        let before = library.playlists[0].tracks
        _ = try await sync()
        XCTAssertEqual(library.playlists[0].tracks, before.contains(id) ? [id] + before.filter { $0 != id } : before)
        XCTAssertEqual(phones.phone(phoneId)?.batchMade, 2)
    }
}

private final class Shown: @unchecked Sendable {
    var code: String?
}

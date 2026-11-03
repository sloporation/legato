import XCTest
@testable import Legato

/// The watch as the iPhone's remote: what the two say to each other comes through intact, and the iPhone makes the same lists the
/// watch shows from its copy of the library.
@MainActor
final class RemoteTests: XCTestCase {
    private func tracks(_ n: Int) -> [Track] {
        (0..<n).map { i in
            Track(id: "track-\(i)", file: "Music/track-\(i).flac", title: "Song \(i)", artist: "Artist \(i % 7)", album: "Album \(i % 40)",
                  year: 2000 + i % 20, trackNumber: i % 12 + 1, duration: 200, size: 5_000_000, modified: .now, cover: "Covers/\(i % 40).jpg")
        }
    }

    func testSourcesGoThroughAMessage() {
        for source in [Remote.Source.playlist("Rainy Day"), .album("a\u{1f}b"), .artist("Avenged Sevenfold"), .songs] {
            XCTAssertEqual(Remote.Source(message: source.message), source)
        }
        XCTAssertNil(Remote.Source(message: ["source": "playlist"]))
    }

    func testStateGoesThroughAMessage() {
        let state = Remote.State(track: tracks(1)[0], playing: true, position: 12.5, duration: 200, at: Date(timeIntervalSince1970: 1000),
                                 problem: "No")
        let back = Remote.State(message: state.message)
        XCTAssertEqual(back.track?.id, "track-0")
        XCTAssertEqual(back.track?.title, "Song 0")
        XCTAssertTrue(back.playing)
        XCTAssertEqual(back.position, 12.5)
        XCTAssertEqual(back.at, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(back.problem, "No")
        XCTAssertNil(Remote.State(message: Remote.State().message).track)
    }

    /// A big library goes in pieces that each fit in a message (65 KB), and comes back whole, without covers.
    func testTheCatalogGoesInPieces() throws {
        let all = tracks(5000)
        let catalog = try Remote.Catalog(tracks: all, playlists: [Playlist(name: "Gym", tracks: ["track-3", "track-1"])])
        XCTAssertGreaterThan(catalog.pieces, 1)
        var data = Data()
        for i in 0..<catalog.pieces {
            let piece = try XCTUnwrap(catalog.piece(i))
            XCTAssertLessThanOrEqual(piece.count, 60_000)
            data.append(piece)
        }
        XCTAssertNil(catalog.piece(catalog.pieces))
        let manifest = try Remote.Catalog.manifest(from: data)
        XCTAssertEqual(manifest.tracks.map(\.id), all.map(\.id))
        XCTAssertNil(manifest.tracks[0].cover)
        XCTAssertEqual(manifest.playlists.first?.tracks, ["track-3", "track-1"])
        XCTAssertEqual(try Remote.Catalog(tracks: all, playlists: manifest.playlists).version, catalog.version)
        XCTAssertNotEqual(try Remote.Catalog(tracks: Array(all.dropLast()), playlists: manifest.playlists).version, catalog.version)
    }

    /// The watch's copy (no files) and the iPhone's library (with them) make the same list from a source.
    func testBothSidesMakeTheSameLists() throws {
        let fm = FileManager.default
        let phoneRoot = fm.temporaryDirectory.appending(path: "legato-remote-\(UUID().uuidString)")
        let watchRoot = fm.temporaryDirectory.appending(path: "legato-remote-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: phoneRoot); try? fm.removeItem(at: watchRoot) }
        let all = tracks(200)
        try fm.createDirectory(at: phoneRoot.appending(path: "Music"), withIntermediateDirectories: true)
        for t in all { fm.createFile(atPath: phoneRoot.appending(path: t.file).path, contents: Data()) }
        try Manifest(tracks: all, playlists: [Playlist(name: "Gym", tracks: ["track-9", "track-2"])]).encoded()
            .write(to: phoneRoot.appending(path: "manifest.json"))
        let phone = LibraryStore(root: phoneRoot)

        let catalog = try Remote.Catalog(tracks: phone.tracks, playlists: phone.playlists)
        try fm.createDirectory(at: watchRoot, withIntermediateDirectories: true)
        try Remote.Catalog.manifest(from: catalog.data).encoded().write(to: watchRoot.appending(path: "manifest.json"))
        let watch = LibraryStore(root: watchRoot, requireFiles: false)

        XCTAssertEqual(watch.tracks.count, 200)
        let album = try XCTUnwrap(watch.albums.dropFirst(3).first)
        let artist = try XCTUnwrap(watch.artists.last)
        for source in [Remote.Source.playlist("Gym"), .album(album.id), .artist(artist.name), .songs] {
            XCTAssertEqual(watch.tracks(from: source).map(\.id), phone.tracks(from: source).map(\.id))
            XCTAssertFalse(phone.tracks(from: source).isEmpty)
        }
    }
}

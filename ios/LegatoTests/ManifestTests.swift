import XCTest
@testable import Legato

final class ManifestTests: XCTestCase {
    func testReadsTheFormatInSyncMd() throws {
        let json = """
        {
          "version": 1,
          "generated": "2026-10-30T12:00:00Z",
          "source": "Legato on a Mac",
          "tracks": [
            { "id": "a", "file": "Music/a.opus", "title": "Critical Acclaim", "artist": "Avenged Sevenfold",
              "album": "Avenged Sevenfold", "albumArtist": "Avenged Sevenfold", "genre": "Rock", "year": 2007,
              "trackNumber": 1, "discNumber": 1, "duration": 315.18, "size": 5223493,
              "modified": "2026-10-30T10:19:00Z", "cover": "Covers/x.jpg", "somethingNew": true }
          ],
          "playlists": [ { "name": "Rainy Day", "tracks": ["a"] } ]
        }
        """
        let m = try Manifest.decode(Data(json.utf8))
        XCTAssertEqual(m.tracks.count, 1)
        XCTAssertEqual(m.tracks[0].title, "Critical Acclaim")
        XCTAssertEqual(m.tracks[0].duration, 315.18)
        XCTAssertEqual(m.tracks[0].cover, "Covers/x.jpg")
        XCTAssertNotNil(m.tracks[0].modified)
        XCTAssertEqual(m.playlists.first?.tracks, ["a"])
    }

    func testMissingFieldsTakeDefaults() throws {
        let m = try Manifest.decode(Data(#"{ "tracks": [ { "id": "a", "file": "Music/untagged recording.wav" } ] }"#.utf8))
        XCTAssertEqual(m.version, 1)
        XCTAssertEqual(m.tracks[0].title, "")
        XCTAssertEqual(m.tracks[0].displayTitle, "untagged recording.wav")
        XCTAssertTrue(m.playlists.isEmpty)
    }

    func testRoundTrips() throws {
        let m = Manifest(generated: Date(timeIntervalSince1970: 1_800_000_000), source: "x",
                         tracks: [Track(id: "a", file: "Music/a.mp3", title: "A", year: 2001)],
                         playlists: [Playlist(name: "P", tracks: ["a"])])
        XCTAssertEqual(try Manifest.decode(m.encoded()), m)
    }

    /// The same grouping as the desktop: album artist (else artist) and album title, ignoring case; album order by disc, track, title.
    func testGroupsAlbumsLikeTheDesktop() {
        let tracks = [
            Track(id: "1", file: "Music/1.mp3", title: "B side", artist: "Ada Lune", album: "Harbour", trackNumber: 2),
            Track(id: "2", file: "Music/2.mp3", title: "Opener", artist: "Ada Lune feat. Ö", album: "HARBOUR", albumArtist: "ada lune", trackNumber: 1),
            Track(id: "3", file: "Music/3.mp3", title: "Unnumbered", artist: "Ada Lune", album: "Harbour"),
            Track(id: "4", file: "Music/4.mp3", title: "Disc two", artist: "Ada Lune", album: "Harbour", trackNumber: 1, discNumber: 2),
            Track(id: "5", file: "Music/5.mp3", title: "Other", artist: "Northern Static", album: "Glass Weather"),
        ]
        let albums = Grouping.albums(tracks)
        XCTAssertEqual(albums.map(\.title), ["Harbour", "Glass Weather"])     // by artist: Ada Lune, then Northern Static
        XCTAssertEqual(albums[0].tracks.map(\.title), ["Opener", "B side", "Unnumbered", "Disc two"])
        let artists = Grouping.artists(albums)
        XCTAssertEqual(artists.map(\.name), ["Ada Lune", "Northern Static"])
        XCTAssertEqual(artists[0].tracks.count, 4)
    }

    @MainActor
    func testLibraryLeavesOutTracksWhoseFileIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "legato-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Music"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: root.appending(path: "Music/here.mp3"))
        let m = Manifest(tracks: [Track(id: "here", file: "Music/here.mp3", title: "Here"),
                                  Track(id: "gone", file: "Music/gone.mp3", title: "Gone")],
                         playlists: [Playlist(name: "P", tracks: ["gone", "here"])])
        try m.encoded().write(to: root.appending(path: "manifest.json"))
        let library = LibraryStore(root: root)
        XCTAssertEqual(library.tracks.map(\.id), ["here"])
        XCTAssertEqual(library.tracks(of: library.playlists[0]).map(\.id), ["here"])
    }
}

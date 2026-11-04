import XCTest

/// Tags read and written with TagLib, in each format the Mac plays.
final class TagsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        Tags.setUp()
        dir = FileManager.default.temporaryDirectory.appending(path: "legato-tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func copy(_ suffix: String) throws -> URL {
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        let url = dir.appending(path: "tone.\(suffix)")
        try FileManager.default.copyItem(at: fixtures.appending(path: "tone.\(suffix)"), to: url)
        return url
    }

    func testWriteThenReadEachFormat() throws {
        for suffix in ["mp3", "m4a", "flac", "opus", "wav"] {
            let url = try copy(suffix)
            try Tags.write([.title: "Tone \(suffix)", .artist: "Test Artist", .album: "Test Album", .albumArtist: "Various",
                            .genre: "Test", .date: "2021-05-01", .trackNumber: "3", .trackTotal: "9", .discNumber: "1"], to: url)
            let t = try XCTUnwrap(Tags.track(at: url), suffix)
            XCTAssertEqual(t.title, "Tone \(suffix)", suffix)
            XCTAssertEqual(t.artist, "Test Artist", suffix)
            XCTAssertEqual(t.album, "Test Album", suffix)
            XCTAssertEqual(t.albumArtist, "Various", suffix)
            XCTAssertEqual(t.year, 2021, suffix)
            XCTAssertEqual(t.trackNumber, 3, suffix)
            XCTAssertEqual(t.discNumber, 1, suffix)
            XCTAssertEqual(t.duration, 2, accuracy: 1, suffix)
            let edit = try XCTUnwrap(Tags.forEditing(url))
            XCTAssertEqual(edit.tags[.trackNumber], "3", suffix)
            XCTAssertEqual(edit.tags[.trackTotal], "9", suffix)
        }
    }

    func testOnlyTheFieldsGivenChange() throws {
        let url = try copy("flac")
        try Tags.write([.title: "One", .artist: "Someone"], to: url)
        try Tags.write([.title: "Two"], to: url)
        let t = try XCTUnwrap(Tags.track(at: url))
        XCTAssertEqual(t.title, "Two")
        XCTAssertEqual(t.artist, "Someone")
        try Tags.write([.artist: ""], to: url)     // empty: the tag goes
        XCTAssertEqual(Tags.track(at: url)?.artist, "")
    }

    /// A total set on a track with no number: its own tag where the format has one, "0/total" in MP4.
    func testLoneTotal() throws {
        for suffix in ["flac", "m4a"] {
            let url = try copy(suffix)
            try Tags.write([.trackNumber: "", .trackTotal: "12"], to: url)
            let edit = try XCTUnwrap(Tags.forEditing(url))
            XCTAssertEqual(edit.tags[.trackNumber], "", suffix)
            XCTAssertEqual(edit.tags[.trackTotal], "12", suffix)
        }
    }

    func testCoverIsASquareJPEG() throws {
        let png = try XCTUnwrap(NSImage(size: NSSize(width: 300, height: 200), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }.tiffRepresentation)
        let jpeg = try XCTUnwrap(Covers.square(png))
        let image = try XCTUnwrap(NSImage(data: jpeg)?.representations.first)
        XCTAssertEqual(image.pixelsWide, 600)
        XCTAssertEqual(image.pixelsHigh, 600)
    }

    func testIdsAreLegatoDesktops() {
        // composed and decomposed é are the same file, and the same id
        XCTAssertEqual(syncId("/Music/Caf\u{e9}.mp3"), syncId("/Music/Cafe\u{301}.mp3"))
        XCTAssertEqual(syncId("/Music/a/../b.mp3"), syncId("/Music/b.mp3"))
        XCTAssertEqual(syncId("/Music/b.mp3").count, 16)
    }
}

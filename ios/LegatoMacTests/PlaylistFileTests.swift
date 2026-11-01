import XCTest

final class PlaylistFileTests: XCTestCase {
    private let dir = URL(filePath: "/Music/Lists")
    private let ids = ["/Music/Lists/a.mp3": "A", "/Music/b.flac": "B", "/Music/Lists/sub/c.m4a": "C"]

    private func parse(_ text: String) -> PlaylistFile {
        PlaylistFile(text: text, dir: dir) { ids[$0] }
    }

    func testReadsRelativeFullAndURLLines() {
        let p = parse("#EXTM3U\n#EXTINF:12,A\na.mp3\n/Music/b.flac\nfile:///Music/Lists/sub/c.m4a\nmissing.mp3\n")
        XCTAssertEqual(p.ids, ["A", "B", "C"])
        XCTAssertEqual(p.entries.count, 4)
        XCTAssertEqual(p.entries[0].comments, ["#EXTINF:12,A"])
    }

    func testEditsKeepOtherLines() {
        var p = parse("#EXTM3U\n#PLAYLIST:Mine\n#EXTINF:12,A\na.mp3\nmissing.mp3\n/Music/b.flac\n")
        XCTAssertTrue(p.add(id: "C", path: "/Music/Lists/sub/c.m4a", dir: dir))
        XCTAssertFalse(p.add(id: "A", path: "/Music/Lists/a.mp3", dir: dir))     // already in
        XCTAssertTrue(p.move(id: "C", after: nil))
        XCTAssertTrue(p.move(id: "A", after: "B"))
        XCTAssertTrue(p.remove(id: "B"))
        XCTAssertEqual(p.ids, ["C", "A"])
        XCTAssertEqual(p.text, "#EXTM3U\n#PLAYLIST:Mine\nsub/c.m4a\nmissing.mp3\n#EXTINF:12,A\na.mp3\n")
    }

    func testMoveAfterOneThatIsntThereLeavesIt() {
        var p = parse("a.mp3\n/Music/b.flac\n")
        XCTAssertFalse(p.move(id: "A", after: "Z"))
        XCTAssertEqual(p.ids, ["A", "B"])
    }

    func testLineIsRelativeOnlyInsideTheFolder() {
        XCTAssertEqual(PlaylistFile.line(for: "/Music/Lists/sub/c.m4a", in: dir), "sub/c.m4a")
        XCTAssertEqual(PlaylistFile.line(for: "/Music/b.flac", in: dir), "/Music/b.flac")
    }
}

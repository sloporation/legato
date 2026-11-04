import XCTest

final class TrackFilterTests: XCTestCase {
    private let tracks = [
        Track(id: "1", file: "/m/Pink Floyd/Time.flac", title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", genre: "Rock"),
        Track(id: "2", file: "/m/Beyoncé/Halo.m4a", title: "Halo", artist: "Beyoncé", album: "I Am... Sasha Fierce", genre: "Pop"),
        Track(id: "3", file: "/m/Unknown/demo.mp3", title: "Demo", artist: "", album: "", genre: ""),
    ]

    private func ids(_ typed: String) -> [String] { TrackFilter(typed)(tracks).map(\.id) }

    func testWordsAreFoundAnywhereAndAllMustMatch() {
        XCTAssertEqual(ids(""), ["1", "2", "3"])
        XCTAssertEqual(ids("floyd"), ["1"])
        XCTAssertEqual(ids("ROCK time"), ["1"])
        XCTAssertEqual(ids("rock halo"), [])
        XCTAssertEqual(ids("beyonce"), ["2"])        // accents aside
    }

    func testAFieldNamesWhereToLook() {
        XCTAssertEqual(ids("album:\"dark side\""), ["1"])
        XCTAssertEqual(ids("artist:floyd"), ["1"])
        XCTAssertEqual(ids("title:floyd"), [])
        XCTAssertEqual(ids("format:flac"), ["1"])
        XCTAssertEqual(ids("format:M4A"), ["2"])
        XCTAssertEqual(ids("genre:pop format:m4a"), ["2"])
    }

    func testEmptyQuotesFindEmptyFields() {
        XCTAssertEqual(ids("artist:\"\""), ["3"])
        XCTAssertEqual(ids("genre:\"\" format:mp3"), ["3"])
        XCTAssertEqual(ids("year:\"\""), ["1", "2", "3"])
    }

    func testHalfTypedAndUnknownFields() {
        XCTAssertEqual(ids("album:"), ["1", "2", "3"])          // still being typed
        XCTAssertEqual(ids("album:\"dark"), ["1"])              // quote not closed yet
        XCTAssertEqual(ids("nope:time"), [])                    // not a field: the whole word, anywhere
    }
}

import XCTest
@testable import Legato

/// Playlist changes made on the phone, as the playlists show them (docs/sync.md, "Phone → desktop").
final class ChangesTests: XCTestCase {
    let base = [Playlist(name: "Rainy Day", tracks: ["a", "b", "c"]), Playlist(name: "Old", tracks: ["a"])]

    func testEachKindOfChange() {
        let changes = [
            PlaylistChange(op: .create, playlist: "Gym"),
            PlaylistChange(op: .add, playlist: "Gym", track: "c"),
            PlaylistChange(op: .add, playlist: "Gym", track: "a"),
            PlaylistChange(op: .move, playlist: "Gym", track: "a"),                  // to the top
            PlaylistChange(op: .remove, playlist: "Rainy Day", track: "b"),
            PlaylistChange(op: .move, playlist: "Rainy Day", track: "a", after: "c"),
            PlaylistChange(op: .rename, playlist: "Gym", to: "Lifting"),
            PlaylistChange(op: .delete, playlist: "Old"),
        ]
        let lists = base.applying(changes)
        XCTAssertEqual(lists.map(\.name), ["Rainy Day", "Lifting"])
        XCTAssertEqual(lists[0].tracks, ["c", "a"])
        XCTAssertEqual(lists[1].tracks, ["a", "c"])
    }

    func testMadeTwiceComesToTheSame() {
        let changes = [
            PlaylistChange(op: .create, playlist: "Gym"),
            PlaylistChange(op: .add, playlist: "Gym", track: "b"),
            PlaylistChange(op: .remove, playlist: "Rainy Day", track: "a"),
            PlaylistChange(op: .move, playlist: "Rainy Day", track: "c", after: nil),
            PlaylistChange(op: .rename, playlist: "Old", to: "Older"),
        ]
        let once = base.applying(changes)
        XCTAssertEqual(once.applying(changes), once)
    }

    func testChangesThatNoLongerFitDoNothing() {
        let changes = [
            PlaylistChange(op: .add, playlist: "Gone", track: "a"),
            PlaylistChange(op: .remove, playlist: "Rainy Day", track: "z"),
            PlaylistChange(op: .rename, playlist: "Old", to: "Rainy Day"),           // a name that's taken
            PlaylistChange(op: .add, playlist: "Rainy Day", track: "a"),             // already in it
        ]
        XCTAssertEqual(base.applying(changes), base)
    }

    func testTheLogReadsBackWhatWasWritten() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        let changes = [PlaylistChange(op: .move, playlist: "Rainy Day", track: "a", after: "c")]
        try ChangeLog(changes: changes).write(url)
        XCTAssertEqual(ChangeLog.read(url).map(\.op), [.move])
        XCTAssertEqual(ChangeLog.read(url).first?.after, "c")
        // and a move to the top is written without "after"
        try ChangeLog(changes: [PlaylistChange(op: .move, playlist: "R", track: "a")]).write(url)
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("after"))
    }
}

/// What a sync from Legato for Mac fetches and deletes (Sync/SyncClient.swift).
final class SyncPlanTests: XCTestCase {
    private func track(_ id: String, size: Int64 = 10, ext: String = "mp3") -> Track {
        Track(id: id, file: "Music/\(id).\(ext)", size: size, modified: Date(timeIntervalSince1970: 1000))
    }

    func testKeepsWhatIsThereUnchanged() {
        let old = Manifest(tracks: [track("a"), track("b"), track("c")])
        let new = Manifest(tracks: [track("a"), track("b", size: 20), track("d")])
        let plan = SyncClient.plan(old: old, new: new, have: ["a.mp3", "b.mp3", "c.mp3", "x.mp3.part"])
        XCTAssertEqual(plan.fetch.map(\.id), ["b", "d"])
        XCTAssertEqual(plan.remove, ["c.mp3", "x.mp3.part"])
        XCTAssertEqual(plan.bytes, 30)
    }

    func testFetchesAFileThatIsMissing() {
        let m = Manifest(tracks: [track("a")])
        XCTAssertEqual(SyncClient.plan(old: m, new: m, have: []).fetch.map(\.id), ["a"])
        XCTAssertEqual(SyncClient.plan(old: nil, new: m, have: ["a.mp3"]).fetch.map(\.id), ["a"])
    }
}

import XCTest
@testable import Legato

final class PlayQueueTests: XCTestCase {
    private let tracks = (0..<5).map { Track(id: "t\($0)", file: "Music/t\($0).mp3", title: "t\($0)") }
    private func title(_ action: PlayQueue.Action) -> String? {
        switch action {
        case .play(let t): return t.title
        case .stop(let t): return t.map { "stopped at \($0.title)" }
        case .restart: return "restart"
        }
    }

    func testStartsAtTheChosenTrackAndMovesOn() {
        var q = PlayQueue()
        XCTAssertEqual(title(q.start(Array(tracks[0..<3]), at: 1)), "t1")
        XCTAssertEqual(title(q.trackEnded()), "t2")
    }

    func testEndOfTheListStopsAtTheFirstTrack() {
        var q = PlayQueue()
        _ = q.start(Array(tracks[0..<3]), at: 2)
        XCTAssertEqual(title(q.trackEnded()), "stopped at t0")
    }

    func testRepeatAllGoesRound() {
        var q = PlayQueue()
        q.repeatMode = .all
        _ = q.start(Array(tracks[0..<3]), at: 2)
        XCTAssertEqual(title(q.trackEnded()), "t0")
    }

    func testRepeatOneRestartsButNextMovesOn() {
        var q = PlayQueue()
        q.repeatMode = .one
        _ = q.start(Array(tracks[0..<3]), at: 0)
        XCTAssertEqual(q.trackEnded(), .restart)
        XCTAssertEqual(title(q.next()), "t1")
    }

    func testShuffleStartsWithTheChosenTrackAndPlaysEachOnce() {
        var q = PlayQueue()
        q.setShuffle(true)
        XCTAssertEqual(title(q.start(tracks, at: 3)), "t3")
        var heard = ["t3"]
        for _ in 0..<4 { heard.append(title(q.next())!) }
        XCTAssertEqual(Set(heard).count, 5)
        XCTAssertEqual(title(q.next()), "stopped at t3")
    }

    func testShuffleOffKeepsTheCurrentTrack() {
        var q = PlayQueue()
        q.setShuffle(true)
        _ = q.start(tracks, at: 0)
        _ = q.next()
        let playing = q.current
        q.setShuffle(false)
        XCTAssertEqual(q.current, playing)
        // and in order from there
        let index = tracks.firstIndex(of: playing!)!
        if index + 1 < tracks.count { XCTAssertEqual(title(q.next()), tracks[index + 1].title) }
    }

    func testRepeatAllShuffledDoesNotStartTheNewRoundWithTheSameTrack() {
        var q = PlayQueue()
        q.repeatMode = .all
        q.setShuffle(true)
        _ = q.start(Array(tracks[0..<2]), at: 0)
        let last = title(q.next())
        XCTAssertNotEqual(title(q.next()), last)
    }

    func testPreviousRestartsWhenWellIntoATrackElseGoesBack() {
        var q = PlayQueue()
        _ = q.start(tracks, at: 2)
        XCTAssertEqual(q.previous(position: 10), .restart)
        XCTAssertEqual(title(q.previous(position: 1)), "t1")
        _ = q.start(tracks, at: 0)
        XCTAssertEqual(q.previous(position: 1), .restart)      // nothing before the first, with repeat off
    }

    func testAnEmptyListStops() {
        var q = PlayQueue()
        XCTAssertEqual(q.start([], at: 0), .stop(nil))
        XCTAssertEqual(q.next(), .stop(nil))
    }
}

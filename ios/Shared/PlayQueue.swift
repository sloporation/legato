import Foundation

enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one

    var next: RepeatMode { self == .off ? .all : self == .all ? .one : .off }
}

/// What to play and in what order, apart from playing it: the list as given, the order (shuffled or not), where we are in it, and what
/// repeat does at the ends. The Player asks it what comes next and does it. Same rules as Legato Desktop's player.
struct PlayQueue {
    /// What the player should do now.
    enum Action: Equatable {
        case play(Track)       // load it and play
        case restart           // the same track, from the start
        case stop(Track?)      // load it (the first track again) and stay stopped
    }

    private(set) var tracks: [Track] = []
    private(set) var order: [Int] = []       // indexes into tracks, in playing order
    private(set) var step = -1               // where we are in order
    private(set) var shuffle = false
    var repeatMode: RepeatMode = .off
    /// Random numbers in 0..<n, replaceable so tests can choose them.
    var random: (Int) -> Int = { Int.random(in: 0..<$0) }

    var current: Track? { order.indices.contains(step) ? tracks[order[step]] : nil }
    var isEmpty: Bool { order.isEmpty }
    /// What comes after the current track, in order.
    var upNext: [Track] { step + 1 < order.count ? order[(step + 1)...].map { tracks[$0] } : [] }

    /// A new list, starting at `index`.
    mutating func start(_ tracks: [Track], at index: Int) -> Action {
        self.tracks = tracks
        guard !tracks.isEmpty else { order = []; step = -1; return .stop(nil) }
        reorder(first: min(max(0, index), tracks.count - 1))
        return .play(current!)
    }

    /// Shuffle on or off. What is playing goes on; only what comes after it changes.
    mutating func setShuffle(_ on: Bool) {
        guard on != shuffle else { return }
        shuffle = on
        if let playing = order.indices.contains(step) ? order[step] : nil { reorder(first: playing) }
    }

    /// The order to play in, starting with tracks[first].
    private mutating func reorder(first: Int) {
        order = Array(tracks.indices)
        if shuffle {
            order.removeAll { $0 == first }
            // Fisher–Yates with our own random numbers, so tests can pin it down
            for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, random(i + 1)) }
            order.insert(first, at: 0)
            step = 0
        } else {
            step = first
        }
    }

    /// The track came to its end.
    mutating func trackEnded() -> Action {
        repeatMode == .one ? .restart : advance()
    }

    /// The next button: moves on even when repeating one track.
    mutating func next() -> Action { advance() }

    /// The previous button: to the start of the track when well into it (or at the very start of the list), else the one before.
    mutating func previous(position: Double) -> Action {
        guard !order.isEmpty else { return .stop(nil) }
        if position > 3 || (step == 0 && repeatMode == .off) { return .restart }
        step = step > 0 ? step - 1 : order.count - 1
        return .play(current!)
    }

    private mutating func advance() -> Action {
        guard !order.isEmpty else { return .stop(nil) }
        if step + 1 < order.count {
            step += 1
            return .play(current!)
        }
        if repeatMode != .off {
            if shuffle {
                // a new order for the next time round, which doesn't start with the track just heard
                let last = order[order.count - 1]
                var first = last
                while tracks.count > 1 && first == last { first = random(tracks.count) }
                reorder(first: first)
            } else {
                step = 0
            }
            return .play(current!)
        }
        // the end: back to the first track, stopped, as a CD player does
        step = 0
        return .stop(current)
    }
}

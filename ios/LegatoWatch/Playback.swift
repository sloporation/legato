import SwiftUI

/// What the watch's screens play with: the watch's own Player, or the iPhone's (PhoneRemote). Both are observable, so the screens
/// follow either.
@MainActor
protocol Playback: AnyObject {
    var current: Track? { get }
    var isPlaying: Bool { get }
    var position: Double { get }
    var duration: Double { get }
    var problem: String? { get }
    var artwork: UIImage? { get }
    /// Playing on the iPhone: the crown turns the iPhone's volume.
    var isRemote: Bool { get }
    func play(_ tracks: [Track], from index: Int, source: Remote.Source)
    func shufflePlay(_ tracks: [Track], source: Remote.Source)
    func toggle()
    func next()
    func previous()
}

extension Player: Playback {
    var artwork: UIImage? { library.coverURL(current?.cover).flatMap { UIImage(contentsOfFile: $0.path) } }
    var isRemote: Bool { false }

    func play(_ tracks: [Track], from index: Int, source: Remote.Source) {
        shuffle = false
        play(tracks, from: index)
    }

    func shufflePlay(_ tracks: [Track], source: Remote.Source) { shufflePlay(tracks) }
}

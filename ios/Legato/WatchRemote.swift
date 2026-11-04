import Foundation
import Observation
import UIKit
import WatchConnectivity

/// Answers Legato on the watch when it's the iPhone's remote (docs/sync.md, "The watch as a remote"): it sends the library for the
/// watch to browse, plays what the watch chooses, and tells the watch what's playing. A message from the watch wakes the app if it
/// isn't running. WatchSender, the session's delegate, hands the messages on.
@MainActor
final class WatchRemote {
    private let library: LibraryStore
    private let player: Player
    private let session: WCSession?
    /// the library as last sent: the watch fetches it a piece at a time
    private var catalog: Remote.Catalog?
    private var lastPushed: Remote.State?
    private var awake: UIBackgroundTaskIdentifier = .invalid
    private var sleeping: Task<Void, Never>?

    init(library: LibraryStore, player: Player, session: WCSession?) {
        self.library = library
        self.player = player
        self.session = session
        observePlayer()
        observeLibrary()
    }

    /// A message from the watch, and the answer to it.
    func handle(_ message: [String: Any]) async -> [String: Any] {
        stayAwake()
        switch message["op"] as? String {
        case "catalog":
            library.reload()
            guard let catalog = try? Remote.Catalog(tracks: library.tracks, playlists: library.playlists) else {
                return ["error": String(localized: "The iPhone's library couldn't be read.")]
            }
            self.catalog = catalog
            let same = message["have"] as? String == catalog.version
            return ["version": catalog.version, "pieces": same ? 0 : catalog.pieces]
        case "piece":
            guard let catalog, message["version"] as? String == catalog.version, let i = message["index"] as? Int,
                  let piece = catalog.piece(i) else { return ["error": "changed"] }
            return ["data": piece]
        case "play":
            guard let source = Remote.Source(message: message) else { break }
            let tracks = library.tracks(from: source)
            guard !tracks.isEmpty else {
                return reply(art: message["art"], problem: String(localized: "That isn't on the iPhone any more."))
            }
            if message["shuffle"] as? Bool == true {
                player.shufflePlay(tracks)
            } else {
                player.shuffle = false
                player.play(tracks, from: tracks.firstIndex { $0.id == message["track"] as? String } ?? 0)
            }
            await settle()
        case "toggle":
            player.toggle()
            await settle()
        case "next":
            player.next()
            await settle()
        case "previous":
            player.previous()
            await settle()
        default:
            break       // "state", and anything newer than this app: what's playing
        }
        return reply(art: message["art"])
    }

    /// What's playing, with the cover when the watch hasn't got it (it says which track's cover it has).
    private func reply(art has: Any?, problem: String? = nil) -> [String: Any] {
        var m = state.message
        if let problem { m["problem"] = problem }
        if let track = player.current, has as? String != track.id, let art = artwork(track) {
            m["art"] = art
            m["artFor"] = track.id
        }
        return m
    }

    private var state: Remote.State {
        Remote.State(track: player.current, playing: player.isPlaying, position: player.position, duration: player.duration,
                     problem: player.problem, upNext: Array(player.upNext.prefix(25).map { var t = $0; t.cover = nil; return t }))
    }

    /// Playing starts a moment after it's asked for (the audio session): answer once it has, or couldn't.
    private func settle() async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(100))
            if player.isPlaying || player.problem != nil { break }
        }
    }

    /// The cover, small, for the watch's Now Playing.
    private func artwork(_ track: Track) -> Data? {
        guard let url = library.coverURL(track.cover), let image = UIImage(contentsOfFile: url.path) else { return nil }
        let side: CGFloat = 120
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        return small.jpegData(compressionQuality: 0.7)
    }

    /// Keeps the app running in the background for a while after each message: the watch asks every few seconds while it's open,
    /// and iOS would otherwise suspend the app a few seconds after each answer, which the watch sees as the iPhone going away.
    private func stayAwake() {
        if awake == .invalid {
            awake = UIApplication.shared.beginBackgroundTask(withName: "Watch remote") { [weak self] in
                MainActor.assumeIsolated { self?.letSleep() }
            }
        }
        sleeping?.cancel()
        sleeping = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { letSleep() }
        }
    }

    private func letSleep() {
        guard awake != .invalid else { return }
        UIApplication.shared.endBackgroundTask(awake)
        awake = .invalid
    }

    // MARK: telling the watch

    /// The watch opened, or went away.
    func reachabilityChanged() {
        lastPushed = nil
        push()
    }

    /// What's playing, when it changes and the watch is open (it asks now and then besides, for the position).
    private func push() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        let now = state
        guard now.track != lastPushed?.track || now.playing != lastPushed?.playing || now.problem != lastPushed?.problem else { return }
        lastPushed = now
        var message = now.message
        message["op"] = "state"
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    private func observePlayer() {
        withObservationTracking {
            _ = player.current
            _ = player.isPlaying
            _ = player.problem
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.push()
                self?.observePlayer()
            }
        }
    }

    /// The library changed (a sync, a playlist change): the watch fetches it again.
    private func observeLibrary() {
        withObservationTracking {
            _ = library.tracks
            _ = library.playlists
        } onChange: { [weak self] in
            Task { @MainActor in
                if let session = self?.session, session.activationState == .activated, session.isReachable {
                    session.sendMessage(["op": "catalog-changed"], replyHandler: nil, errorHandler: nil)
                }
                self?.observeLibrary()
            }
        }
    }
}

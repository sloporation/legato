import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Plays music. The app hands it a list (`play(_:from:)`) and it owns what happens next: the order (shuffle), repeat, moving on at the
/// end of a track or past one that won't play. It also answers the lock screen, Control Center, headphone buttons and the watch's
/// Now Playing, and stops when headphones are unplugged or a call comes in.
@MainActor
@Observable
final class Player {
    private(set) var current: Track?
    private(set) var isPlaying = false
    private(set) var position: Double = 0      // seconds
    private(set) var duration: Double = 0      // seconds (the tags' length when there is one)
    private(set) var problem: String?          // why the last track couldn't be played
    var shuffle: Bool {
        get { queue.shuffle }
        set { queue.setShuffle(newValue) }
    }
    var repeatMode: RepeatMode {
        get { queue.repeatMode }
        set { queue.repeatMode = newValue }
    }
    var upNext: [Track] { queue.upNext }

    private let library: LibraryStore
    private var queue = PlayQueue()
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var failures = 0                   // tracks in a row that wouldn't play: give up when it's all of them
    private var sessionReady = false

    init(library: LibraryStore) {
        self.library = library
        player.automaticallyWaitsToMinimizeStalling = false     // local files: start at once
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if self.duration == 0, let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        observeSession()
        setUpRemoteCommands()
    }

    // MARK: what the app asks for

    func play(_ tracks: [Track], from index: Int = 0) {
        failures = 0
        perform(queue.start(tracks, at: index))
    }

    /// Shuffle the whole list, starting anywhere.
    func shufflePlay(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        queue.setShuffle(true)
        play(tracks, from: Int.random(in: 0..<tracks.count))
    }

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        Task {
            guard await activateSession() else { return }
            player.play()
            isPlaying = true
            updateNowPlaying()
        }
    }

    func next() { failures = 0; perform(queue.next()) }
    func previous() { perform(queue.previous(position: position)) }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        position = seconds
        updateNowPlaying()
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    // MARK: playing

    private func perform(_ action: PlayQueue.Action) {
        switch action {
        case .play(let track):
            load(track)
            resume()
        case .restart:
            seek(to: 0)
            resume()
        case .stop(let track):
            if let track { load(track) } else { unload() }
            pause()
        }
    }

    private func load(_ track: Track) {
        current = track
        problem = nil
        position = 0
        duration = track.duration
        let item = AVPlayerItem(url: library.url(for: track))
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers = [
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ended() }
            },
            NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.failed(item.error) }
            },
        ]
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed { self?.failed(item.error) }
                if item.status == .readyToPlay { self?.failures = 0 }
            }
        }
        player.replaceCurrentItem(with: item)
        updateNowPlaying()
    }

    private func unload() {
        current = nil
        player.replaceCurrentItem(with: nil)
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func ended() { perform(queue.trackEnded()) }

    private func failed(_ error: Error?) {
        let title = current?.displayTitle ?? ""
        problem = String(localized: "Couldn't play “\(title)”") + (error.map { ": " + $0.localizedDescription } ?? "")
        failures += 1
        // move on, unless nothing in the list will play
        if failures < max(1, queue.tracks.count) { perform(queue.next()) } else { pause() }
    }

    // MARK: the audio session

    /// Music keeps playing in the background and with the ring switch on. On the watch it plays only through Bluetooth headphones:
    /// activating asks for them (the system shows its picker) and fails if none is chosen.
    private func activateSession() async -> Bool {
        if sessionReady { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            #if os(watchOS)
            sessionReady = try await session.activate()
            #else
            try session.setActive(true)
            sessionReady = true
            #endif
        } catch {
            problem = error.localizedDescription
        }
        return sessionReady
    }

    private func observeSession() {
        let center = NotificationCenter.default
        // a call, an alarm, Siri: pause, and carry on afterwards if the system says so
        _ = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began { self.isPlaying = false; self.sessionReady = false }
                if type == .ended, options?.contains(.shouldResume) == true { self.resume() }
            }
        }
        // headphones unplugged: stop rather than play out loud
        _ = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        }
    }

    // MARK: lock screen, Control Center, headphones

    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let url = library.coverURL(track.cover), let image = UIImage(contentsOfFile: url.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

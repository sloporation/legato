import Foundation
import Observation
import UIKit
import WatchConnectivity

/// Legato on the iPhone, played from the watch (docs/sync.md, "The watch as a remote"). While the iPhone is in reach, the watch shows
/// its library (fetched from it and kept, so it shows at once next time) and tells it what to play; headphones are with the iPhone
/// then. Out of reach, the watch plays its own music. WatchReceiver, the session's delegate, hands on what the iPhone says.
@MainActor
@Observable
final class PhoneRemote: Playback {
    /// Whether the iPhone is in reach: the watch is its remote. Becomes true at once; false only after a while out of reach. (The
    /// session says the iPhone isn't reachable whenever iOS suspends Legato there, which it does a few seconds after the watch last
    /// asked it something; it's reachable again once the watch asks or iOS wakes it. That mustn't swap the screens.)
    private(set) var connected = false
    /// Whether it's known yet (just after launch, it isn't for a moment).
    private(set) var decided = false
    /// Fetching the library now.
    private(set) var loading = false
    /// Why the library couldn't be fetched, the last time it couldn't.
    private(set) var libraryProblem: String?
    let library: LibraryStore

    private(set) var current: Track?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var problem: String?
    private(set) var artwork: UIImage?
    var isRemote: Bool { true }

    private var base = Remote.State()           // the last the iPhone said, which `position` counts on from
    private var artFor: String?
    private var leaving: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    private var active = false
    private var wasReachable = false
    private let session = WCSession.default

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "iPhone", directoryHint: .isDirectory)
    }
    private var version: String? {
        get { UserDefaults.standard.string(forKey: "phone.catalog") }
        set { UserDefaults.standard.set(newValue, forKey: "phone.catalog") }
    }

    init() {
        library = LibraryStore(root: Self.root, requireFiles: false)
        // (if the session doesn't say within a moment, the iPhone isn't there)
        Task {
            try? await Task.sleep(for: .seconds(2))
            decided = true
        }
    }

    // MARK: reach

    func reachabilityChanged() {
        guard session.activationState == .activated else { return }
        if session.isReachable != wasReachable {
            wasReachable = session.isReachable
            NSLog("legato remote: iPhone %@", session.isReachable ? "reachable" : "not reachable")
        }
        decided = true
        if session.isReachable {
            leaving?.cancel()
            leaving = nil
            if !connected {
                connected = true
                loading = library.tracks.isEmpty       // (so it doesn't say there's no music while asking)
                Task { await refresh(); await fetchLibrary(force: true) }
            }
        } else if connected && leaving == nil {
            leaving = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                if !session.isReachable { connected = false }
                leaving = nil
            }
        }
    }

    /// The app came to the front, or went: while it's in front and the iPhone is playing, the position moves on, and the watch asks
    /// what's playing now and then (the iPhone says when the track changes, but not when it's moved on its lock screen).
    func setActive(_ active: Bool) {
        self.active = active
        ticking?.cancel()
        ticking = nil
        guard active else { return }
        reachabilityChanged()
        ticking = Task {
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if isPlaying { position = min(duration, base.position + Date.now.timeIntervalSince(base.at)) }
                n += 1
                if connected && n % 5 == 0 { await refresh() }
            }
        }
    }

    // MARK: what the iPhone says

    /// A message the iPhone sent unasked.
    func received(_ message: [String: Any]) {
        switch message["op"] as? String {
        case "state": show(message)
        case "catalog-changed": Task { await fetchLibrary() }
        default: break
        }
    }

    private func show(_ message: [String: Any]) {
        let state = Remote.State(message: message)
        base = state
        if state.track?.id != current?.id { artwork = nil; artFor = nil }
        current = state.track
        isPlaying = state.playing
        duration = state.duration > 0 ? state.duration : state.track?.duration ?? 0
        position = state.playing ? min(duration, state.position + Date.now.timeIntervalSince(state.at)) : state.position
        problem = state.problem
        if let data = message["art"] as? Data, let id = message["artFor"] as? String, id == current?.id {
            artwork = UIImage(data: data)
            artFor = id
        }
    }

    /// Asks what's playing.
    func refresh() async {
        if let reply = try? await ask(["op": "state"]) { show(reply) }
    }

    /// Fetches the library if it changed since last time, a piece at a time; tries a few times, as the iPhone can be suspended
    /// part way through.
    func fetchLibrary(force: Bool = false) async {
        guard force || !loading else { return }
        loading = true
        defer { loading = false }
        for attempt in 1...3 {
            do {
                try await fetchLibraryOnce()
                libraryProblem = nil
                return
            } catch {
                NSLog("legato remote: fetching the iPhone's library, attempt %d: %@", attempt, String(describing: error))
                libraryProblem = String(localized: "Couldn't get your iPhone's music: \(error.localizedDescription)")
            }
        }
    }

    private func fetchLibraryOnce() async throws {
        do {
            var request: [String: Any] = ["op": "catalog"]
            if version != nil, !library.tracks.isEmpty { request["have"] = version }
            let answer = try await ask(request)
            guard let latest = answer["version"] as? String, let pieces = answer["pieces"] as? Int else {
                throw Failure(answer["error"] as? String ?? String(localized: "Legato on the iPhone didn't answer."))
            }
            if pieces == 0 { return }       // (the same as here)
            var data = Data()
            for i in 0..<pieces {
                let reply = try await ask(["op": "piece", "version": latest, "index": i])
                guard let piece = reply["data"] as? Data else { throw Failure(String(localized: "It changed while being sent.")) }
                data.append(piece)
            }
            let manifest = try Remote.Catalog.manifest(from: data)
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            try manifest.encoded().write(to: library.manifestURL, options: .atomic)
            version = latest
            library.reload(force: true)
        }
    }

    private struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ why: String) { errorDescription = why }
    }

    // MARK: telling the iPhone

    func play(_ tracks: [Track], from index: Int, source: Remote.Source) {
        var message = source.message
        message["op"] = "play"
        if tracks.indices.contains(index) { message["track"] = tracks[index].id }
        command(message)
    }

    func shufflePlay(_ tracks: [Track], source: Remote.Source) {
        var message = source.message
        message["op"] = "play"
        message["shuffle"] = true
        command(message)
    }

    func toggle() {
        isPlaying.toggle()      // (at once; the iPhone's answer puts it right)
        command(["op": "toggle"])
    }

    func next() { command(["op": "next"]) }
    func previous() { command(["op": "previous"]) }

    private func command(_ message: [String: Any]) {
        Task {
            do {
                show(try await ask(message))
            } catch {
                problem = String(localized: "Couldn't reach your iPhone.")
            }
        }
    }

    /// Sends a message to the iPhone and waits for its answer. Each says which track's cover the watch has, so the answer brings the
    /// cover only when it's needed. Sending wakes Legato on the iPhone if iOS has suspended it; if the session says the iPhone can't
    /// be reached just then, it tries again a moment later, and it gives up on an answer that doesn't come.
    private func ask(_ message: [String: Any]) async throws -> [String: Any] {
        var message = message
        if let artFor { message["art"] = artFor }
        let op = message["op"] as? String ?? ""
        var attempt = 1
        while true {
            do {
                return try await send(message)
            } catch let error as WCError where error.code == .notReachable && attempt < 4 {
                attempt += 1
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                NSLog("legato remote: %@ failed: %@", op, String(describing: error))
                throw error
            }
        }
    }

    private func send(_ message: [String: Any]) async throws -> [String: Any] {
        let answer = Answer()
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            answer.finish(.failure(Failure(String(localized: "Legato on the iPhone didn't answer."))))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            answer.start(continuation)
            session.sendMessage(message, replyHandler: { answer.finish(.success($0)) },
                                errorHandler: { answer.finish(.failure($0)) })
        }
    }
}

/// An answer from the iPhone, or the reason there isn't one: whichever comes first.
private final class Answer: @unchecked Sendable {
    private var continuation: CheckedContinuation<[String: Any], Error>?
    private var early: Result<[String: Any], Error>?
    private let lock = NSLock()

    func start(_ c: CheckedContinuation<[String: Any], Error>) {
        lock.lock()
        if let early {
            lock.unlock()
            c.resume(with: early)
            return
        }
        continuation = c
        lock.unlock()
    }

    func finish(_ result: Result<[String: Any], Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        if c == nil && early == nil { early = result }
        lock.unlock()
        c?.resume(with: result)
    }
}

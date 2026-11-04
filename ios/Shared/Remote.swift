import CryptoKit
import Foundation

/// Legato on the watch as a remote for Legato on the iPhone (docs/sync.md, "The watch as a remote"): while the iPhone is in reach, the
/// watch browses the iPhone's library and tells it what to play, over WatchConnectivity messages. These are what both sides say.
enum Remote {
    /// Where a list of tracks came from, so the iPhone can make the same list from its own library (sending the tracks themselves
    /// could be more than a message holds). Both sides group the same tracks the same way, so the lists match.
    enum Source: Equatable {
        case playlist(String)       // by name
        case album(String)          // by Album.id
        case artist(String)         // by name
        case songs                  // every song, by title

        var message: [String: Any] {
            switch self {
            case .playlist(let name): ["source": "playlist", "name": name]
            case .album(let id): ["source": "album", "name": id]
            case .artist(let name): ["source": "artist", "name": name]
            case .songs: ["source": "songs"]
            }
        }

        init?(message: [String: Any]) {
            let name = message["name"] as? String
            switch message["source"] as? String {
            case "playlist": guard let name else { return nil }; self = .playlist(name)
            case "album": guard let name else { return nil }; self = .album(name)
            case "artist": guard let name else { return nil }; self = .artist(name)
            case "songs": self = .songs
            default: return nil
            }
        }
    }

    /// What the iPhone is playing.
    struct State: Equatable {
        var track: Track?
        var playing = false
        var position: Double = 0        // seconds, at `at`
        var duration: Double = 0
        var at = Date.now
        var problem: String?
        var upNext: [Track] = []        // the first few after it

        var message: [String: Any] {
            var m: [String: Any] = ["playing": playing, "position": position, "duration": duration, "at": at.timeIntervalSince1970]
            if let track, let data = try? JSONEncoder.remote.encode(track) { m["track"] = data }
            if let problem { m["problem"] = problem }
            if !upNext.isEmpty, let data = try? JSONEncoder.remote.encode(upNext) { m["next"] = data }
            return m
        }

        init(track: Track? = nil, playing: Bool = false, position: Double = 0, duration: Double = 0, at: Date = .now, problem: String? = nil,
             upNext: [Track] = []) {
            self.track = track; self.playing = playing; self.position = position; self.duration = duration; self.at = at; self.problem = problem
            self.upNext = upNext
        }

        init(message m: [String: Any]) {
            track = (m["track"] as? Data).flatMap { try? JSONDecoder.remote.decode(Track.self, from: $0) }
            playing = m["playing"] as? Bool ?? false
            position = m["position"] as? Double ?? 0
            duration = m["duration"] as? Double ?? 0
            at = (m["at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
            problem = m["problem"] as? String
            upNext = (m["next"] as? Data).flatMap { try? JSONDecoder.remote.decode([Track].self, from: $0) } ?? []
        }
    }

    /// The iPhone's library for the watch to browse: its tracks (without covers) and playlists, as a manifest, JSON compressed with
    /// LZFSE, sent in pieces that each fit in a message. Its version is a hash of it, so the watch only fetches it when it changed.
    struct Catalog {
        static let pieceSize = 48_000
        var data: Data
        var version: String

        init(tracks: [Track], playlists: [Playlist]) throws {
            let manifest = Manifest(tracks: tracks.map { var t = $0; t.cover = nil; return t }, playlists: playlists)
            data = try (manifest.encoded() as NSData).compressed(using: .lzfse) as Data
            version = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        }

        var pieces: Int { (data.count + Self.pieceSize - 1) / Self.pieceSize }

        func piece(_ i: Int) -> Data? {
            guard i >= 0, i < pieces else { return nil }
            return data.subdata(in: i * Self.pieceSize..<min(data.count, (i + 1) * Self.pieceSize))
        }

        /// The manifest, from the pieces put back together.
        static func manifest(from data: Data) throws -> Manifest {
            try Manifest.decode(try (data as NSData).decompressed(using: .lzfse) as Data)
        }
    }
}

extension LibraryStore {
    /// The tracks a source names, in the order the watch shows them.
    func tracks(from source: Remote.Source) -> [Track] {
        switch source {
        case .playlist(let name): playlists.first { $0.name == name }.map(tracks(of:)) ?? []
        case .album(let id): albums.first { $0.id == id }?.tracks ?? []
        case .artist(let name): artists.first { $0.name == name }?.tracks ?? []
        case .songs: songsByTitle
        }
    }
}

extension JSONEncoder {
    static let remote: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let remote: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

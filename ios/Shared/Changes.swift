import Foundation

/// A change made to the playlists on the phone, kept in `Legato/changes.json` until the next sync takes it to the desktop
/// (docs/sync.md, "Phone → desktop").
struct PlaylistChange: Codable, Equatable {
    enum Op: String, Codable { case create, rename, delete, add, remove, move }

    var op: Op
    var playlist: String
    var to: String? = nil        // rename: the new name
    var track: String? = nil     // add, remove, move: the track's id
    var after: String? = nil     // move: the track it goes after; none, to the top
    var at: Date? = .now
}

struct ChangeLog: Codable {
    var version = 1
    var changes: [PlaylistChange] = []

    static func read(_ url: URL) -> [PlaylistChange] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ChangeLog.self, from: data))?.changes ?? []
    }

    func write(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension Array where Element == Playlist {
    /// The playlists with the changes made, each as far as it still can be.
    func applying(_ changes: [PlaylistChange]) -> [Playlist] {
        var lists = self
        for c in changes {
            let i = lists.firstIndex { $0.name == c.playlist }
            switch c.op {
            case .create:
                if i == nil { lists.append(Playlist(name: c.playlist)) }
            case .rename:
                if let i, let to = c.to, !to.isEmpty, !lists.contains(where: { $0.name == to }) { lists[i].name = to }
            case .delete:
                if let i { lists.remove(at: i) }
            case .add:
                if let i, let t = c.track, !lists[i].tracks.contains(t) { lists[i].tracks.append(t) }
            case .remove:
                if let i, let t = c.track, let at = lists[i].tracks.firstIndex(of: t) { lists[i].tracks.remove(at: at) }
            case .move:
                guard let i, let t = c.track, let from = lists[i].tracks.firstIndex(of: t) else { break }
                lists[i].tracks.remove(at: from)
                if let after = c.after, let a = lists[i].tracks.firstIndex(of: after) {
                    lists[i].tracks.insert(t, at: a + 1)
                } else if c.after == nil {
                    lists[i].tracks.insert(t, at: 0)
                } else {
                    lists[i].tracks.insert(t, at: from)     // (the one it went after is gone: it stays put)
                }
            }
        }
        return lists
    }
}

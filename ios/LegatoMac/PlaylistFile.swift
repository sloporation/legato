import Foundation

/// A playlist file (.m3u or .m3u8) in a music folder, where Legato Desktop keeps playlists too: each line naming a file, with the
/// comment lines (#EXTINF) just before it. Edits keep everything else in the file as it was, so other players' lines survive.
struct PlaylistFile: Equatable {
    struct Entry: Equatable {
        var comments: [String]      // #EXTINF and the like, just before the line
        var line: String            // as written: relative to the playlist's folder, or in full
        var id: String?             // the track's id, if it is in the library
    }

    var header: [String] = ["#EXTM3U"]      // what comes before the first entry
    var entries: [Entry] = []
    var trailer: [String] = []              // comments after the last entry

    static let suffixes: Set<String> = ["m3u", "m3u8"]

    /// The ids of the tracks in it, in order, leaving out lines that aren't in the library.
    var ids: [String] { entries.compactMap(\.id) }

    /// `idOf` gives the id of a file in the library (its full path), nil if it isn't one.
    init(text: String, dir: URL, idOf: (String) -> String?) {
        header = []
        var pending: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                if entries.isEmpty && !trimmed.hasPrefix("#EXTINF") { header.append(trimmed) } else { pending.append(trimmed) }
                continue
            }
            // (a file or folder's name can start or end with a space: the line as written first, then trimmed)
            let line = String(raw)
            let id = idOf(Self.path(of: line, in: dir)) ?? idOf(Self.path(of: trimmed, in: dir))
            entries.append(Entry(comments: pending, line: line, id: id))
            pending = []
        }
        trailer = pending
    }

    init() {}

    var text: String {
        (header + entries.flatMap { $0.comments + [$0.line] } + trailer).joined(separator: "\n") + "\n"
    }

    /// The full path a line names: in full, a file:// URL, or relative to the playlist's folder.
    static func path(of line: String, in dir: URL) -> String {
        if line.hasPrefix("file://"), let url = URL(string: line) { return url.standardized.path }
        let line = line.replacingOccurrences(of: "\\", with: "/")     // (written on Windows)
        if line.hasPrefix("/") { return URL(filePath: line).standardized.path }
        return dir.appending(path: line).standardized.path
    }

    /// A track's line: from the playlist's folder (as most players write them), else in full.
    static func line(for path: String, in dir: URL) -> String {
        let base = dir.standardized.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    // MARK: changes (the phones' too: docs/sync.md)

    /// Adds the track at the end, unless it is already in. False if it was.
    @discardableResult
    mutating func add(id: String, path: String, dir: URL) -> Bool {
        guard !ids.contains(id) else { return false }
        entries.append(Entry(comments: [], line: Self.line(for: path, in: dir), id: id))
        return true
    }

    @discardableResult
    mutating func remove(id: String) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: i)
        return true
    }

    /// Moves the track to just after another (wherever that is), or to the top. A track that isn't in, or one to go after that isn't,
    /// leaves it as it is.
    @discardableResult
    mutating func move(id: String, after: String?) -> Bool {
        guard let from = entries.firstIndex(where: { $0.id == id }) else { return false }
        if let after, !entries.contains(where: { $0.id == after }) || after == id { return false }
        let entry = entries.remove(at: from)
        if let after, let a = entries.firstIndex(where: { $0.id == after }) {
            entries.insert(entry, at: a + 1)
        } else {
            entries.insert(entry, at: 0)
        }
        return true
    }
}

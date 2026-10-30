import Foundation

/// What is synced: `Legato/manifest.json`, written by Legato Desktop on the iPhone and by the iPhone on the watch. The format is in
/// docs/sync.md. Missing keys take their defaults and unknown ones are ignored, so either side can add fields.
struct Manifest: Codable, Equatable {
    var version: Int = 1
    var generated: Date?
    var source: String?
    var tracks: [Track] = []
    var playlists: [Playlist] = []

    init(version: Int = 1, generated: Date? = nil, source: String? = nil, tracks: [Track] = [], playlists: [Playlist] = []) {
        self.version = version
        self.generated = generated
        self.source = source
        self.tracks = tracks
        self.playlists = playlists
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generated = try c.decodeIfPresent(Date.self, forKey: .generated)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
    }

    static func decode(_ data: Data) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct Track: Codable, Identifiable, Hashable {
    var id: String              // stable across syncs
    var file: String            // relative to the Legato folder: "Music/<id>.<ext>"
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumArtist: String = ""
    var genre: String = ""
    var year: Int = 0
    var trackNumber: Int = 0
    var discNumber: Int = 0
    var duration: Double = 0    // seconds; 0 when the file doesn't say
    var size: Int64 = 0
    var modified: Date?
    var cover: String?          // relative to the Legato folder

    init(id: String, file: String, title: String = "", artist: String = "", album: String = "", albumArtist: String = "",
         genre: String = "", year: Int = 0, trackNumber: Int = 0, discNumber: Int = 0, duration: Double = 0,
         size: Int64 = 0, modified: Date? = nil, cover: String? = nil) {
        self.id = id; self.file = file; self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.genre = genre; self.year = year; self.trackNumber = trackNumber
        self.discNumber = discNumber; self.duration = duration; self.size = size; self.modified = modified; self.cover = cover
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(String.self, forKey: .file)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
        genre = try c.decodeIfPresent(String.self, forKey: .genre) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        trackNumber = try c.decodeIfPresent(Int.self, forKey: .trackNumber) ?? 0
        discNumber = try c.decodeIfPresent(Int.self, forKey: .discNumber) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        modified = try c.decodeIfPresent(Date.self, forKey: .modified)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
    }

    /// What to show when the tags say nothing: the file's name.
    var displayTitle: String { title.isEmpty ? (file as NSString).lastPathComponent : title }
    /// Whose album it is: the album artist, else the artist.
    var albumArtistOrArtist: String { albumArtist.isEmpty ? artist : albumArtist }
    /// Which album it is on, as the desktop groups them: album artist (else artist) and album title, ignoring case.
    var albumKey: String { albumArtistOrArtist.lowercased() + "\u{1f}" + album.lowercased() }
}

struct Playlist: Codable, Hashable, Identifiable {
    var name: String
    var tracks: [String] = []   // track ids, in playlist order
    var id: String { name }
}

/// An album, grouped from the tracks.
struct Album: Identifiable, Hashable {
    var id: String              // Track.albumKey
    var title: String
    var artist: String
    var year: Int
    var genre: String
    var tracks: [Track]         // disc, then track number, then title
    var cover: String?
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

/// An artist (an album artist, else the artist), grouped from the tracks.
struct Artist: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var albums: [Album]
    var tracks: [Track] { albums.flatMap(\.tracks) }
}

extension Track {
    /// Album order: disc (none counts as 1), then track number (numbered ones first), then title.
    static func albumOrder(_ a: Track, _ b: Track) -> Bool {
        let da = max(1, a.discNumber), db = max(1, b.discNumber)
        if da != db { return da < db }
        let ta = a.trackNumber > 0 ? a.trackNumber : Int.max, tb = b.trackNumber > 0 ? b.trackNumber : Int.max
        if ta != tb { return ta < tb }
        return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
    }
}

enum Grouping {
    static let unknownAlbum = String(localized: "Unknown Album")
    static let unknownArtist = String(localized: "Unknown Artist")

    /// Albums, by artist then title.
    static func albums(_ tracks: [Track]) -> [Album] {
        var byKey: [String: Album] = [:]
        for t in tracks {
            if var a = byKey[t.albumKey] {
                a.tracks.append(t)
                a.year = max(a.year, t.year)
                if a.genre.isEmpty { a.genre = t.genre }
                if a.cover == nil { a.cover = t.cover }
                byKey[t.albumKey] = a
            } else {
                byKey[t.albumKey] = Album(id: t.albumKey, title: t.album.isEmpty ? unknownAlbum : t.album,
                                          artist: t.albumArtistOrArtist.isEmpty ? unknownArtist : t.albumArtistOrArtist,
                                          year: t.year, genre: t.genre, tracks: [t], cover: t.cover)
            }
        }
        return byKey.values
            .map { album in var a = album; a.tracks.sort(by: Track.albumOrder); return a }
            .sorted {
                let c = $0.artist.localizedStandardCompare($1.artist)
                return c != .orderedSame ? c == .orderedAscending : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    /// Artists, by name, each with their albums by year then title.
    static func artists(_ albums: [Album]) -> [Artist] {
        Dictionary(grouping: albums, by: { $0.artist.lowercased() })
            .map { _, albums in
                Artist(name: albums[0].artist,
                       albums: albums.sorted { $0.year != $1.year ? $0.year < $1.year : $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

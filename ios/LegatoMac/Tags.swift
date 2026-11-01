import Foundation
import TagLibC

/// A music file's tags, read and written with TagLib (built by TagLib/build.sh), through its C API: the same names and rules as Legato
/// Desktop's (qt/library.cpp), so either app reads what the other wrote.
enum Tags {
    /// The tags the edit window changes, and the TagLib name of each (which TagLib maps onto ID3v2 frames, Vorbis comments, MP4 atoms…).
    enum Field: String, CaseIterable, Identifiable {
        case title, artist, album, albumArtist, genre, date, trackNumber, trackTotal, discNumber, discTotal
        var id: String { rawValue }
    }

    private static let editable: [(Field, String)] = [
        (.title, "TITLE"), (.artist, "ARTIST"), (.album, "ALBUM"), (.albumArtist, "ALBUMARTIST"), (.genre, "GENRE"), (.date, "DATE"),
    ]

    /// What the edit window shows about the file besides its tags.
    struct Details: Equatable {
        var format = ""
        var bitrate = 0         // kbps
        var sampleRate = 0      // Hz
        var channels = 0
    }

    enum Failure: LocalizedError {
        case unreadable, readOnly, unsaved
        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "Legato can't read the tags of this file.")
            case .readOnly: String(localized: "The file can't be changed (it is read-only, or on a disk that is).")
            case .unsaved: String(localized: "Couldn't save the tags into the file.")
            }
        }
    }

    static func setUp() {
        taglib_set_strings_unicode(1)
        taglib_set_string_management_enabled(0)     // each string is freed here, so files can be read on any thread
    }

    // MARK: reading

    /// The track as the library shows it (id, file and cover are the caller's), or nil if TagLib can't read the file.
    static func track(at url: URL) -> Track? {
        guard let file = open(url) else { return nil }
        defer { taglib_file_free(file) }
        let props = properties(file)
        var track = Track(id: "", file: url.path)
        track.title = first(props, "TITLE")
        track.artist = first(props, "ARTIST")
        track.album = first(props, "ALBUM")
        track.albumArtist = first(props, "ALBUMARTIST")
        track.genre = first(props, "GENRE")
        track.year = leadingNumber(first(props, "DATE"))
        track.trackNumber = leadingNumber(first(props, "TRACKNUMBER"))
        track.discNumber = leadingNumber(first(props, "DISCNUMBER"))
        if let audio = taglib_file_audioproperties(file) {
            track.duration = Double(taglib_audioproperties_length(audio))
        }
        return track
    }

    /// The first picture in the file, as it is there (JPEG, PNG…).
    static func picture(at url: URL) -> Data? {
        guard let file = open(url) else { return nil }
        defer { taglib_file_free(file) }
        guard let props = taglib_complex_property_get(file, "PICTURE") else { return nil }
        defer { taglib_complex_property_free(props) }
        var picture = TagLib_Complex_Property_Picture_Data()
        taglib_picture_from_complex_property(props, &picture)
        guard let data = picture.data, picture.size > 0 else { return nil }
        return Data(bytes: data, count: Int(picture.size))
    }

    /// The edit window's fields, as the file has them: a number and its total apart ("3/12" → "3", "12").
    static func forEditing(_ url: URL) -> (tags: [Field: String], details: Details)? {
        guard let file = open(url) else { return nil }
        defer { taglib_file_free(file) }
        let props = properties(file)
        var tags: [Field: String] = [:]
        for (field, key) in editable { tags[field] = first(props, key) }
        for (number, total, key, totalKey) in [(Field.trackNumber, Field.trackTotal, "TRACKNUMBER", "TRACKTOTAL"),
                                               (.discNumber, .discTotal, "DISCNUMBER", "DISCTOTAL")] {
            let (n, t) = split(first(props, key))
            tags[number] = n == "0" ? "" : n         // ("0/10": a total written for a track with no number)
            tags[total] = t.isEmpty ? first(props, totalKey) : t     // (Vorbis comments keep the total apart)
        }
        var details = Details(format: url.pathExtension.uppercased())
        if let audio = taglib_file_audioproperties(file) {
            details.bitrate = Int(taglib_audioproperties_bitrate(audio))
            details.sampleRate = Int(taglib_audioproperties_samplerate(audio))
            details.channels = Int(taglib_audioproperties_channels(audio))
        }
        return (tags, details)
    }

    // MARK: writing

    /// Writes the fields given (an empty one removes the tag), leaving the file's other tags as they are.
    static func write(_ tags: [Field: String], to url: URL) throws {
        guard FileManager.default.isWritableFile(atPath: url.path) else { throw Failure.readOnly }
        guard let file = open(url) else { throw Failure.unreadable }
        defer { taglib_file_free(file) }
        var props = properties(file)
        var changed = Set<String>()
        func put(_ key: String, _ value: String?) {
            let v = value?.trimmingCharacters(in: .whitespaces) ?? ""
            props[key] = v.isEmpty ? nil : [v]
            changed.insert(key)
        }
        for (field, key) in editable {
            if let value = tags[field] { put(key, value) }
        }

        // numbers as "n/total", the form every format's readers understand; a separate total (Vorbis) goes, so it can't disagree. A
        // total with no number (set on tracks that have none) is kept on its own instead, where the format has a tag for that (else as
        // "0/total").
        var loneTotals: [(key: String, totalKey: String, total: String)] = []
        func numbers(_ key: String, _ totalKey: String, _ numberField: Field, _ totalField: Field) {
            guard tags[numberField] != nil || tags[totalField] != nil else { return }
            // a number or a total on its own (edited across several tracks at once) goes with the file's own other half
            let now = split(props[key]?.first ?? "")
            let nowTotal = now.total.isEmpty ? props[totalKey]?.first ?? "" : now.total
            let number = (tags[numberField] ?? now.number).trimmingCharacters(in: .whitespaces)
            let total = (tags[totalField] ?? nowTotal).trimmingCharacters(in: .whitespaces)
            put(key, number.isEmpty ? nil : total.isEmpty ? number : "\(number)/\(total)")
            put(totalKey, nil)
            if number.isEmpty && !total.isEmpty {
                put(totalKey, total)
                loneTotals.append((key, totalKey, total))
            }
        }
        numbers("TRACKNUMBER", "TRACKTOTAL", .trackNumber, .trackTotal)
        numbers("DISCNUMBER", "DISCTOTAL", .discNumber, .discTotal)
        // in MP4 the number field holds both: there a lone total is "0/total", which players show as no number of that many
        if ["m4a", "mp4", "m4b", "aac", "alac"].contains(url.pathExtension.lowercased()) {
            for lone in loneTotals {
                put(lone.totalKey, nil)
                put(lone.key, "0/\(lone.total)")
            }
        }

        for key in changed.sorted() {
            taglib_property_set(file, key, props[key]?.first)
        }
        guard taglib_file_save(file) != 0 else { throw Failure.unsaved }
    }

    // MARK: TagLib

    private typealias TagFile = UnsafeMutablePointer<TagLib_File>

    private static func open(_ url: URL) -> TagFile? {
        guard let file = url.withUnsafeFileSystemRepresentation({ $0.flatMap(taglib_file_new) }) else { return nil }
        guard taglib_file_is_valid(file) != 0 else {
            taglib_file_free(file)
            return nil
        }
        return file
    }

    private static func properties(_ file: TagFile) -> [String: [String]] {
        var out: [String: [String]] = [:]
        guard let keys = taglib_property_keys(file) else { return out }
        defer { taglib_property_free(keys) }
        var i = 0
        while let key = keys[i] {
            if let values = taglib_property_get(file, key) {
                var list: [String] = []
                var j = 0
                while let value = values[j] {
                    list.append(String(cString: value))
                    j += 1
                }
                taglib_property_free(values)
                out[String(cString: key)] = list
            }
            i += 1
        }
        return out
    }

    private static func first(_ props: [String: [String]], _ key: String) -> String {
        props[key]?.first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// "3/12" → ("3", "12")
    private static func split(_ value: String) -> (number: String, total: String) {
        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return (parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
                parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
    }

    /// "3/12" → 3, "2007-05-01" → 2007
    static func leadingNumber(_ value: String) -> Int {
        Int(value.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }) ?? 0
    }
}

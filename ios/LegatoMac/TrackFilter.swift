import Foundation

/// The search field's words, as Legato Desktop has them (qt/qml/components/TrackTable.qml): every word has to be in the title, artist,
/// album, genre or year (case and accents aside). A word can name the field it is for, with quotes around more than one word:
/// `album:"dark side" artist:floyd format:flac`. Quotes with nothing in them pick out the songs where that field is empty: `genre:""`.
struct TrackFilter {
    enum Field: String, CaseIterable {
        case title, artist, albumartist, album, genre, year, track, disc, format
    }

    struct Term: Equatable {
        var fields: [Field]         // any of these
        var text: String            // folded; "" (only with one field): that field is empty
    }

    let terms: [Term]

    private static let anywhere: [Field] = [.title, .artist, .albumartist, .album, .genre, .year]

    init(_ typed: String) {
        var terms: [Term] = []
        var rest = Substring(typed)
        while true {
            rest = rest.drop { $0.isWhitespace }
            guard !rest.isEmpty else { break }
            // an optional "field:", then "quoted words" or a word
            var name: Substring?
            if let colon = rest.firstIndex(of: ":"), rest[..<colon].allSatisfy(\.isLetter), colon > rest.startIndex {
                name = rest[..<colon]
                rest = rest[rest.index(after: colon)...]
            }
            var text: Substring
            var quoted = false
            if rest.first == "\"" {
                rest = rest.dropFirst()
                let close = rest.firstIndex(of: "\"") ?? rest.endIndex
                text = rest[..<close]
                quoted = close < rest.endIndex
                rest = close < rest.endIndex ? rest[rest.index(after: close)...] : rest[close...]
            } else {
                let end = rest.firstIndex { $0.isWhitespace } ?? rest.endIndex
                text = rest[..<end]
                rest = rest[end...]
            }
            let field = name.flatMap { Field(rawValue: $0.lowercased()) }
            if let field {
                if !text.isEmpty || quoted {        // ("album:" alone, still being typed, picks nothing out yet)
                    terms.append(Term(fields: field == .artist ? [.artist, .albumartist] : [field], text: Self.fold(String(text))))
                }
            } else {
                let word = (name.map { $0 + ":" } ?? "") + text
                if !word.isEmpty { terms.append(Term(fields: Self.anywhere, text: Self.fold(String(word)))) }
            }
        }
        self.terms = terms
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ track: Track) -> Bool {
        terms.allSatisfy { term in
            if term.text.isEmpty { return term.fields.allSatisfy { Self.value(of: $0, in: track).isEmpty } }
            return term.fields.contains { Self.fold(Self.value(of: $0, in: track)).contains(term.text) }
        }
    }

    func callAsFunction(_ tracks: [Track]) -> [Track] {
        isEmpty ? tracks : tracks.filter(matches)
    }

    static func value(of field: Field, in t: Track) -> String {
        switch field {
        case .title: t.title
        case .artist: t.artist
        case .albumartist: t.albumArtist
        case .album: t.album
        case .genre: t.genre
        case .year: t.year > 0 ? String(t.year) : ""
        case .track: t.trackNumber > 0 ? String(t.trackNumber) : ""
        case .disc: t.discNumber > 0 ? String(t.discNumber) : ""
        case .format: (t.file as NSString).pathExtension.lowercased()
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

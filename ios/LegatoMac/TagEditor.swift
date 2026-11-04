import SwiftUI

/// Get Info: a song's tags, or several songs' at once (a field they differ in shows "Mixed", and is left as each has it unless typed
/// into).
struct TagEditor: View {
    let tracks: [Track]
    @Environment(MusicFolders.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var values: [Tags.Field: String] = [:]
    @State private var mixed: Set<Tags.Field> = []
    @State private var edited: Set<Tags.Field> = []
    @State private var details: Tags.Details?
    @State private var problem: String?

    private static let labels: [(Tags.Field, LocalizedStringKey)] = [
        (.title, "Title"), (.artist, "Artist"), (.album, "Album"), (.albumArtist, "Album artist"), (.genre, "Genre"), (.date, "Year"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tracks.count == 1 ? tracks[0].displayTitle : String(localized: "\(tracks.count) songs"))
                .font(.headline)
            Form {
                ForEach(Self.labels, id: \.0) { field, label in
                    if field != .title || tracks.count == 1 {
                        TextField(label, text: binding(field), prompt: mixed.contains(field) ? Text("Mixed") : nil)
                    }
                }
                HStack {
                    if tracks.count == 1 {
                        TextField("Track", text: binding(.trackNumber))
                    }
                    TextField("of", text: binding(.trackTotal), prompt: mixed.contains(.trackTotal) ? Text("Mixed") : nil)
                }
                HStack {
                    TextField("Disc", text: binding(.discNumber), prompt: mixed.contains(.discNumber) ? Text("Mixed") : nil)
                    TextField("of", text: binding(.discTotal), prompt: mixed.contains(.discTotal) ? Text("Mixed") : nil)
                }
            }
            if let details, tracks.count == 1 {
                Text("\(details.format) · \(details.bitrate) kbps · \(details.sampleRate) Hz · \(details.channels == 1 ? String(localized: "mono") : details.channels == 2 ? String(localized: "stereo") : String(localized: "\(details.channels) channels"))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(tracks[0].file).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(edited.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { load() }
    }

    private func binding(_ field: Tags.Field) -> Binding<String> {
        Binding(get: { values[field] ?? "" }, set: {
            values[field] = $0
            edited.insert(field)
        })
    }

    private func load() {
        let read = tracks.compactMap { Tags.forEditing(library.url(for: $0)) }
        guard let first = read.first else {
            problem = Tags.Failure.unreadable.localizedDescription
            return
        }
        details = first.details
        for field in Tags.Field.allCases {
            let all = Set(read.map { $0.tags[field] ?? "" })
            if all.count == 1 { values[field] = all.first } else { mixed.insert(field) }
        }
    }

    private func save() {
        let changes = Dictionary(uniqueKeysWithValues: edited.map { ($0, values[$0] ?? "") })
        if let failed = library.writeTags(changes, to: tracks) {
            problem = failed
        } else {
            dismiss()
        }
    }
}

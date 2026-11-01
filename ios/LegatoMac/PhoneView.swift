import SwiftUI

/// A phone's page: what goes on it, how big that is, and how its last sync went. The phone starts a sync (Sync with Mac, in Legato on
/// it); this Mac answers. The playlists, artists and albums to tick are one table, which the search field narrows, as Legato Desktop's.
struct PhoneView: View {
    let id: String
    var forgotten: () -> Void
    @Environment(Phones.self) private var phones
    @Environment(MusicFolders.self) private var library

    @State private var search = ""

    /// A playlist, artist or album that can be ticked.
    private struct Pick: Identifiable {
        enum Kind: Int { case playlist, artist, album }
        var kind: Kind
        var value: String           // what goes in Chosen: the name, or the album's id
        var name: String
        var detail: String
        var id: String { "\(kind.rawValue):\(value)" }

        var list: WritableKeyPath<Chosen, [String]> {
            switch kind { case .playlist: \.playlists; case .artist: \.artists; case .album: \.albums }
        }
        var kindName: String {
            switch kind {
            case .playlist: String(localized: "Playlist")
            case .artist: String(localized: "Artist")
            case .album: String(localized: "Album")
            }
        }
    }

    var body: some View {
        if let phone = phones.phone(id) {
            let shown = picks.filter(matches)
            VStack(spacing: 0) {
                header(phone)
                Divider()
                Table(shown) {
                    TableColumn("") { pick in
                        Toggle("", isOn: member(pick.list, pick.value, of: phone)).labelsHidden()
                    }
                    .width(24)
                    TableColumn("Name") { pick in Text(pick.name) }
                    TableColumn("Kind") { pick in Text(pick.kindName).foregroundStyle(.secondary) }
                        .width(min: 60, ideal: 70, max: 100)
                    TableColumn("Details") { pick in Text(pick.detail).foregroundStyle(.secondary) }
                }
                .disabled(phone.chosen.everything)
                .opacity(phone.chosen.everything ? 0.5 : 1)
                .overlay { if shown.isEmpty && !search.isEmpty { ContentUnavailableView.search(text: search) } }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Playlists, artists and albums")
            .navigationTitle(phone.name)
            .navigationSubtitle(summary(phone.chosen))
        }
    }

    @ViewBuilder private func header(_ phone: Phones.Phone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last synced: \(phone.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Never"))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Forget This Phone", role: .destructive) {
                    phones.forget(id)
                    forgotten()
                }
            }
            if let a = phones.activity[id] {
                ProgressView(value: Double(a.done), total: Double(max(a.total, 1))) {
                    Text("Syncing: \(a.what)")
                }
            }
            if phone.refused {
                Text("This Mac doesn't sync with this phone. To pair it again, forget it here, then choose Sync with Mac on the phone.")
                    .foregroundStyle(.secondary)
            } else if let code = phone.code {
                HStack {
                    Text("Code: \(code)").font(.title3.monospacedDigit())
                    Button("Allow This Phone") { phones.allow(id) }
                }
            } else {
                Text("To sync, open Legato on the phone and choose Sync with Mac.")
                    .foregroundStyle(.secondary)
            }
            Toggle("All the music", isOn: Binding(get: { phone.chosen.everything }, set: { all in
                choose { $0.everything = all }
            }))
            .toggleStyle(.checkbox)
        }
        .padding()
    }

    private var picks: [Pick] {
        library.playlists.map { Pick(kind: .playlist, value: $0.name, name: $0.name, detail: songs(library.tracks(of: $0).count)) }
        + library.artists.map { Pick(kind: .artist, value: $0.name, name: $0.name, detail: songs($0.tracks.count)) }
        + library.albums.map {
            Pick(kind: .album, value: $0.id, name: $0.title.isEmpty ? String(localized: "Unknown Album") : $0.title, detail: $0.artist)
        }
    }

    private func matches(_ pick: Pick) -> Bool {
        search.split(whereSeparator: \.isWhitespace).allSatisfy { word in
            pick.name.localizedStandardContains(word) || pick.detail.localizedStandardContains(word)
                || pick.kindName.localizedStandardContains(word)
        }
    }

    private func songs(_ n: Int) -> String { n == 1 ? String(localized: "1 song") : String(localized: "\(n) songs") }

    private func choose(_ change: (inout Chosen) -> Void) {
        guard var chosen = phones.phone(id)?.chosen else { return }
        change(&chosen)
        phones.choose(chosen, for: id)
    }

    private func member(_ list: WritableKeyPath<Chosen, [String]>, _ item: String, of phone: Phones.Phone) -> Binding<Bool> {
        Binding(get: { phone.chosen[keyPath: list].contains(item) }, set: { on in
            choose { chosen in
                chosen[keyPath: list].removeAll { $0 == item }
                if on { chosen[keyPath: list].append(item) }
            }
        })
    }

    private func summary(_ chosen: Chosen) -> String {
        let (manifest, _) = SyncServer.manifest(of: library, for: chosen, source: "")
        let bytes = manifest.tracks.reduce(Int64(0)) { $0 + $1.size }
        return String(localized: "\(manifest.tracks.count) songs, \(bytes.formatted(.byteCount(style: .file)))")
    }
}

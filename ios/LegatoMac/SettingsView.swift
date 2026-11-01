import AppKit
import SwiftUI

/// Settings (⌘,): the folders the music is in.
struct SettingsView: View {
    @Environment(MusicFolders.self) private var library
    @State private var chosen: MusicFolders.Folder.ID?
    @State private var choosingFolder = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    List(library.folders, selection: $chosen) { folder in
                        HStack {
                            Image(systemName: folder.url == nil ? "folder.badge.questionmark" : "folder")
                                .foregroundStyle(folder.url == nil ? .secondary : .primary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.name)
                                Text(folder.url.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? String(localized: "Not there now"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                if folder.url != nil && !folder.writable {
                                    Text("Read only: Legato can't change tags or playlists here")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if let url = folder.url, !folder.writable {
                                Button("Allow Changes…") { allowChanges(url) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds()
                    .frame(minHeight: 160)
                    .overlay {
                        if library.folders.isEmpty {
                            Text("No folders yet").foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 0) {
                        Button("Add Folder", systemImage: "plus") { choosingFolder = true }
                        Divider().frame(height: 16)
                        Button("Remove Folder", systemImage: "minus") {
                            if let folder = library.folders.first(where: { $0.id == chosen }) { library.remove(folder) }
                            chosen = nil
                        }
                        .disabled(chosen == nil)
                        Spacer()
                        if library.scanning {
                            ProgressView().controlSize(.small).padding(.trailing, 6)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(height: 22)
                    .padding(.horizontal, 4)
                }
            } header: {
                Text("Music Folders")
            } footer: {
                Text("Legato shows the music in these folders and their subfolders, and keeps up with changes to them. Playlists are the .m3u8 files in them.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(library.add) }
        }
    }

    /// The open panel at the folder: choosing it again gives Legato leave to change it (the sandbox only grants that to a choice).
    private func allowChanges(_ url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.message = String(localized: "Choose “\(url.lastPathComponent)” to let Legato change the tags and playlists in it.")
        panel.prompt = String(localized: "Allow Changes")
        if panel.runModal() == .OK, let chosen = panel.url { library.add(chosen) }
    }
}

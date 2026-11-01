import SwiftUI

/// Legato for Mac: the library in the music folders, played with the same Player as the iPhone and watch, and synced to phones over
/// Wi-Fi.
@main
struct LegatoMacApp: App {
    @State private var library: MusicFolders
    @State private var player: Player
    @State private var phones: Phones
    private let server: SyncServer

    init() {
        let library = MusicFolders()
        let phones = Phones()
        _library = State(initialValue: library)
        _player = State(initialValue: Player(library: library))
        _phones = State(initialValue: phones)
        server = SyncServer(library: library, phones: phones)
    }

    var body: some Scene {
        Window("Legato", id: "library") {
            LibraryWindow()
                .environment(library)
                .environment(player)
                .environment(phones)
                .frame(minWidth: 980, minHeight: 520)
                .task { await server.start() }
        }
        .commands { SongCommands(library: library) }
        Settings {
            SettingsView()
                .environment(library)
        }
    }
}

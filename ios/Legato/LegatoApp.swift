import SwiftUI

@main
struct LegatoApp: App {
    @State private var library: LibraryStore
    @State private var player: Player
    @State private var watch: WatchSender
    @Environment(\.scenePhase) private var phase

    init() {
        let library = LibraryStore()
        _library = State(initialValue: library)
        _player = State(initialValue: Player(library: library))
        _watch = State(initialValue: WatchSender(library: library))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(watch)
                // Legato Desktop may sync while the app is open: look at the manifest now and then (it is only read when it changed)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        if phase == .active { library.reload() }
                    }
                }
                .onChange(of: phase) { _, phase in
                    if phase == .active { library.reload() }
                }
        }
    }
}

import Observation
import SwiftUI

/// Where you can go from the track list: an album's, an artist's or a playlist's tracks (long-press a track), or a page from the
/// cog menu.
enum Route: Hashable {
    case album(String)       // Album.id
    case artist(String)      // artist name, lowercased
    case playlist(String)    // playlist name
    case settings
    case equaliser
    case watchSync
}

/// The navigation stack's path, so a long-press menu deep in a list can open an album or an artist.
@MainActor
@Observable
final class Navigator {
    var path: [Route] = []
    func go(_ route: Route) { path.append(route) }
}

/// Two tabs, Music (every track, searchable) and Playlists, each with its own stack of pages. The mini player sits above the tab bar
/// whenever something is loaded.
struct RootView: View {
    var body: some View {
        TabView {
            Stack { HomeView() }
                .withMiniPlayer()
                .tabItem { Label("Music", systemImage: "music.note") }
            Stack { PlaylistsView() }
                .withMiniPlayer()
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
        }
    }
}

/// A tab's stack: its own path (so each tab keeps its place), and everywhere a long-press or the cog menu can lead.
private struct Stack<Root: View>: View {
    @ViewBuilder var root: Root
    @State private var navigator = Navigator()

    var body: some View {
        NavigationStack(path: $navigator.path) {
            root
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .album(let key): AlbumView(key: key)
                    case .artist(let name): ArtistView(name: name)
                    case .playlist(let name): PlaylistView(name: name)
                    case .settings: SettingsView()
                    case .equaliser: EqualiserView()
                    case .watchSync: WatchView()
                    }
                }
        }
        .environment(navigator)
    }
}

/// The cog at the top right of each tab: Settings, Equaliser and Watch Sync.
private struct AppMenu: ViewModifier {
    @Environment(Navigator.self) private var navigator

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { navigator.go(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                    Button { navigator.go(.equaliser) } label: { Label("Equaliser", systemImage: "slider.vertical.3") }
                    Button { navigator.go(.watchSync) } label: { Label("Watch Sync", systemImage: "applewatch") }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Menu")
            }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(Player.self) private var player
    @State private var showingNowPlaying = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if player.current != nil {
                    MiniPlayer { showingNowPlaying = true }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            }
            .sheet(isPresented: $showingNowPlaying) { NowPlayingView() }
    }
}

extension View {
    func withMiniPlayer() -> some View { modifier(MiniPlayerInset()) }
    func withAppMenu() -> some View { modifier(AppMenu()) }
}

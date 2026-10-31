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
                .tabItem { Label("Music", systemImage: "music.note") }
            Stack { PlaylistsView() }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
        }
    }
}

/// A tab's stack: its own path (so each tab keeps its place), and everywhere a long-press or the cog menu can lead. Each page in it
/// makes room for the mini player itself: a list only keeps its last rows clear of an inset that is on the page, not on the stack.
private struct Stack<Root: View>: View {
    @ViewBuilder var root: Root
    @State private var navigator = Navigator()
    @State private var showingNowPlaying = false

    var body: some View {
        NavigationStack(path: $navigator.path) {
            root
                .withMiniPlayer { showingNowPlaying = true }
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .album(let key): AlbumView(key: key)
                        case .artist(let name): ArtistView(name: name)
                        case .playlist(let name): PlaylistView(name: name)
                        case .settings: SettingsView()
                        case .equaliser: EqualiserView()
                        case .watchSync: WatchView()
                        }
                    }
                    .withMiniPlayer { showingNowPlaying = true }
                }
        }
        .environment(navigator)
        .sheet(isPresented: $showingNowPlaying) { NowPlayingView() }
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

/// The mini player at the foot of a page, above the tab bar, whenever something is loaded; the page's lists end above it.
private struct MiniPlayerInset: ViewModifier {
    var open: () -> Void
    @Environment(Player.self) private var player

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 10) {     // (and a little room between the last row and it)
                if player.current != nil {
                    MiniPlayer(open: open)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            }
    }
}

extension View {
    func withMiniPlayer(open: @escaping () -> Void) -> some View { modifier(MiniPlayerInset(open: open)) }
    func withAppMenu() -> some View { modifier(AppMenu()) }
}

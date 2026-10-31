import CarPlay
import UIKit

/// Legato in the car: Apple's CarPlay templates, filled from the same library and player as the phone's screens. Two tabs, Music
/// (shuffle everything, or go by album, artist or song) and Playlists; choosing a song plays its list from there and shows Now Playing.
///
/// CarPlay only shows an app Apple has given the CarPlay audio entitlement (`com.apple.developer.carplay-audio`). Until then it is in
/// the simulator's builds only (project.yml): Simulator › I/O › External Displays › CarPlay shows it.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CPInterfaceController?
    private let music = CPListTemplate(title: String(localized: "Music"), sections: [])
    private let playlists = CPListTemplate(title: String(localized: "Playlists"), sections: [])

    private var library: LibraryStore { AppModel.shared.library }
    private var player: Player { AppModel.shared.player }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        music.tabImage = UIImage(systemName: "music.note")
        playlists.tabImage = UIImage(systemName: "music.note.list")
        for list in [music, playlists] {
            list.emptyViewTitleVariants = [String(localized: "No Music Yet")]
            list.emptyViewSubtitleVariants = [String(localized: "Sync your iPhone from Legato on your computer.")]
        }
        setUpNowPlaying()
        fill()
        followLibrary()
        interfaceController.setRootTemplate(CPTabBarTemplate(templates: [music, playlists]), animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        interface = nil
    }

    // MARK: the tabs

    private func fill() {
        let tracks = library.tracksInAlbumOrder
        music.updateSections(tracks.isEmpty ? [] : [CPListSection(items: [
            row(String(localized: "Shuffle All"), image: UIImage(systemName: "shuffle")) { [unowned self] in
                player.shufflePlay(tracks)
                showNowPlaying()
            },
            row(String(localized: "Albums"), image: UIImage(systemName: "square.stack"), more: true) { [unowned self] in push(albums()) },
            row(String(localized: "Artists"), image: UIImage(systemName: "music.mic"), more: true) { [unowned self] in push(artists()) },
            row(String(localized: "Songs"), image: UIImage(systemName: "music.note"), more: true) { [unowned self] in
                push(songs(String(localized: "Songs"), library.songsByTitle))
            },
        ])])
        playlists.updateSections([CPListSection(items: fitted(library.playlists).map { p in
            let tracks = library.tracks(of: p)
            let item = row(p.name, detail: count(tracks.count), more: true) { [unowned self] in push(songs(p.name, tracks)) }
            cover(tracks.first?.cover, into: item)
            return item
        })])
    }

    /// The lists follow the library: a sync, or a playlist changed on the phone.
    private func followLibrary() {
        withObservationTracking {
            _ = library.tracks
            _ = library.playlists
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.interface != nil else { return }
                self.fill()
                self.followLibrary()
            }
        }
    }

    // MARK: lists

    private func albums() -> CPListTemplate {
        CPListTemplate(title: String(localized: "Albums"), sections: [CPListSection(items: fitted(library.albums).map { album in
            let item = row(album.title.isEmpty ? String(localized: "Unknown Album") : album.title, detail: album.artist, more: true) { [unowned self] in
                push(songs(album.title, album.tracks))
            }
            cover(album.cover, into: item)
            return item
        })])
    }

    private func artists() -> CPListTemplate {
        CPListTemplate(title: String(localized: "Artists"), sections: [CPListSection(items: fitted(library.artists).map { artist in
            let item = row(artist.name, detail: count(artist.tracks.count), more: true) { [unowned self] in
                push(songs(artist.name, artist.tracks))
            }
            cover(artist.albums.first?.cover, into: item)
            return item
        })])
    }

    /// A list of songs, Shuffle first: choosing one plays the whole list from it.
    private func songs(_ title: String, _ tracks: [Track]) -> CPListTemplate {
        var items: [CPListItem] = [
            row(String(localized: "Shuffle"), image: UIImage(systemName: "shuffle")) { [unowned self] in
                player.shufflePlay(tracks)
                showNowPlaying()
            },
        ]
        for (index, track) in tracks.prefix(max(0, CPListTemplate.maximumItemCount - 1)).enumerated() {
            let item = row(track.displayTitle, detail: track.artist) { [unowned self] in
                player.shuffle = false
                player.play(tracks, from: index)
                showNowPlaying()
            }
            item.isPlaying = player.current?.id == track.id
            cover(track.cover, into: item)
            items.append(item)
        }
        return CPListTemplate(title: title, sections: [CPListSection(items: items)])
    }

    // MARK: Now Playing (drawn by CarPlay from what the player tells the system; these are its extra buttons)

    private func setUpNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = false
        nowPlaying.isAlbumArtistButtonEnabled = false
        nowPlaying.updateNowPlayingButtons([
            CPNowPlayingShuffleButton { [weak self] _ in Task { @MainActor in self?.player.shuffle.toggle() } },
            CPNowPlayingRepeatButton { [weak self] _ in Task { @MainActor in self?.player.cycleRepeat() } },
        ])
    }

    private func showNowPlaying() {
        guard let interface, !(interface.topTemplate is CPNowPlayingTemplate) else { return }
        interface.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: pieces

    private func row(_ text: String, detail: String? = nil, image: UIImage? = nil, more: Bool = false,
                     action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: text, detailText: detail, image: image)
        if more { item.accessoryType = .disclosureIndicator }
        item.handler = { _, done in
            action()
            done()
        }
        return item
    }

    private func push(_ template: CPTemplate) {
        interface?.pushTemplate(template, animated: true, completion: nil)
    }

    /// as many as CarPlay will show in a list while driving
    private func fitted<T>(_ items: [T]) -> [T] { Array(items.prefix(CPListTemplate.maximumItemCount)) }

    private func count(_ n: Int) -> String { n == 1 ? String(localized: "1 song") : String(localized: "\(n) songs") }

    private func cover(_ path: String?, into item: CPListItem) {
        guard let url = library.coverURL(path) else { return }
        let size = CPListItem.maximumImageSize
        Task { item.setImage(await CoverCache.shared.image(url, size: max(size.width, size.height) * 3)) }
    }
}

/// The app's shared pieces, made once: the phone's screens and CarPlay play from the same library and player.
@MainActor
final class AppModel {
    static let shared = AppModel()
    let library: LibraryStore
    let player: Player
    let watch: WatchSender

    private init() {
        library = LibraryStore()
        player = Player(library: library)
        watch = WatchSender(library: library)
    }
}

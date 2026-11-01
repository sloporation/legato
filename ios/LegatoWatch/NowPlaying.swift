import SwiftUI
import WatchKit

/// What's playing, with the controls. Legato's own rather than WatchKit's NowPlayingView: that one works out from the system whether
/// it's playing, and shows Play while a song that has just started plays. This one asks the player. The crown is the volume, as there.
struct WatchNowPlaying: View {
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                WatchCover(path: player.current?.cover)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.current?.displayTitle ?? "").font(.headline).lineLimit(2)
                    Text(player.current?.artist ?? "").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: min(player.position, player.duration), total: max(player.duration, 1))
                .tint(.white)
            if let problem = player.problem {
                Text(problem).font(.footnote).foregroundStyle(.red).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack {
                control("Previous", "backward.fill") { player.previous() }
                control(player.isPlaying ? "Pause" : "Play", player.isPlaying ? "pause.fill" : "play.fill", font: .title2) { player.toggle() }
                control("Next", "forward.fill") { player.next() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(player.current == nil)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .topTrailing) {
            // the crown turns the volume while this is on screen (and shows its own indicator); it takes no room
            VolumeControl().frame(width: 1, height: 1).opacity(0.01)
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A round button of a fixed size: play and pause are different heights, and the row mustn't move when one becomes the other.
    private func control(_ name: LocalizedStringKey, _ symbol: String, font: Font = .body, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel(Text(name))
    }
}

/// WatchKit's volume control: the Digital Crown sets the volume of what's playing here.
private struct VolumeControl: WKInterfaceObjectRepresentable {
    func makeWKInterfaceObject(context: Context) -> WKInterfaceVolumeControl {
        WKInterfaceVolumeControl(origin: .local)
    }
    func updateWKInterfaceObject(_ control: WKInterfaceVolumeControl, context: Context) {}
}

/// A cover from the watch's Covers folder.
private struct WatchCover: View {
    let path: String?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let url = library.coverURL(path), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.gray.opacity(0.3))
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
    }
}

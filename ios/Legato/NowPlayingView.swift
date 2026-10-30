import AVKit
import SwiftUI

/// The bar above the tab bar: what's playing, play/pause and next. Tapping it opens Now Playing.
struct MiniPlayer: View {
    var open: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(path: player.current?.cover, size: 96).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.displayTitle ?? "").font(.subheadline.weight(.medium)).lineLimit(1)
                Text(player.current?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3) }
                .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// Now Playing: the cover, where it is in the track, the controls, shuffle and repeat, and where the sound goes (AirPlay).
struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @State private var scrubbing: Double?

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 24) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 8)
            CoverImage(path: player.current?.cover, size: 900)
                .aspectRatio(1, contentMode: .fit)
                .shadow(radius: 12, y: 6)
                .scaleEffect(player.isPlaying ? 1 : 0.85)
                .animation(.spring(duration: 0.4), value: player.isPlaying)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.displayTitle ?? "").font(.title3.bold()).lineLimit(1)
                Text(player.current?.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
                if let problem = player.problem { Text(problem).font(.caption).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // a file that doesn't say how long it is can't be skipped through
            VStack(spacing: 4) {
                Slider(value: Binding(get: { scrubbing ?? player.position }, set: { scrubbing = $0 }),
                       in: 0...max(1, player.duration)) { editing in
                    if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
                }
                .disabled(player.duration <= 0)
                HStack {
                    Text(time(scrubbing ?? player.position))
                    Spacer()
                    Text(player.duration > 0 ? "-" + time(player.duration - (scrubbing ?? player.position)) : "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous")
                Spacer()
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44)) }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next")
                Spacer()
            }
            .font(.system(size: 30))
            .buttonStyle(.plain)

            HStack {
                Button { player.shuffle.toggle() } label: {
                    Image(systemName: "shuffle").foregroundStyle(player.shuffle ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .accessibilityLabel(player.shuffle ? "Shuffle is on" : "Shuffle")
                Spacer()
                AirPlayButton().frame(width: 32, height: 32)
                Spacer()
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .accessibilityLabel(player.repeatMode == .one ? "Repeating this song" : player.repeatMode == .all ? "Repeating" : "Repeat")
            }
            .font(.title3)
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .presentationDragIndicator(.hidden)
    }

    private func time(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

/// The system's AirPlay and Bluetooth picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

import AVFoundation
import XCTest

/// Which formats AVFoundation plays on iOS, without making a sound: each fixture (a 2-second tone) has to load to "ready to play" with
/// the right length. Legato Desktop copies these formats as they are; anything that fails here needs converting during sync.
final class FormatTests: XCTestCase {
    private func readyToPlay(_ name: String) async throws -> Double? {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tone", withExtension: name))
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        for _ in 0..<50 {
            if item.status == .readyToPlay { return item.duration.seconds }
            if item.status == .failed { return nil }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func testMP3() async throws { let d = try await readyToPlay("mp3"); XCTAssertEqual(d ?? 0, 2, accuracy: 0.2) }
    func testAAC() async throws { let d = try await readyToPlay("m4a"); XCTAssertEqual(d ?? 0, 2, accuracy: 0.2) }
    func testFLAC() async throws { let d = try await readyToPlay("flac"); XCTAssertEqual(d ?? 0, 2, accuracy: 0.2) }
    func testWAV() async throws { let d = try await readyToPlay("wav"); XCTAssertEqual(d ?? 0, 2, accuracy: 0.2) }
    func testOggOpus() async throws { let d = try await readyToPlay("opus"); XCTAssertEqual(d ?? 0, 2, accuracy: 0.2) }
    /// iOS doesn't play WebM, so Legato Desktop repackages its Opus audio as .opus (no re-encoding) when it syncs. If this starts
    /// failing, iOS has learnt WebM and the repackaging can go.
    func testWebMIsNotPlayable() async throws { let d = try await readyToPlay("webm"); XCTAssertNil(d) }
}

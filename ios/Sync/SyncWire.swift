import Foundation
import Tether

/// Legato for Mac ↔ Legato for iPhone over Wi-Fi (docs/sync.md). Tether finds the Mac (Bonjour, `_legato._tcp`), pairs the phone with
/// it once (both show a code) and opens an encrypted connection; these are what the phone and the Mac say over it. A reply that says
/// `size` is followed by that many bytes of a file.
enum SyncWire {
    static let configuration = TetherConfiguration(serviceType: "_legato._tcp", label: "legato")

    /// The phone's question.
    struct Request: Codable {
        enum Op: String, Codable { case hello, file, done }
        var op: Op
        // hello
        var chosen: Chosen?             // what the phone's manifest says was chosen for it last
        var batch: String?              // its playlist changes: this lot's name, and
        var changes: [PlaylistChange]?  // them
        // file
        var path: String?               // "Music/<id>.<ext>" or "Covers/<hash>.jpg", from the manifest
        // done
        var copied: Int?
    }

    /// The Mac's answer.
    struct Reply: Codable {
        var ok: Bool
        var why: String?
        var manifest: Manifest?         // hello: what the phone is to have
        var size: Int64?                // file: this many bytes follow
    }
}

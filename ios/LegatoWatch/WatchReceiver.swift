import Foundation
import WatchConnectivity

/// Takes the music the iPhone sends (docs/sync.md): track and cover files go into `Documents/Legato/`, the manifest replaces the old
/// one, and files it no longer names are deleted. Afterwards it tells the iPhone what it has, so nothing is sent twice.
final class WatchReceiver: NSObject, WCSessionDelegate {
    private let root: URL
    private let changed: @MainActor () -> Void
    private let session = WCSession.default

    init(root: URL, changed: @escaping @MainActor () -> Void) {
        self.root = root
        self.changed = changed
        super.init()
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated { reportWhatWeHave() }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // the file is deleted when this returns: move it now
        let fm = FileManager.default
        let kind = file.metadata?["kind"] as? String
        do {
            switch kind {
            case "track", "cover":
                guard let relative = file.metadata?["file"] as? String, Self.isSafe(relative) else { return }
                let destination = root.appending(path: relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: file.fileURL, to: destination)
            case "manifest":
                let data = try Data(contentsOf: file.fileURL)
                let manifest = try Manifest.decode(data)
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                try data.write(to: root.appending(path: "manifest.json"), options: .atomic)
                prune(keeping: manifest)
            default:
                return
            }
        } catch {
            NSLog("legato: couldn't take %@ from the iPhone: %@", file.fileURL.lastPathComponent, error.localizedDescription)
        }
        Task { @MainActor in self.changed() }
        if kind == "manifest" { reportWhatWeHave() }
    }

    /// Deletes the tracks and covers the manifest doesn't name (music taken off the watch).
    private func prune(keeping manifest: Manifest) {
        let wanted = Set(manifest.tracks.map(\.file) + manifest.tracks.compactMap(\.cover))
        let fm = FileManager.default
        for folder in ["Music", "Covers"] {
            let dir = root.appending(path: folder)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !wanted.contains("\(folder)/\(name)") {
                try? fm.removeItem(at: dir.appending(path: name))
            }
        }
    }

    /// `{"have": [track ids]}`: the files in Music/ are named by track id.
    private func reportWhatWeHave() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Music").path)) ?? []
        let ids = names.map { ($0 as NSString).deletingPathExtension }
        session.transferUserInfo(["have": ids])
    }

    /// Only into our own folder: no "..", no absolute paths.
    private static func isSafe(_ relative: String) -> Bool {
        !relative.hasPrefix("/") && !relative.split(separator: "/").contains("..")
    }
}

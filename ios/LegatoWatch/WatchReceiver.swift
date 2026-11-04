import Foundation
import WatchConnectivity

/// Takes the music the iPhone sends (docs/sync.md): track and cover files go into `Documents/Legato/`, the manifest replaces the old
/// one, and files it no longer names are deleted. Afterwards it tells the iPhone what it has, so nothing is sent twice. It also hands
/// the iPhone's messages, and whether it's in reach, to the remote.
final class WatchReceiver: NSObject, WCSessionDelegate {
    private let root: URL
    private let changed: @MainActor () -> Void
    private let remote: PhoneRemote
    private let session = WCSession.default
    private let reports = DispatchQueue(label: "legato.watch.reports")
    private var report: DispatchWorkItem?

    init(root: URL, remote: PhoneRemote, changed: @escaping @MainActor () -> Void) {
        self.root = root
        self.remote = remote
        self.changed = changed
        super.init()
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        NSLog("legato watch sync: session %d, error %@", state.rawValue, error.map { String(describing: $0) } ?? "none")
        if state == .activated { reportWhatWeHave() }
        Task { @MainActor in self.remote.reachabilityChanged() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.remote.reachabilityChanged() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.remote.received(message) }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // the file is deleted when this returns: move it now
        let fm = FileManager.default
        let kind = file.metadata?["kind"] as? String
        NSLog("legato watch sync: got %@ %@", kind ?? "?", file.metadata?["file"] as? String ?? file.fileURL.lastPathComponent)
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
                UserDefaults.standard.set(file.metadata?["id"] as? String, forKey: "manifest.id")
            default:
                return
            }
        } catch {
            NSLog("legato: couldn't take %@ from the iPhone: %@", file.fileURL.lastPathComponent, error.localizedDescription)
        }
        Task { @MainActor in self.changed() }
        reportSoon()
    }

    /// Tells the iPhone what's here once the files stop arriving for a moment (they come in any order, the manifest among them).
    private func reportSoon() {
        reports.async {
            self.report?.cancel()
            let work = DispatchWorkItem { self.reportWhatWeHave() }
            self.report = work
            self.reports.asyncAfter(deadline: .now() + 2, execute: work)
        }
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

    /// `{"have": [track ids], "manifest": "<id>"}`: the files in Music/ are named by track id; the manifest's id says which sync
    /// this is the result of.
    private func reportWhatWeHave() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Music").path)) ?? []
        let ids = names.map { ($0 as NSString).deletingPathExtension }
        var info: [String: Any] = ["have": ids]
        if let manifest = UserDefaults.standard.string(forKey: "manifest.id") { info["manifest"] = manifest }
        for old in session.outstandingUserInfoTransfers where old.userInfo["have"] != nil { old.cancel() }     // (only the latest matters)
        session.transferUserInfo(info)
        NSLog("legato watch sync: told the iPhone we have %d tracks", ids.count)
    }

    /// Only into our own folder: no "..", no absolute paths.
    private static func isSafe(_ relative: String) -> Bool {
        !relative.hasPrefix("/") && !relative.split(separator: "/").contains("..")
    }
}

import CoreServices
import Foundation

/// Notices changes anywhere in the music folders (FSEvents, which watches a whole tree), and says so once things settle.
@MainActor
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var roots: [URL] = []
    private var settle: Task<Void, Never>?
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
    }

    func watch(_ roots: [URL]) {
        guard roots != self.roots else { return }
        stop()
        self.roots = roots
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.noticed() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, roots.map(\.path) as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        settle?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        roots = []
    }

    /// (a copy of a whole album is many events: wait for a quiet second)
    private func noticed() {
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { changed() }
        }
    }
}

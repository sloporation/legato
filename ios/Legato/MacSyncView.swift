import SwiftUI
import Tether
import UIKit

/// Sync with Mac (from the cog menu): finds Legato for Mac on this network and fetches the music chosen for this phone there. The
/// first time, the phone pairs: it and the Mac show the same code, and the Mac asks whether to allow it. Tether does the finding,
/// pairing and connecting (docs/sync.md).
@MainActor
@Observable
final class MacSync {
    enum State: Equatable {
        case idle
        case pairing(mac: String, code: String)     // waiting for the Mac to allow this phone
        case syncing(String)
        case done(String)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var done: Int64 = 0
    private(set) var total: Int64 = 0
    private(set) var what = ""
    private var task: Task<Void, Never>?
    private let library: LibraryStore
    private let client = TetherClient(configuration: SyncWire.configuration, name: UIDevice.current.name)

    init(library: LibraryStore) {
        self.library = library
    }

    /// The Macs running Legato on this network now, by name.
    var macs: [TetherClient.Host] { client.discovered.sorted { $0.name < $1.name } }
    var problem: String? { client.problem }

    var busy: Bool {
        switch state {
        case .pairing, .syncing: true
        default: false
        }
    }

    func look() { client.startBrowsing() }

    func stop() {
        client.stopBrowsing()
        task?.cancel()          // (a pairing hangs up: the Mac stops asking)
        if busy { state = .idle }
    }

    func sync(with mac: TetherClient.Host) {
        task?.cancel()
        state = .syncing(String(localized: "Connecting to \(mac.name)"))
        done = 0
        total = 0
        task = Task {
            do {
                if client.isPaired(mac.id) {
                    do {
                        try await sync(with: mac)
                        return
                    } catch TetherError.unpaired {
                        // the Mac forgot this phone (Tether has forgotten it here too): pair again
                    }
                }
                try await client.pair(with: mac) { code in self.state = .pairing(mac: mac.name, code: code) }
                state = .syncing(String(localized: "Connecting to \(mac.name)"))
                try await sync(with: mac)
            } catch is CancellationError {
            } catch {
                library.reload(force: true)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func sync(with mac: TetherClient.Host) async throws {
        let session = try await client.connect(to: mac)
        defer { session.close() }
        let sync = SyncClient(root: library.root) { done, total, what in
            Task { @MainActor in
                self.done = done
                self.total = total
                self.what = what
                self.state = .syncing(what)
            }
        }
        let outcome = try await sync.sync(session)
        library.reload(force: true)
        if case .synced(let copied, let removed) = outcome {
            state = .done(copied == 0 && removed == 0 ? String(localized: "Up to date.")
                          : String(localized: "\(copied) songs copied, \(removed) removed."))
        }
    }
}

struct MacSyncView: View {
    @Environment(LibraryStore.self) private var library
    @State private var sync: MacSync?

    var body: some View {
        List {
            if let sync {
                Section {
                    if let problem = sync.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else if sync.macs.isEmpty {
                        Label("Looking for Legato on your Mac…", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sync.macs) { mac in
                        Button {
                            sync.sync(with: mac)
                        } label: {
                            Label("Sync with \(mac.name)", systemImage: "laptopcomputer")
                        }
                        .disabled(sync.busy)
                    }
                } footer: {
                    Text("Open Legato on your Mac, on the same Wi-Fi. What goes on this phone is chosen there, under Phones; playlist changes made here go back to it.")
                }
                status(sync)
            }
        }
        .navigationTitle("Sync with Mac")
        .onAppear {
            if sync == nil { sync = MacSync(library: library) }
            sync?.look()
        }
        .onDisappear { sync?.stop() }
    }

    @ViewBuilder private func status(_ sync: MacSync) -> some View {
        switch sync.state {
        case .idle:
            EmptyView()
        case .pairing(let mac, let code):
            Section {
                VStack(spacing: 8) {
                    Text(code).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Check that Legato on \(mac) shows this code, then click Allow there.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("If the codes are different, click Don't Allow: something else on this network is pretending to be one of them.")
            }
        case .syncing(let what):
            Section {
                ProgressView(value: Double(sync.done), total: Double(max(sync.total, 1))) {
                    Text(what).lineLimit(1)
                }
            } footer: {
                Text("Keep Legato open until it's done.")
            }
        case .done(let message):
            Section { Label(message, systemImage: "checkmark.circle") }
        case .failed(let message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        }
    }
}

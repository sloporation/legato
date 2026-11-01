import CryptoKit
import Network
import SwiftUI
import UIKit

/// Sync with Mac (from the cog menu): finds Legato for Mac on this network and fetches the music chosen for this phone there. The
/// first time, the phone pairs: it and the Mac show the same code, and the Mac asks whether to allow it. (docs/sync.md)
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

    struct Mac: Identifiable, Hashable {
        var id: String              // its id, from the Bonjour TXT record
        var name: String
        var endpoint: NWEndpoint
    }

    private(set) var macs: [Mac] = []
    private(set) var state = State.idle
    private(set) var done: Int64 = 0
    private(set) var total: Int64 = 0
    private(set) var what = ""
    private var browser: NWBrowser?
    private var task: Task<Void, Never>?
    private let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    var busy: Bool {
        switch state {
        case .pairing, .syncing: true
        default: false
        }
    }

    func look() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Wire.service, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Mac? in
                guard case .service(let name, _, _, _) = result.endpoint, case .bonjour(let txt) = result.metadata,
                      let id = txt["mac"] else { return nil }
                return Mac(id: id, name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.macs = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        task?.cancel()
        if busy { state = .idle }
    }

    func sync(with mac: Mac) {
        task?.cancel()
        state = .syncing(String(localized: "Connecting to \(mac.name)"))
        done = 0
        total = 0
        task = Task {
            do {
                if let key = Self.keys[mac.id] {
                    do {
                        try await sync(with: mac, key: key)
                        return
                    } catch let error where Self.unpaired(error) {
                        Self.keys[mac.id] = nil     // (the Mac forgot this phone: pair again)
                    }
                }
                let key = try await pair(with: mac)
                state = .syncing(String(localized: "Connecting to \(mac.name)"))
                try await sync(with: mac, key: key)
            } catch is CancellationError {
            } catch {
                library.reload(force: true)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func pair(with mac: Mac) async throws -> SymmetricKey {
        let wire = WireConnection(NWConnection(to: mac.endpoint, using: Wire.pairingParameters()))
        defer { wire.cancel() }
        try await wire.start()
        let paired = try await withTaskCancellationHandler {
            try await SyncClient.pair(wire, as: Self.identity) { code in
                Task { @MainActor in self.state = .pairing(mac: mac.name, code: code) }
            }
        } onCancel: {
            wire.cancel()       // (the page was closed: the Mac stops asking)
        }
        Self.keys[paired.mac] = paired.key
        return paired.key
    }

    private func sync(with mac: Mac, key: SymmetricKey) async throws {
        let identity = Self.identity
        let wire = WireConnection(NWConnection(to: mac.endpoint, using: Wire.phoneParameters(identity: identity.phone, key: key)))
        defer { wire.cancel() }
        try await wire.start()
        let client = SyncClient(root: library.root, identity: identity, key: key) { done, total, what in
            Task { @MainActor in
                self.done = done
                self.total = total
                self.what = what
                self.state = .syncing(what)
            }
        }
        let outcome = try await client.sync(wire)
        library.reload(force: true)
        if case .synced(let copied, let removed) = outcome {
            state = .done(copied == 0 && removed == 0 ? String(localized: "Up to date.")
                          : String(localized: "\(copied) songs copied, \(removed) removed."))
        }
    }

    /// The Mac doesn't know this phone's key (forgotten there): TLS fails, or the hello says so.
    private static func unpaired(_ error: Error) -> Bool {
        if case SyncClient.Failure.unpaired = error { return true }
        if case NWError.tls = error { return true }
        return false
    }

    /// The keys agreed with the Macs this phone has paired with: Mac id → key.
    private static var keys: [String: SymmetricKey] {
        get {
            let saved = UserDefaults.standard.dictionary(forKey: "mac.keys") as? [String: Data] ?? [:]
            return saved.mapValues { SymmetricKey(data: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.mapValues(\.data), forKey: "mac.keys")
        }
    }

    /// Who this phone is to the Mac: made once and kept.
    private static var identity: SyncClient.Identity {
        let key = "mac.identity"
        if let data = UserDefaults.standard.data(forKey: key), var id = try? JSONDecoder().decode(SyncClient.Identity.self, from: data) {
            id.name = UIDevice.current.name
            return id
        }
        let id = SyncClient.Identity(phone: UUID().uuidString, name: UIDevice.current.name)
        UserDefaults.standard.set(try? JSONEncoder().encode(id), forKey: key)
        return id
    }
}

struct MacSyncView: View {
    @Environment(LibraryStore.self) private var library
    @State private var sync: MacSync?

    var body: some View {
        List {
            if let sync {
                Section {
                    if sync.macs.isEmpty {
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

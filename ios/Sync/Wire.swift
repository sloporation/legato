import CryptoKit
import Foundation
import Network

/// Legato for Mac ↔ Legato for iPhone over Wi-Fi (docs/sync.md): the Mac advertises `_legato._tcp` with Bonjour (its id in the TXT
/// record), the phone connects over TLS with the key they agreed when the phone was paired. Each message is a 4-byte big-endian length,
/// that much JSON, and, when the JSON says `size`, that many bytes of a file after it. The Mac speaks first, with a challenge.
enum Wire {
    static let service = "_legato._tcp"
    /// The TLS identity (and key, which isn't a secret) of a phone pairing: the pairing is made safe by the code both show, not by TLS.
    static let pairingIdentity = "legato-pairing"
    private static let pairingKey = SymmetricKey(data: Data("legato-pairing-0000000000000000".utf8))

    /// The phone's question.
    struct Request: Codable {
        enum Op: String, Codable { case pair, hello, file, done }
        var op: Op
        // pair, hello
        var phone: String?              // the phone's id (made once, kept on it)
        var name: String?               // "Jacob's iPhone"
        // pair: first the hash of the phone's half of the key agreement (Curve25519), then, once the Mac has sent its half, the half
        var commitment: Data?
        var key: Data?
        // hello
        var proof: Data?                // HMAC of the challenge with this phone's key: which phone this is
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
        var challenge: Data?            // first, on every connection: random bytes for the hello's proof
        var waiting: Bool?              // pair: the Mac is asking whether to allow the phone; its answer follows (ok, or not)
        var mac: String?                // pair: the Mac's id
        var key: Data?                  // pair: the Mac's half of the key agreement
        var why: String?
        var unpaired: Bool?             // hello: the Mac doesn't know this phone (or its key) now; pair again
        var manifest: Manifest?         // hello: what the phone is to have
        var size: Int64?                // file: this many bytes follow
    }

    enum Failure: LocalizedError {
        case closed, tooBig
        var errorDescription: String? {
            switch self {
            case .closed: String(localized: "The connection to the Mac was lost.")
            case .tooBig: String(localized: "The Mac sent something Legato didn't understand.")
            }
        }
    }

    /// TLS 1.2 with a pre-shared key and an ephemeral key exchange on top (so a key found later can't open syncs recorded before):
    /// the phone with its own key, or the pairing one.
    static func phoneParameters(identity: String, key: SymmetricKey) -> NWParameters {
        tls(keys: [(identity, key)])
    }

    static func pairingParameters() -> NWParameters { tls(keys: [(pairingIdentity, pairingKey)]) }

    /// The Mac's: every allowed phone's key, and the pairing one.
    static func macParameters(keys: [(identity: String, key: SymmetricKey)]) -> NWParameters {
        tls(keys: [(pairingIdentity, pairingKey)] + keys)
    }

    private static func tls(keys: [(String, SymmetricKey)]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let o = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(o, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(o, .TLSv12)       // (PSK with Network.framework is 1.2)
        sec_protocol_options_append_tls_ciphersuite(o, tls_ciphersuite_t(rawValue: UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256))!)
        for (identity, key) in keys {
            sec_protocol_options_add_pre_shared_key(o, dispatchData(key.withUnsafeBytes { Data($0) }), dispatchData(Data(identity.utf8)))
        }
        let parameters = NWParameters(tls: tls)
        parameters.includePeerToPeer = false
        return parameters
    }

    private static func dispatchData(_ data: Data) -> __DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// One end of a connection, with async sends and receives.
final class WireConnection: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "legato.wire")

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Starts the connection and waits until it can be used.
    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let once = Once(c)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume()
                case .failed(let error): once.resume(throwing: error)
                case .cancelled: once.resume(throwing: Wire.Failure.closed)
                case .waiting(let error): once.resume(throwing: error)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    func cancel() { connection.cancel() }

    func send<T: Encodable>(_ message: T) async throws {
        let json = try Wire.encoder.encode(message)
        var length = UInt32(json.count).bigEndian
        try await send(Data(bytes: &length, count: 4) + json)
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }

    func receive<T: Decodable>(_ type: T.Type) async throws -> T {
        let header = try await receive(exactly: 4)
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length < 64 << 20 else { throw Wire.Failure.tooBig }
        return try Wire.decoder.decode(T.self, from: try await receive(exactly: length))
    }

    func receive(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { c.resume(throwing: error) } else if let data, data.count == count { c.resume(returning: data) } else { c.resume(throwing: Wire.Failure.closed) }
            }
        }
    }

    /// Receives `size` bytes into a file, a piece at a time.
    func receiveFile(size: Int64, to url: URL, progress: (Int64) -> Void = { _ in }) async throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var got: Int64 = 0
        while got < size {
            let piece = try await receive(upTo: Int(min(size - got, 1 << 20)))
            try handle.write(contentsOf: piece)
            got += Int64(piece.count)
            progress(got)
        }
    }

    private func receive(upTo count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: count) { data, _, _, error in
                if let error { c.resume(throwing: error) } else if let data, !data.isEmpty { c.resume(returning: data) } else { c.resume(throwing: Wire.Failure.closed) }
            }
        }
    }
}

/// A continuation resumed at most once (the state handler goes on being called).
private final class Once: @unchecked Sendable {
    private var c: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    init(_ c: CheckedContinuation<Void, Error>) { self.c = c }
    func resume(throwing error: Error? = nil) {
        lock.lock()
        let c = self.c
        self.c = nil
        lock.unlock()
        if let error { c?.resume(throwing: error) } else { c?.resume() }
    }
}

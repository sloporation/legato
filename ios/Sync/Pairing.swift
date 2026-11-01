import CryptoKit
import Foundation

/// Pairing a phone with a Mac (docs/sync.md): each sends the other its half of a Curve25519 key agreement, and both work out the same
/// key for TLS and the same six-digit code. The person checks the code on the phone is the one on the Mac before allowing it there, so
/// nobody between them on the network can have put their own halves in. The phone sends a hash of its half before it sees the Mac's,
/// and the half itself after: someone in the middle has to choose theirs before seeing the other, so can't search for halves that
/// happen to give the same code on both (one in a million).
enum Pairing {
    struct Agreed {
        var key: SymmetricKey
        var code: String            // "482 913"
    }

    /// The key and code from this side's private half and the other's public one. `phoneKey` and `macKey` are the two public halves,
    /// in that order whichever side this is.
    static func agree(_ mine: Curve25519.KeyAgreement.PrivateKey, with theirs: Data, phoneKey: Data, macKey: Data) throws -> Agreed {
        let shared = try mine.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs))
        let salt = phoneKey + macKey
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("legato sync key".utf8), outputByteCount: 32)
        let digits = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("legato pairing code".utf8), outputByteCount: 4)
            .withUnsafeBytes { $0.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } } % 1_000_000
        let code = String(format: "%06u", digits)
        return Agreed(key: key, code: code.prefix(3) + " " + code.suffix(3))
    }

    /// The hello's proof that it comes from this phone: the Mac's challenge and the phone's id, signed with the phone's key.
    static func proof(challenge: Data, phone: String, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: challenge + Data(phone.utf8), using: key))
    }

    static func check(_ proof: Data, challenge: Data, phone: String, key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: challenge + Data(phone.utf8), using: key)
    }

    static func commitment(to key: Data) -> Data { Data(SHA256.hash(data: key)) }

    static func challenge() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}

extension SymmetricKey {
    var data: Data { withUnsafeBytes { Data($0) } }
}

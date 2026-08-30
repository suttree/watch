import CryptoKit
import Foundation

public enum PasswordProtectedSecretStoreError: Error, LocalizedError, Equatable {
    case locked
    case incorrectPassword
    case corruptedStore
    case alreadyHasPassword

    public var errorDescription: String? {
        switch self {
        case .locked:
            "Read is locked."
        case .incorrectPassword:
            "That password is incorrect."
        case .corruptedStore:
            "The saved data file is corrupted."
        case .alreadyHasPassword:
            "A password has already been set."
        }
    }
}

/// Stores the Anthropic API key in a local encrypted file protected by a
/// password the user chooses, instead of the macOS Keychain. A Keychain item
/// added by an ad-hoc-signed debug build gets challenged for authorization
/// on every launch, since the app's code identity isn't stable across
/// rebuilds — this sidesteps that entirely by managing its own key
/// derivation, the same trade-off Fork's identity store makes. There is no
/// password recovery: losing the password means losing access to the key
/// encrypted with it.
public final class PasswordProtectedSecretStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private var derivedKey: SymmetricKey?

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public var hasStoredPassword: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    public var isUnlocked: Bool {
        derivedKey != nil
    }

    public func createPassword(_ password: String) throws {
        guard !hasStoredPassword else {
            throw PasswordProtectedSecretStoreError.alreadyHasPassword
        }

        let salt = randomBytes(count: 16)
        let key = Self.deriveKey(password: password, salt: salt)
        let verification = try AES.GCM.seal(Self.verificationPlaintext, using: key).combined!
        derivedKey = key
        try save(Container(salt: salt, verification: verification, encryptedSecret: nil))
    }

    public func unlock(password: String) throws {
        let container = try loadContainer()
        let key = Self.deriveKey(password: password, salt: container.salt)

        guard let sealedVerification = try? AES.GCM.SealedBox(combined: container.verification),
              let opened = try? AES.GCM.open(sealedVerification, using: key),
              opened == Self.verificationPlaintext
        else {
            throw PasswordProtectedSecretStoreError.incorrectPassword
        }

        derivedKey = key
    }

    /// Drops the in-memory decryption key so the secret can't be read again
    /// without the password, without touching the encrypted file on disk.
    public func lock() {
        derivedKey = nil
    }

    public func loadSecret() throws -> String? {
        guard let derivedKey else {
            throw PasswordProtectedSecretStoreError.locked
        }
        let container = try loadContainer()
        guard let encrypted = container.encryptedSecret else {
            return nil
        }
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let data = try AES.GCM.open(sealedBox, using: derivedKey)
        return String(data: data, encoding: .utf8)
    }

    public func saveSecret(_ secret: String) throws {
        guard let derivedKey else {
            throw PasswordProtectedSecretStoreError.locked
        }
        var container = try loadContainer()
        if secret.isEmpty {
            container.encryptedSecret = nil
        } else {
            let sealedBox = try AES.GCM.seal(Data(secret.utf8), using: derivedKey)
            container.encryptedSecret = sealedBox.combined!
        }
        try save(container)
    }

    private func randomBytes(count: Int) -> Data {
        Data(SymmetricKey(size: .init(bitCount: count * 8)).withUnsafeBytes { Array($0) })
    }

    private static let verificationPlaintext = Data("read-password-verification".utf8)

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: passwordKey,
            salt: salt,
            info: Data("app.read.secret.password".utf8),
            outputByteCount: 32
        )
    }

    private struct Container: Codable {
        var salt: Data
        var verification: Data
        var encryptedSecret: Data?
    }

    private func loadContainer() throws -> Container {
        guard let data = fileManager.contents(atPath: fileURL.path) else {
            throw PasswordProtectedSecretStoreError.corruptedStore
        }
        do {
            return try JSONDecoder().decode(Container.self, from: data)
        } catch {
            throw PasswordProtectedSecretStoreError.corruptedStore
        }
    }

    private func save(_ container: Container) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(container)
        try data.write(to: fileURL, options: [.atomic])
    }
}

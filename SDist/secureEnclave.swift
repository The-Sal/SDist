//
//  secureEnclave.swift
//  SDist
//
//  Secure Enclave encryption implementation for macOS
//  Uses hybrid encryption: SE-backed key wrapping + AES-256-GCM
//

#if os(macOS)

import Foundation
import CryptoKit
import LocalAuthentication

// MARK: - Constants

private let MAGIC_HEADER: [UInt8] = [0x53, 0x44, 0x49, 0x53, 0x54, 0x2E, 0x53, 0x45] // "SDIST.SE"
private let FORMAT_VERSION: UInt16 = 1
private let GCM_NONCE_SIZE = 12
private let GCM_TAG_SIZE = 16
private let INTEGRITY_HASH_SIZE = 32

// MARK: - Errors

enum SEEncryptionError: Error, CustomStringConvertible {
    case fileReadError(String)
    case fileWriteError(String)
    case keyGenerationFailed(String)
    case keyNotFound(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidFileFormat(String)
    case integrityCheckFailed
    case authenticationFailed(String)
    case unsupportedVersion(UInt16)

    var description: String {
        switch self {
        case .fileReadError(let msg): return "File read error: \(msg)"
        case .fileWriteError(let msg): return "File write error: \(msg)"
        case .keyGenerationFailed(let msg): return "Key generation failed: \(msg)"
        case .keyNotFound(let msg): return "SE key not found: \(msg)"
        case .encryptionFailed(let msg): return "Encryption failed: \(msg)"
        case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
        case .invalidFileFormat(let msg): return "Invalid file format: \(msg)"
        case .integrityCheckFailed: return "Integrity check failed - file may be corrupted or tampered"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .unsupportedVersion(let ver): return "Unsupported file version: \(ver)"
        }
    }
}

// MARK: - Metadata Structure

private struct SEFileMetadata: Codable {
    let version: Int
    let seKeyID: String
    let seKeyLabel: String
    let algorithm: String
    let keyEncryptionAlgorithm: String
    let nonce: String // Base64-encoded
    let timestamp: Int
    let originalFilename: String?
    let reserved: [String: String]

    init(seKeyID: String, seKeyLabel: String, nonce: Data, originalFilename: String? = nil) {
        self.version = 1
        self.seKeyID = seKeyID
        self.seKeyLabel = seKeyLabel
        self.algorithm = "AES-256-GCM"
        self.keyEncryptionAlgorithm = "ECIES-P256"
        self.nonce = nonce.base64EncodedString()
        self.timestamp = Int(Date().timeIntervalSince1970)
        self.originalFilename = originalFilename
        self.reserved = [:]
    }
}

// MARK: - Secure Enclave Key Management

private class SEKeyManager {

    static func getOrCreateKey(label: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        // Try to retrieve existing key
        if let existingKey = try? retrieveKey(label: label) {
            print("Using existing Secure Enclave key: \(label)")
            return existingKey
        }

        // Create new key
        print("Creating new Secure Enclave key: \(label)")
        return try createKey(label: label)
    }

    static func createKey(label: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        do {
            // Generate key in Secure Enclave
            // Note: Using simplified API without explicit access control for compatibility
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey()

            // Store key reference in keychain
            try storeKeyReference(key: key, label: label)

            return key
        } catch {
            throw SEEncryptionError.keyGenerationFailed(error.localizedDescription)
        }
    }

    static func retrieveKey(label: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: label,
            kSecAttrService as String: "SDist-SE-Keys",
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let keyData = item as? Data else {
            throw SEEncryptionError.keyNotFound("Key with label '\(label)' not found in keychain")
        }

        do {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyData)
        } catch {
            throw SEEncryptionError.keyNotFound("Failed to reconstruct key from keychain: \(error.localizedDescription)")
        }
    }

    private static func storeKeyReference(key: SecureEnclave.P256.KeyAgreement.PrivateKey, label: String) throws {
        let keyData = key.dataRepresentation

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: label,
            kSecAttrService as String: "SDist-SE-Keys",
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw SEEncryptionError.keyGenerationFailed("Failed to store key reference: \(status)")
        }
    }
}

// MARK: - Binary Writer Helper

private class BinaryWriter {
    private var data = Data()

    func write(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    func writeUInt16BigEndian(_ value: UInt16) {
        data.append(contentsOf: [
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    func writeUInt32BigEndian(_ value: UInt32) {
        data.append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    func writeData(_ data: Data) {
        self.data.append(data)
    }

    func getData() -> Data {
        return data
    }
}

// MARK: - Binary Reader Helper

private class BinaryReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else {
            throw SEEncryptionError.invalidFileFormat("Unexpected end of file")
        }
        let bytes = Array(data[offset..<(offset + count)])
        offset += count
        return bytes
    }

    func readUInt16BigEndian() throws -> UInt16 {
        let bytes = try readBytes(2)
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    func readUInt32BigEndian() throws -> UInt32 {
        let bytes = try readBytes(4)
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
               (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    func readData(_ count: Int) throws -> Data {
        guard offset + count <= data.count else {
            throw SEEncryptionError.invalidFileFormat("Unexpected end of file")
        }
        let result = data.subdata(in: offset..<(offset + count))
        offset += count
        return result
    }

    func readRemainingData() -> Data {
        return data.subdata(in: offset..<data.count)
    }

    func getCurrentOffset() -> Int {
        return offset
    }

    func getDataUpToCurrentOffset() -> Data {
        return data.subdata(in: 0..<offset)
    }
}

// MARK: - Public Encryption Function

func se_encrypt(_ inputFile: String, outputFile: String, keyLabel: String? = nil) {
    do {
        // Clean paths
        let cleanInputFile = inputFile.trimmingCharacters(in: .whitespaces)
        let cleanOutputFile = outputFile.trimmingCharacters(in: .whitespaces)

        print("Starting Secure Enclave encryption...")
        print("Input: \(cleanInputFile)")
        print("Output: \(cleanOutputFile)")

        // Read input file
        guard let fileData = FileManager.default.contents(atPath: cleanInputFile) else {
            throw SEEncryptionError.fileReadError("Cannot read file: \(cleanInputFile)")
        }

        let originalFilename = URL(fileURLWithPath: cleanInputFile).lastPathComponent

        // Generate or retrieve SE key
        let label = keyLabel ?? "SDist-SE-Key-Default"
        let sePrivateKey = try SEKeyManager.getOrCreateKey(label: label)
        let sePublicKey = sePrivateKey.publicKey

        // Generate random AES-256 key
        let aesKey = SymmetricKey(size: .bits256)

        // Generate random nonce for GCM
        var nonceBytes = [UInt8](repeating: 0, count: GCM_NONCE_SIZE)
        guard SecRandomCopyBytes(kSecRandomDefault, GCM_NONCE_SIZE, &nonceBytes) == errSecSuccess else {
            throw SEEncryptionError.encryptionFailed("Failed to generate random nonce")
        }
        let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))

        // Encrypt file data with AES-GCM
        print("Encrypting file content with AES-256-GCM...")
        let sealedBox = try AES.GCM.seal(fileData, using: aesKey, nonce: nonce)

        guard let encryptedContent = sealedBox.combined else {
            throw SEEncryptionError.encryptionFailed("Failed to get encrypted content")
        }

        // Extract raw AES key data
        let aesKeyData = aesKey.withUnsafeBytes { Data($0) }

        // Encrypt AES key with SE public key using key agreement (ECIES-like)
        // For actual ECIES, we'll use a simple approach: generate ephemeral key and do ECDH
        let ephemeralKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: sePublicKey)

        // Derive encryption key from shared secret
        let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "SDist-SE-Key-Wrap".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Encrypt AES key with derived wrap key
        let wrappedKeyBox = try AES.GCM.seal(aesKeyData, using: wrapKey)
        guard var encryptedAESKey = wrappedKeyBox.combined else {
            throw SEEncryptionError.encryptionFailed("Failed to wrap AES key")
        }

        // Prepend ephemeral public key to encrypted key (needed for decryption)
        let ephemeralPublicKeyData = ephemeralKey.publicKey.rawRepresentation
        encryptedAESKey = ephemeralPublicKeyData + encryptedAESKey

        // Zero out sensitive key material
        // Note: Swift's memory safety makes this challenging, but we can help GC
        var zeroedKey = aesKeyData
        _ = zeroedKey.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0, ptr.count)
        }

        // Build metadata
        let keyID = "sdist.se.\(label).\(UUID().uuidString)"
        let metadata = SEFileMetadata(
            seKeyID: keyID,
            seKeyLabel: label,
            nonce: Data(nonceBytes),
            originalFilename: originalFilename
        )

        let encoder = JSONEncoder()
        let metadataJSON = try encoder.encode(metadata)

        // Build binary file
        let writer = BinaryWriter()

        // Write magic header
        writer.write(MAGIC_HEADER)

        // Write version
        writer.writeUInt16BigEndian(FORMAT_VERSION)

        // Write metadata length and data
        writer.writeUInt32BigEndian(UInt32(metadataJSON.count))
        writer.writeData(metadataJSON)

        // Write encrypted AES key length and data
        writer.writeUInt32BigEndian(UInt32(encryptedAESKey.count))
        writer.writeData(encryptedAESKey)

        // Calculate and write integrity marker (SHA-256 of everything so far)
        let integrityData = writer.getData()
        let integrityHash = SHA256.hash(data: integrityData)
        writer.writeData(Data(integrityHash))

        // Write encrypted content (ciphertext + tag)
        writer.writeData(encryptedContent)

        // Write to output file
        let finalData = writer.getData()
        do {
            try finalData.write(to: URL(fileURLWithPath: cleanOutputFile))
            print("✓ Encryption successful!")
            print("  Output file size: \(finalData.count) bytes")
            print("  Original size: \(fileData.count) bytes")
            print("  Overhead: \(finalData.count - fileData.count) bytes")
            print("  SE Key: \(label)")
        } catch {
            throw SEEncryptionError.fileWriteError(error.localizedDescription)
        }

    } catch let error as SEEncryptionError {
        print("❌ SE Encryption Error: \(error.description)")
    } catch {
        print("❌ Unexpected error: \(error.localizedDescription)")
    }
}

// MARK: - Public Decryption Function

func se_decrypt(_ inputFile: String, outputFile: String) {
    do {
        // Clean paths
        let cleanInputFile = inputFile.trimmingCharacters(in: .whitespaces)
        let cleanOutputFile = outputFile.trimmingCharacters(in: .whitespaces)

        print("Starting Secure Enclave decryption...")
        print("Input: \(cleanInputFile)")
        print("Output: \(cleanOutputFile)")

        // Read encrypted file
        guard let fileData = FileManager.default.contents(atPath: cleanInputFile) else {
            throw SEEncryptionError.fileReadError("Cannot read file: \(cleanInputFile)")
        }

        let reader = BinaryReader(data: fileData)

        // Read and verify magic header
        let magic = try reader.readBytes(8)
        guard magic == MAGIC_HEADER else {
            throw SEEncryptionError.invalidFileFormat("Invalid magic header - not a Secure Enclave encrypted file")
        }

        // Read and check version
        let version = try reader.readUInt16BigEndian()
        guard version == FORMAT_VERSION else {
            throw SEEncryptionError.unsupportedVersion(version)
        }

        // Read metadata
        let metadataLength = try reader.readUInt32BigEndian()
        let metadataJSON = try reader.readData(Int(metadataLength))

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(SEFileMetadata.self, from: metadataJSON)

        print("File metadata:")
        print("  Encrypted: \(Date(timeIntervalSince1970: TimeInterval(metadata.timestamp)))")
        if let filename = metadata.originalFilename {
            print("  Original filename: \(filename)")
        }
        print("  SE Key: \(metadata.seKeyLabel)")

        // Read encrypted AES key
        let encryptedKeyLength = try reader.readUInt32BigEndian()
        let encryptedAESKeyFull = try reader.readData(Int(encryptedKeyLength))

        // Verify integrity marker
        let integrityMarker = try reader.readData(INTEGRITY_HASH_SIZE)
        let dataToVerify = reader.getDataUpToCurrentOffset().subdata(in: 0..<(reader.getCurrentOffset() - INTEGRITY_HASH_SIZE))
        let calculatedHash = SHA256.hash(data: dataToVerify)

        guard Data(calculatedHash) == integrityMarker else {
            throw SEEncryptionError.integrityCheckFailed
        }
        print("✓ Integrity check passed")

        // Read encrypted content (rest of file)
        let encryptedContent = reader.readRemainingData()

        // Retrieve SE private key
        print("Requesting Secure Enclave key access...")
        print("(You may be prompted for Touch ID / Face ID)")

        let sePrivateKey = try SEKeyManager.getOrCreateKey(label: metadata.seKeyLabel)

        // Split ephemeral public key and encrypted AES key
        guard encryptedAESKeyFull.count > 65 else {
            throw SEEncryptionError.decryptionFailed("Invalid encrypted key format")
        }

        let ephemeralPublicKeyData = encryptedAESKeyFull.prefix(65) // 65 bytes for P256 public key
        let wrappedKey = encryptedAESKeyFull.suffix(from: 65)

        // Reconstruct ephemeral public key
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyData)

        // Perform key agreement to get shared secret
        let sharedSecret = try sePrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        // Derive the same wrap key
        let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "SDist-SE-Key-Wrap".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Decrypt AES key
        print("Unwrapping AES key...")
        let sealedBox = try AES.GCM.SealedBox(combined: wrappedKey)
        let aesKeyData = try AES.GCM.open(sealedBox, using: wrapKey)
        let aesKey = SymmetricKey(data: aesKeyData)

        // Decrypt file content
        print("Decrypting file content...")
        let contentSealedBox = try AES.GCM.SealedBox(combined: encryptedContent)
        let decryptedData = try AES.GCM.open(contentSealedBox, using: aesKey)

        // Write decrypted file
        do {
            try decryptedData.write(to: URL(fileURLWithPath: cleanOutputFile))
            print("✓ Decryption successful!")
            print("  Output file size: \(decryptedData.count) bytes")
        } catch {
            throw SEEncryptionError.fileWriteError(error.localizedDescription)
        }

        // Zero out sensitive data
        var zeroedKey = aesKeyData
        _ = zeroedKey.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0, ptr.count)
        }

    } catch let error as SEEncryptionError {
        print("❌ SE Decryption Error: \(error.description)")
    } catch {
        print("❌ Unexpected error: \(error.localizedDescription)")
    }
}

// MARK: - Key Management Functions

func se_list_keys() {
    print("Listing Secure Enclave keys in keychain...")

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SDist-SE-Keys",
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true
    ]

    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)

    guard status == errSecSuccess, let keyItems = items as? [[String: Any]] else {
        print("No SE keys found in keychain")
        return
    }

    print("Found \(keyItems.count) key(s):")
    for (index, item) in keyItems.enumerated() {
        let label = item[kSecAttrAccount as String] as? String ?? "Unknown"
        print("  \(index + 1). \(label)")
    }
}

#endif // os(macOS)

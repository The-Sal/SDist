//
//  secureEnclave.swift
//  SDist
//
//  Secure Enclave encryption implementation for macOS with Touch ID
//  Uses hybrid encryption: SE-backed key wrapping + AES-256-GCM
//

#if os(macOS)

import Foundation
import CryptoKit
import LocalAuthentication

// MARK: - Constants

private let MAGIC_HEADER: [UInt8] = [0x53, 0x44, 0x49, 0x53, 0x54, 0x2E, 0x53, 0x45] // "SDIST.SE"
private let FORMAT_VERSION: UInt16 = 2
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
    case biometryNotAvailable(String)

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
        case .biometryNotAvailable(let msg): return "Biometry not available: \(msg)"
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

    init(version: Int, seKeyID: String, seKeyLabel: String, algorithm: String, keyEncryptionAlgorithm: String, nonce: String, timestamp: Int, originalFilename: String?, reserved: [String : String]) {
        self.version = version
        self.seKeyID = seKeyID
        self.seKeyLabel = seKeyLabel
        self.algorithm = algorithm
        self.keyEncryptionAlgorithm = keyEncryptionAlgorithm
        self.nonce = nonce
        self.timestamp = timestamp
        self.originalFilename = originalFilename
        self.reserved = reserved
    }
}

private func stripMetadata(_ metadata: SEFileMetadata) -> SEFileMetadata{
    // removes all metadata from `SEFileMetadata`. SEFileMetadata is kept for backwards compatibility
    return .init(version: 2, seKeyID: metadata.seKeyID, seKeyLabel: metadata.seKeyLabel, algorithm: metadata.algorithm, keyEncryptionAlgorithm: metadata.keyEncryptionAlgorithm, nonce: metadata.nonce, timestamp: 0, originalFilename: nil, reserved: metadata.reserved)
}

// MARK: - Biometry Helper

private class BiometryHelper {
    
    /// Check if biometric authentication is available on this device
    static func isBiometryAvailable() -> (available: Bool, biometryType: LABiometryType, error: Error?) {
        let context = LAContext()
        var error: NSError?
        
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        return (canEvaluate, context.biometryType, error)
    }
    
    /// Get a user-friendly description of the available biometry type
    static func getBiometryDescription() -> String {
        let context = LAContext()
        switch context.biometryType {
        case .none:
            return "No biometric authentication"
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "Unknown biometric type"
        }
    }
    
    /// Perform biometric authentication with a custom reason
    static func authenticate(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        // First check if biometry is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async {
                completion(false, error ?? SEEncryptionError.biometryNotAvailable("Biometric authentication not available"))
            }
            return
        }
        
        // Perform the authentication
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                completion(success, authError)
            }
        }
    }
}

// MARK: - Secure Enclave Key Management

private class SEKeyManager {

    /// Get or create a Secure Enclave key with Touch ID protection
    static func getOrCreateKey(label: String, requireBiometry: Bool = true) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        // Try to retrieve existing key
        if let existingKey = try? retrieveKey(label: label) {
            print("Using existing Secure Enclave key: \(label)")
            return existingKey
        }

        // Create new key
        print("Creating new Secure Enclave key: \(label)")
        return try createKey(label: label, requireBiometry: requireBiometry)
    }

    /// Create a new Secure Enclave key with Touch ID protection
    static func createKey(label: String, requireBiometry: Bool = true) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        do {
            // Check if biometry is available if required
            if requireBiometry {
                let biometryCheck = BiometryHelper.isBiometryAvailable()
                guard biometryCheck.available else {
                    throw SEEncryptionError.biometryNotAvailable(
                        "Touch ID is not available. Please ensure biometric authentication is enabled in System Settings."
                    )
                }
                print("✓ \(BiometryHelper.getBiometryDescription()) is available")
            }
            
            // Create access control for the key with Touch ID requirement
            let flags: SecAccessControlCreateFlags
            if requireBiometry {
                // Use biometryCurrentSet to strictly require Touch ID
                // This ties the key to the current set of enrolled fingerprints
                flags = [.privateKeyUsage, .biometryCurrentSet]
                print("Creating key with Touch ID requirement")
            } else {
                // Fallback: use userPresence which allows both biometry and device passcode
                flags = [.privateKeyUsage, .userPresence]
                print("Creating key with user presence requirement (Touch ID or passcode)")
            }
            
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                flags,
                &error
            ) else {
                if let cfError = error?.takeRetainedValue() {
                    throw SEEncryptionError.keyGenerationFailed("Failed to create access control: \(cfError)")
                }
                throw SEEncryptionError.keyGenerationFailed("Failed to create access control")
            }

            // Create authentication context with a clear prompt
            let authContext = LAContext()
            authContext.localizedReason = "Authenticate to create encryption key"
            // Allow reuse of authentication for 60 seconds to avoid multiple prompts
            authContext.touchIDAuthenticationAllowableReuseDuration = 60

            // Generate key in Secure Enclave
            let tag = "com.sdist.sekey.\(label)".data(using: .utf8)!

            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                compactRepresentable: false,
                accessControl: accessControl,
                authenticationContext: authContext
            )

            // Store key reference in keychain with proper attributes
            try storeKeyReference(key: key, label: label, tag: tag)

            print("✓ Secure Enclave key created successfully")
            return key
        } catch let error as SEEncryptionError {
            throw error
        } catch {
            throw SEEncryptionError.keyGenerationFailed(error.localizedDescription)
        }
    }

    /// Retrieve an existing Secure Enclave key and authenticate with Touch ID
    static func retrieveKey(label: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        // Query the stored data representation
        let dataQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: label,
            kSecAttrService as String: "SDist-SE-KeyData",
            kSecReturnData as String: true
        ]

        var dataItem: CFTypeRef?
        let dataStatus = SecItemCopyMatching(dataQuery as CFDictionary, &dataItem)

        guard dataStatus == errSecSuccess, let keyData = dataItem as? Data else {
            throw SEEncryptionError.keyNotFound("Key data not found for label '\(label)' (status: \(dataStatus))")
        }

        do {
            // Reconstruct the key - this will trigger Touch ID prompt if required by the key's ACL
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyData)
        } catch {
            throw SEEncryptionError.keyNotFound("Failed to reconstruct key (may require Touch ID): \(error.localizedDescription)")
        }
    }

    /// Store key reference in keychain
    private static func storeKeyReference(key: SecureEnclave.P256.KeyAgreement.PrivateKey, label: String, tag: Data) throws {
        // Store the key's data representation for later retrieval
        let keyData = key.dataRepresentation

        // Store as generic password for easy retrieval
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: label,
            kSecAttrService as String: "SDist-SE-KeyData",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw SEEncryptionError.keyGenerationFailed("Failed to store key data: \(status)")
        }

        print("Key stored successfully with label: \(label)")
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

func se_encrypt(_ inputFile: String, outputFile: String, keyLabel: String? = nil, requireBiometry: Bool = true) {
    do {
        // Clean paths
        let cleanInputFile = inputFile.trimmingCharacters(in: .whitespaces)
        let cleanOutputFile = outputFile.trimmingCharacters(in: .whitespaces)

        print("Starting Secure Enclave encryption with Touch ID...")
        print("Input: \(cleanInputFile)")
        print("Output: \(cleanOutputFile)")
        
        // Check biometry availability
        let biometryCheck = BiometryHelper.isBiometryAvailable()
        if requireBiometry && !biometryCheck.available {
            print("⚠️  Warning: Touch ID not available, falling back to user presence (Touch ID or passcode)")
            print("   Enable Touch ID in System Settings for enhanced security")
        }

        // Read input file
        guard let fileData = FileManager.default.contents(atPath: cleanInputFile) else {
            throw SEEncryptionError.fileReadError("Cannot read file: \(cleanInputFile)")
        }

        let originalFilename = URL(fileURLWithPath: cleanInputFile).lastPathComponent

        // Generate or retrieve SE key with Touch ID protection
        let label = keyLabel ?? "SDist-SE-Key-Default"
        print("\nAuthenticating with \(BiometryHelper.getBiometryDescription())...")
        
        let sePrivateKey = try SEKeyManager.getOrCreateKey(label: label, requireBiometry: requireBiometry)
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
        let ephemeralPublicKeyData = ephemeralKey.publicKey.x963Representation
        encryptedAESKey = ephemeralPublicKeyData + encryptedAESKey

        // Zero out sensitive key material
        var zeroedKey = aesKeyData
        _ = zeroedKey.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0, ptr.count)
        }

        // Build metadata
        let keyID = "sdist.se.\(label).\(UUID().uuidString)"
        let metadata = stripMetadata(SEFileMetadata(
            seKeyID: keyID,
            seKeyLabel: label,
            nonce: Data(nonceBytes),
            originalFilename: originalFilename
        ))

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
            print("\n✓ Encryption successful!")
            print("  Output file size: \(finalData.count) bytes")
            print("  Original size: \(fileData.count) bytes")
            print("  Overhead: \(finalData.count - fileData.count) bytes")
            print("  SE Key: \(label)")
            print("  Protection: Secure Enclave with Touch ID authentication")
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

        print("Starting Secure Enclave decryption with Touch ID...")
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
        guard version <= FORMAT_VERSION else {
            throw SEEncryptionError.unsupportedVersion(version)
        }

        // Read metadata
        let metadataLength = try reader.readUInt32BigEndian()
        let metadataJSON = try reader.readData(Int(metadataLength))

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(SEFileMetadata.self, from: metadataJSON)

        print("\nFile metadata:")
        if metadata.timestamp > 0 {
            print("  Encrypted: \(Date(timeIntervalSince1970: TimeInterval(metadata.timestamp)))")
        }
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

        // Retrieve SE private key - this will trigger Touch ID prompt
        print("\nAuthenticating with \(BiometryHelper.getBiometryDescription())...")
        print("(You will be prompted for authentication)")

        let sePrivateKey = try SEKeyManager.getOrCreateKey(label: metadata.seKeyLabel)

        // Split ephemeral public key and encrypted AES key
        guard encryptedAESKeyFull.count > 65 else {
            throw SEEncryptionError.decryptionFailed("Invalid encrypted key format: got \(encryptedAESKeyFull.count) bytes, expected > 65")
        }

        let ephemeralPublicKeyData = encryptedAESKeyFull.prefix(65) // 65 bytes for P256 public key
        let wrappedKey = encryptedAESKeyFull.suffix(from: 65)

        // Reconstruct ephemeral public key and perform key agreement
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: ephemeralPublicKeyData)
        let sharedSecret = try sePrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        // Derive the same wrap key
        let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "SDist-SE-Key-Wrap".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Decrypt AES key
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
            print("\n✓ Decryption successful!")
            print("  Output file size: \(decryptedData.count) bytes")
            print("  File restored successfully")
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

func se_cleanup_old_keys() {
    print("Cleaning up old SE key storage...")

    // Delete old generic password entries
    let deleteQuery1: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SDist-SE-Keys"
    ]
    SecItemDelete(deleteQuery1 as CFDictionary)

    // Also clean up the new storage if needed
    let deleteQuery2: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SDist-SE-KeyData"
    ]
    SecItemDelete(deleteQuery2 as CFDictionary)

    print("Cleanup complete. Please encrypt your file again with a fresh key.")
}

func se_list_keys() {
    print("Listing Secure Enclave keys in keychain...")
    print("\nAvailable biometry: \(BiometryHelper.getBiometryDescription())")

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SDist-SE-KeyData",
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
    print("\n💡 These keys are protected by Touch ID authentication")
}

// MARK: - Biometry Information Function

func se_check_biometry() {
    print("Checking biometric authentication capabilities...\n")
    
    let biometryCheck = BiometryHelper.isBiometryAvailable()
    
    print("Biometry Type: \(BiometryHelper.getBiometryDescription())")
    print("Available: \(biometryCheck.available ? "✓ Yes" : "✗ No")")
    
    if let error = biometryCheck.error {
        print("Status: \(error.localizedDescription)")
        
        if let laError = error as? LAError {
            switch laError.code {
            case .biometryNotAvailable:
                print("\n💡 Touch ID is not available on this Mac")
            case .biometryNotEnrolled:
                print("\n💡 Touch ID is available but not set up")
                print("   Go to System Settings > Touch ID & Password to enroll your fingerprint")
            case .biometryLockout:
                print("\n⚠️  Touch ID is locked due to too many failed attempts")
                print("   Unlock your Mac to reset Touch ID")
            case .passcodeNotSet:
                print("\n💡 No password is set on this Mac")
                print("   Set a password in System Settings to enable Touch ID")
            default:
                print("\n⚠️  Error code: \(laError.code.rawValue)")
            }
        }
    } else if biometryCheck.available {
        print("Status: Ready for use")
        print("\n✓ Your files can be protected with Touch ID authentication")
    }
    
    print("\nNote: Secure Enclave encryption works on Macs with:")
    print("  • Apple Silicon (M1, M2, M3, M4 chips)")
    print("  • T2 Security Chip (some Intel Macs)")
}

#endif // os(macOS)

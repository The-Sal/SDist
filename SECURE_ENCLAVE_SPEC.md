# SDist Secure Enclave Encrypted File Format Specification

## Version 1.0 - November 2024

---

## Overview

This document specifies the binary file format for SDist Secure Enclave (SE) encrypted files. These files use a hybrid encryption scheme combining macOS Secure Enclave hardware-backed asymmetric cryptography with AES-256-GCM symmetric encryption.

**File Extension**: `.enc.se` or `.sdist`

**Platform**: macOS only (SE hardware requirement)

---

## File Structure

```
┌─────────────────────────────────────────────────────────┐
│ Magic Header (8 bytes)                                  │
├─────────────────────────────────────────────────────────┤
│ Format Version (2 bytes)                                │
├─────────────────────────────────────────────────────────┤
│ JSON Metadata Length (4 bytes, uint32)                  │
├─────────────────────────────────────────────────────────┤
│ JSON Metadata (variable length)                         │
│   - SE Key Identifier                                   │
│   - Algorithm info                                      │
│   - Timestamp                                           │
│   - Nonce/IV                                            │
├─────────────────────────────────────────────────────────┤
│ Encrypted AES Key Length (4 bytes, uint32)              │
├─────────────────────────────────────────────────────────┤
│ Encrypted AES-256 Key (variable, typically 32-256 bytes)│
├─────────────────────────────────────────────────────────┤
│ Integrity Marker (32 bytes - SHA-256 of above)          │
├─────────────────────────────────────────────────────────┤
│ Encrypted File Content (variable length)                │
│   - Encrypted with AES-256-GCM                          │
│   - Includes GCM authentication tag (16 bytes) at end   │
└─────────────────────────────────────────────────────────┘
```

**Total Overhead**: ~400-700 bytes (negligible for most files)

---

## Field Specifications

### 1. Magic Header (8 bytes)
- **Bytes**: `0x53 0x44 0x49 0x53 0x54 0x2E 0x53 0x45`
- **ASCII**: `SDIST.SE`
- **Purpose**: File type identification and validation
- **Position**: Offset 0-7

### 2. Format Version (2 bytes, uint16, big-endian)
- **Current Value**: `0x0001` (version 1)
- **Purpose**: Format version for future compatibility
- **Position**: Offset 8-9

### 3. JSON Metadata Length (4 bytes, uint32, big-endian)
- **Range**: 0 to 4,294,967,295 bytes (practical: ~1-4KB)
- **Purpose**: Exact byte count of following JSON block
- **Position**: Offset 10-13

### 4. JSON Metadata (UTF-8 encoded, variable)
- **Position**: Offset 14 to (14 + metadata_length - 1)
- **Encoding**: UTF-8
- **Format**: Minified JSON (no pretty printing)

**Schema**:
```json
{
  "version": 1,
  "seKeyID": "string",
  "seKeyLabel": "string",
  "algorithm": "AES-256-GCM",
  "keyEncryptionAlgorithm": "ECIES-P256",
  "nonce": "base64-string",
  "timestamp": 1234567890,
  "originalFilename": "string",
  "reserved": {}
}
```

**Field Descriptions**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | integer | Yes | Metadata schema version (currently 1) |
| `seKeyID` | string | Yes | Unique identifier for SE key in keychain |
| `seKeyLabel` | string | Yes | Human-readable key label for lookup |
| `algorithm` | string | Yes | Symmetric encryption algorithm (must be "AES-256-GCM") |
| `keyEncryptionAlgorithm` | string | Yes | Asymmetric algorithm for key wrapping (must be "ECIES-P256") |
| `nonce` | string | Yes | Base64-encoded 12-byte nonce for AES-GCM |
| `timestamp` | integer | Yes | Unix timestamp of encryption (seconds since epoch) |
| `originalFilename` | string | No | Original filename before encryption |
| `reserved` | object | No | Reserved for future extensions |

### 5. Encrypted AES Key Length (4 bytes, uint32, big-endian)
- **Typical Values**: 32-256 bytes
- **Purpose**: Length of ECIES-encrypted symmetric key
- **Position**: Immediately after JSON metadata

### 6. Encrypted AES-256 Key (variable)
- **Content**: The 32-byte AES-256 key, encrypted with SE public key
- **Algorithm**: ECIES (Elliptic Curve Integrated Encryption Scheme) with P-256 curve
- **Typical Size**: 97-133 bytes (ECIES overhead)
- **Position**: Immediately after encrypted key length field

### 7. Integrity Marker (32 bytes)
- **Algorithm**: SHA-256
- **Input**: All bytes from file start through end of encrypted AES key
- **Formula**:
  ```
  SHA-256(
    magic_header ||
    format_version ||
    metadata_length ||
    json_metadata ||
    encrypted_key_length ||
    encrypted_aes_key
  )
  ```
- **Purpose**:
  - Metadata integrity verification
  - Logical separator between metadata and payload
  - Fast corruption detection
- **Position**: Immediately after encrypted AES key

### 8. Encrypted File Content (variable, remainder of file)
- **Algorithm**: AES-256-GCM
- **Key**: The symmetric AES key (after SE decryption)
- **Nonce**: 12 bytes from JSON metadata
- **Structure**: `[ciphertext (N bytes)][authentication_tag (16 bytes)]`
- **Authentication Tag**: Last 16 bytes of the file
- **Position**: From end of integrity marker to EOF

---

## Encryption Process

1. **Generate or retrieve SE key pair**
   - Check keychain for existing SE private key
   - If not found, create new key in Secure Enclave
   - Store reference with `seKeyID` and `seKeyLabel`

2. **Generate symmetric encryption key**
   - Create random 32-byte (256-bit) AES key using CSRNG
   - Generate random 12-byte nonce

3. **Encrypt file content**
   - Read input file into memory (or stream for large files)
   - Encrypt with AES-256-GCM using generated key and nonce
   - Produces: `ciphertext + 16-byte authentication tag`

4. **Encrypt the AES key**
   - Extract SE public key from private key
   - Encrypt 32-byte AES key using ECIES with P-256
   - Produces: ECIES-encrypted key blob (~100 bytes)

5. **Build metadata**
   - Construct JSON object with all metadata fields
   - Serialize to UTF-8 bytes (minified)
   - Calculate length

6. **Assemble file**
   - Write magic header (8 bytes)
   - Write format version (2 bytes)
   - Write metadata length (4 bytes)
   - Write JSON metadata (variable)
   - Write encrypted key length (4 bytes)
   - Write encrypted AES key (variable)
   - Calculate and write integrity marker (32 bytes)
   - Write encrypted content with tag (variable)

7. **Secure cleanup**
   - Zero out AES key from memory
   - Zero out plaintext file data
   - Flush buffers

---

## Decryption Process

1. **Read and validate header**
   - Read first 8 bytes, verify magic header
   - Read format version, check compatibility
   - If invalid, abort immediately

2. **Parse metadata**
   - Read metadata length (4 bytes)
   - Read JSON metadata (metadata_length bytes)
   - Parse JSON, extract fields
   - Validate required fields present

3. **Read encrypted key**
   - Read encrypted key length (4 bytes)
   - Read encrypted AES key (key_length bytes)

4. **Verify integrity marker**
   - Read 32-byte hash
   - Recalculate SHA-256 of all metadata
   - Compare hashes (constant-time comparison)
   - If mismatch, abort (corruption detected)

5. **Decrypt AES key with SE**
   - Look up SE private key using `seKeyID`
   - Prompt for biometric authentication (Touch ID / Face ID)
   - Decrypt encrypted AES key using SE private key
   - Produces: 32-byte plaintext AES key

6. **Decrypt file content**
   - Read remaining file data (ciphertext + tag)
   - Decrypt using AES-256-GCM with decrypted key and nonce
   - Verify GCM authentication tag
   - If tag invalid, abort (tampering detected)

7. **Write output**
   - Write decrypted content to output file
   - Set appropriate permissions

8. **Secure cleanup**
   - Zero out AES key from memory
   - Zero out plaintext data buffers

---

## Security Properties

### Confidentiality
- ✅ **File content**: Protected by AES-256-GCM (industry standard)
- ✅ **AES key**: Protected by SE private key (hardware-backed, non-extractable)
- ⚠️ **Metadata**: NOT encrypted (visible to attackers)
  - Exposed: timestamp, original filename, algorithm names, SE key ID
  - Rationale: Required for decryption, non-sensitive

### Integrity
- ✅ **Metadata**: Protected by SHA-256 integrity marker
- ✅ **File content**: Protected by GCM authentication tag (16 bytes)
- ✅ **Detection**: Both corruption and tampering detected

### Authenticity
- ✅ **Content authenticity**: GCM provides authenticated encryption
- ⚠️ **Metadata authenticity**: Hash-based (not HMAC), vulnerable to replacement
  - Acceptable: Metadata is public information
  - Future: Consider HMAC-SHA256 in v1.1

### Device Binding
- ✅ **SE private key**: Locked to specific device, non-exportable
- ✅ **Biometric requirement**: Face ID / Touch ID required for decryption
- ⚠️ **Limitation**: File cannot be decrypted on different device
  - This is by design (Secure Enclave purpose)

---

## Error Handling

### Encryption Errors

| Error | Cause | User Action |
|-------|-------|-------------|
| SE key generation failed | No SE hardware, permissions issue | Verify macOS device, check entitlements |
| File read error | Invalid path, permissions | Check file exists and is readable |
| Memory allocation failed | File too large | Use streaming encryption (future) |

### Decryption Errors

| Error | Cause | User Action |
|-------|-------|-------------|
| Invalid magic header | Not an SE-encrypted file | Verify correct file |
| Unsupported version | Future format version | Update SDist to newer version |
| Integrity marker mismatch | File corruption or tampering | File is corrupted, restore from backup |
| SE key not found | Wrong device, key deleted | File encrypted on different device |
| Biometric authentication failed | User cancelled, biometrics disabled | Retry, enable Touch/Face ID |
| GCM tag verification failed | Content tampering or corruption | File has been modified, restore from backup |

---

## Implementation Notes

### Endianness
- **All multi-byte integers**: Big-endian (network byte order)
- **Rationale**: Standard for binary formats, cross-platform consistency

### Memory Safety
- **Sensitive data**: Use `withUnsafeBytes` and explicit zeroing
- **Swift**: Use `Data(count:)` then zero, or `SecureBytes` wrapper
- **Nonce**: Use `SystemRandomNumberGenerator` (cryptographically secure)

### Large File Handling
- **Current**: Load entire file into memory
- **Future (v2.0)**: Chunked streaming for GB+ files
- **Limit**: Practical limit ~2GB on 32-bit systems (uint32 limitations)

### Cross-Platform
- **Compile Guard**: All SE code wrapped in `#if os(macOS)`
- **Linux/Windows**: Code excluded at compile time
- **Fallback**: Use standard `openssl_encrypt()` on non-macOS

---

## File Extension Recommendations

### Primary: `.enc.se`
- Clear indication of encryption + SE
- Maintains `.enc` consistency with OpenSSL encryption
- Easy to distinguish from standard `.enc` files

### Alternative: `.sdist`
- Custom extension for SDist ecosystem
- Requires user education
- Could support both SE and standard encryption in future

---

## Version History

### Version 1.0 (November 2024)
- Initial specification
- AES-256-GCM content encryption
- ECIES-P256 key wrapping
- SHA-256 integrity marker
- JSON metadata format

---

## Future Enhancements

### Version 1.1 (Proposed)
- **HMAC integrity marker**: Replace SHA-256 with HMAC-SHA256
- **Metadata encryption**: Optional encrypted metadata section
- **Compression support**: Transparent zlib/zstd before encryption

### Version 2.0 (Proposed)
- **Chunked encryption**: Stream large files in 64MB chunks
- **Multi-key support**: Encrypt for multiple SE keys (shared files)
- **Forward secrecy**: Ephemeral key agreement per file

---

## References

- **AES-GCM**: NIST SP 800-38D
- **ECIES**: IEEE 1363a-2004, SEC 1 v2.0
- **Secure Enclave**: Apple Platform Security Guide
- **CryptoKit**: Apple Developer Documentation

---

**Specification Author**: Claude (Anthropic AI)
**Implementation**: SDist Project
**License**: Same as SDist project

# SDist

**Secure Distribution** - A command-line tool for secure distribution of payloads with optional encryption

SDist provides a centralized manifest system for managing and distributing assets across networks, with support for both standard password-based encryption and hardware-backed Secure Enclave encryption on macOS.

---

## Overview

SDist operates on a client-server model where:
- A **Distribution Center** (server) maintains a manifest of asset locations
- Clients use a **manifest password** to access and manage asset URLs in the manifest
- Assets can be optionally encrypted using either OpenSSL or macOS Secure Enclave
- The manifest password is distinct from encryption keys used to secure the actual payloads

### Key Concept: Manifest Password vs Encryption Keys

**Manifest Password**: Controls access to the distribution manifest (the database of asset URLs). This password allows you to:
- Query asset locations
- Add/update asset URLs
- Remove assets from the manifest
- List all available assets

**Encryption Keys**: Separate credentials that protect the actual file contents:
- **OpenSSL encryption**: Password-based encryption (you set the password when encrypting)
- **Secure Enclave encryption**: Hardware-backed keys protected by biometric authentication

The manifest password grants access to *where* files are located, while encryption keys protect *what's inside* those files.

---

## Platform Compatibility

| Feature | Linux | macOS |
|---------|-------|-------|
| Asset distribution | ✅ | ✅ |
| Manifest management | ✅ | ✅ |
| OpenSSL encryption/decryption | ✅ | ✅ |
| Secure Enclave encryption | ❌ | ✅ |
| Application installation | ❌ | ✅ |

SDist is cross-platform compatible for core distribution and standard encryption features. Secure Enclave features require macOS hardware and are conditionally compiled on that platform only.

---

## Encryption Methods

SDist supports two distinct encryption approaches:

### Standard Encryption (OpenSSL)

- **Algorithm**: AES-256-CBC with PBKDF2 key derivation
- **Key Derivation**: 1,000,000 iterations for resistance against brute-force attacks
- **File Extension**: `.enc`
- **Platform Support**: Linux and macOS
- **Authentication**: Password-based (user provides password during encryption/decryption)
- **Portability**: Files can be decrypted on any platform with the correct password
- **Use Case**: Cross-platform distribution, password-protected payloads

### Secure Enclave Encryption (macOS only)

- **Algorithm**: AES-256-GCM for content, ECIES-P256 for key wrapping
- **File Extension**: `.enc.se`
- **Platform Support**: macOS only (requires Secure Enclave hardware)
- **Authentication**: Biometric (Touch ID / Face ID) required for key access
- **Key Storage**: Private keys stored in Secure Enclave, non-extractable
- **Portability**: Files can only be decrypted on the device where they were encrypted
- **Use Case**: Device-bound sensitive data, hardware-backed security

For technical details on the Secure Enclave file format, see [SECURE_ENCLAVE_SPEC.md](SECURE_ENCLAVE_SPEC.md).

**Key Differences**:
- OpenSSL encryption is password-based and portable; SE encryption is hardware-bound and requires biometrics
- OpenSSL uses CBC mode; SE uses GCM (authenticated encryption)
- SE provides device binding and tamper detection through hardware security
- SE encryption includes metadata integrity verification and authentication tags

---

## Asset Distribution

### How Distribution Works

SDist uses a centralized Distribution Center that maintains a manifest mapping asset keys to URLs:

1. **Upload**: Host your files on any CDN or web server
2. **Register**: Add the asset's URL to the manifest with a unique key
3. **Distribute**: Share the asset key and manifest password with users
4. **Download**: Users retrieve the asset using the key, which queries the manifest for the download URL

Assets can be:
- Plain files (unencrypted)
- OpenSSL-encrypted files (.enc extension)
- Secure Enclave-encrypted files (.enc.se extension, macOS only)
- macOS application bundles (.app in .zip format)

### Downloading Assets

Assets are downloaded through a two-step process:

1. SDist queries the Distribution Center with the asset key and manifest password
2. The server returns the direct download URL
3. SDist downloads the file from the URL to your local system

If an encrypted file (.enc) is detected during download, SDist will prompt whether to decrypt it immediately using the OpenSSL decryption method.

---

## macOS Application Distribution

SDist includes specialized commands for distributing and installing macOS application bundles (.app). This feature is macOS-only and handles the complete workflow from download to installation.

### Application Installation Process

When using the `install`, `install-encrypted`, or `install-local-encrypted` commands, SDist performs the following operations:

1. **Download or Locate**: Retrieves the application zip from the manifest URL or uses a local encrypted zip file
2. **Decryption** (if encrypted): Decrypts the zip file using OpenSSL with user-provided password
3. **Extraction**: Unzips the application to a temporary directory
4. **Security Attribute Removal**: Removes macOS Gatekeeper quarantine flags and clears extended attributes that would prevent execution
5. **Permission Setting**: Makes the application executable
6. **Installation**: Moves the .app bundle to the current working directory
7. **Cleanup**: Removes temporary files and directories

### Operations Performed on Applications

SDist automatically executes these security-related operations on installed applications:

- **`xattr -d com.apple.quarantine`**: Removes the quarantine attribute that macOS applies to downloaded files, which would otherwise trigger Gatekeeper warnings
- **`chmod +x`**: Sets executable permissions on the application bundle and its executables
- **`xattr -cr`**: Recursively clears all extended attributes from the application bundle

These operations ensure the application can launch immediately without manual intervention to bypass security prompts.

### Application Distribution Formats

Applications can be distributed in three formats:

1. **Plain zip**: Standard .zip file containing the .app bundle (use `install` command)
2. **OpenSSL encrypted zip**: .zip.enc file requiring password decryption (use `install-encrypted` command)
3. **Local encrypted zip**: Previously downloaded encrypted zip (use `install-local-encrypted` command)

All formats are extracted to the current directory after processing. The encrypted formats provide an additional layer of security for proprietary or sensitive applications.

### Application Bundle Requirements

For successful installation, application zips must:
- Contain a single .app bundle at the root level
- Follow standard macOS application structure (Contents/MacOS/ with executables)
- Be properly formatted zip archives

SDist will verify the application structure and abort installation if the bundle format is invalid.

---

## Installation

### Building from Source

SDist is written in Swift and requires a Swift compiler.

**macOS:**
```bash
cd SDist
swiftc *.swift -o sdist
```

**Linux:**
```bash
cd SDist
swiftc *.swift -o sdist
```

The compiled binary `sdist` will be created in the SDist directory. You can move it to a location in your PATH for system-wide access:

```bash
sudo mv sdist /usr/local/bin/
```

### Requirements

- **Swift 5.5+** (Swift compiler)
- **OpenSSL** (for standard encryption, usually pre-installed)
- **macOS 10.15+** (for Secure Enclave features)

---

## Usage

SDist operates in two modes:

### Interactive Mode

Launch SDist without arguments to enter interactive mode:
```bash
./sdist
```

You'll be prompted for the manifest password, then can execute commands interactively.

### Command-Line Mode

Execute single commands directly:
```bash
./sdist -c -p <manifest_password> -f <command> -a <arguments...>
```

---

## Core Commands

### Manifest Management

- **list**: Display all available assets in the manifest
- **get**: Retrieve the download URL for a specific asset key
- **update**: Add or update an asset's URL in the manifest
- **rm-asset**: Remove an asset from the manifest

### Asset Operations

- **download**: Download an asset from the distribution network
- **encrypt**: Encrypt a file locally using OpenSSL
- **decrypt**: Decrypt a file locally using OpenSSL

### Secure Enclave Commands (macOS only)

- **encrypt-se**: Encrypt a file using Secure Enclave
- **decrypt-se**: Decrypt a Secure Enclave encrypted file
- **list-se-keys**: Show Secure Enclave keys stored in keychain
- **cleanup-se-keys**: Remove old or orphaned SE keys
- **install**: Download and install a macOS application bundle
- **install-encrypted**: Download and install an encrypted macOS application
- **install-local-encrypted**: Install an application from a local encrypted zip

### Utility Commands

- **save-password**: Store manifest password to `.sdist` file in current directory
- **help**: Display all available commands
- **clear**: Clear the terminal screen
- **ls**: List files in current directory
- **exit**: Exit the program

Use the `-h` flag to view detailed documentation on all commands and flags.

---

## Security Considerations

### Manifest Password Storage

The manifest password can be saved locally in a `.sdist` file for convenience. This file is stored in plaintext, so ensure appropriate file permissions on systems where multiple users have access.

### Encryption Key Management

- **OpenSSL passwords**: Not stored by SDist; you must remember them or manage them separately
- **SE keys**: Stored in macOS Keychain, protected by Secure Enclave and biometric authentication

### Network Security

Asset URLs and manifest queries are transmitted over HTTPS. The security of your payloads depends on:
1. The strength of your manifest password
2. The encryption method used (if any)
3. The security of your hosting infrastructure

### Secure Enclave Limitations

Files encrypted with Secure Enclave cannot be decrypted on a different device or if the SE key is deleted. Ensure you have unencrypted backups of critical data or use OpenSSL encryption for files that need to be portable.

---

## Version

Current version: 0.8

---

## Project Structure

```
SDist/
├── SDist/
│   ├── main.swift           # Entry point and CLI argument parsing
│   ├── commands.swift        # Command implementations
│   ├── constants.swift       # Configuration and endpoints
│   ├── openssl.swift         # OpenSSL encryption functions
│   ├── secureEnclave.swift   # Secure Enclave operations (macOS)
│   └── subprocesses.swift    # Process spawning utilities
├── SECURE_ENCLAVE_SPEC.md    # Technical specification for SE encryption
└── README.md                 # This file
```

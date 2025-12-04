# SDist

A secure distribution CLI tool for managing and distributing encrypted assets with support for both OpenSSL and Secure Enclave encryption.

## Features

- **Asset Management**: Upload, download, and manage assets through a distribution network
- **Dual Encryption Support**: 
  - OpenSSL AES-256-CBC encryption with PBKDF2
  - Secure Enclave encryption with Touch ID authentication (macOS only)
- **Application Installation**: Install macOS applications from encrypted zip files
- **Interactive & CLI Modes**: Use interactively or via command line arguments
- **Password Management**: Securely store passwords locally

## Requirements

- macOS (for Secure Enclave features)
- OpenSSL command-line tools
- Xcode (for building)

## Installation

1. Clone the repository
2. Open the Xcode project
3. Build and run the application

## Usage

### Interactive Mode

Simply run the application and follow the prompts:

```bash
./SDist
```

### Command Line Mode

```bash
./SDist -c -p PASSWORD -f COMMAND -a ARGUMENTS
```

#### Flags

- `-c`: Run in command line mode
- `-p`: Password to use
- `-f`: Function/command to run
- `-a`: Arguments for the function
- `-h`: Show help message
- `--args-only`: Exit with error if insufficient arguments provided

## Commands

### Basic Commands

- `get`: Get the URL of an asset
- `download`: Download an asset (optionally decrypt)
- `list`: List all available assets
- `update`: Update the CDN with a new asset
- `rm-asset`: Remove an asset from the manifest

### Encryption Commands

- `encrypt`: Locally encrypt a file using OpenSSL
- `decrypt`: Locally decrypt a file using OpenSSL
- `save-password`: Save password to local file

### macOS-Only Commands

- `encrypt-se`: Encrypt a file using Secure Enclave with Touch ID
- `decrypt-se`: Decrypt a Secure Enclave encrypted file
- `list-se-keys`: List Secure Enclave keys in keychain
- `cleanup-se-keys`: Clean up old SE key storage
- `install`: Install an application from the distribution network
- `install-encrypted`: Install an encrypted application
- `install-local-encrypted`: Install from a locally encrypted zip

### Utility Commands

- `help`: Show help information
- `clear`: Clear the screen
- `ls`: List directory contents
- `exit`: Exit the CLI

## Examples

### Download an asset

```bash
./SDist -c -p mypassword -f download -a asset_key my_file.txt
```

### Encrypt a file with Secure Enclave

```bash
./SDist
> encrypt-se
Filepath: /path/to/file.txt
Destination: encrypted_file.txt.enc.se
SE Key Label (optional): MyKey
```

### Install an application

```bash
./SDist -c -p mypassword -f install -a app_key
```

## Security Features

### Secure Enclave Encryption (macOS)

- Uses Apple's Secure Enclave for hardware-backed key storage
- Touch ID authentication required for encryption/decryption
- Hybrid encryption: SE key wrapping + AES-256-GCM
- Integrity verification with SHA-256
- Automatic key management in macOS Keychain

### OpenSSL Encryption

- AES-256-CBC encryption
- PBKDF2 key derivation with 1,000,000 iterations
- Cross-platform compatibility

## File Structure

- `main.swift`: Entry point and CLI argument handling
- `commands.swift`: Core command implementations
- `constants.swift`: Constants and configuration
- `openssl.swift`: OpenSSL encryption functions
- `secureEnclave.swift`: Secure Enclave encryption (macOS only)
- `subprocesses.swift`: System process utilities
- `SDist.entitlements`: macOS app entitlements

## API Endpoints

The tool communicates with a distribution center at `https://thesal.pythonanywhere.com/dc`:

- `/location?l=KEY&p=PASSWORD`: Get asset location
- `/location/set?k=KEY&v=URL&p=PASSWORD`: Set asset location
- `/location/all?p=PASSWORD`: List all assets
- `/location/remove?k=KEY&p=PASSWORD`: Remove asset

## Version

Current version: 0.8

## License

Copyright © 2024 Sal Faris. All rights reserved.
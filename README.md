# SDist

**SDist** – A command-line tool for secure distribution of payloads with optional encryption.

SDist provides a centralized manifest system for managing and distributing assets across networks, with support for both standard password-based encryption and hardware-backed Secure Enclave encryption on macOS.

---

## Overview

SDist operates on a client-server model:

- A **Distribution Center** (server) maintains a manifest mapping asset keys to URLs
- Clients authenticate with a **manifest password** to query and manage the manifest
- Assets can be optionally encrypted using OpenSSL or the macOS Secure Enclave
- Downloads can be customized with **cURL Mods** for CDN-specific header requirements

### Manifest Password vs. Encryption Keys

**Manifest Password** — controls access to the manifest (the registry of asset URLs):
- Query asset locations
- Add or update asset URLs
- Remove assets
- List all available assets

**Encryption Keys** — protect the actual file contents:
- **OpenSSL**: password-based AES-256-CBC encryption
- **Secure Enclave**: hardware-backed biometric-protected keys (macOS only)

The manifest password controls *where* files are; encryption keys protect *what's inside* them.

---

## Platform Compatibility

| Feature | Linux | macOS |
|---------|:-----:|:-----:|
| Asset distribution | ✅ | ✅ |
| Manifest management | ✅ | ✅ |
| OpenSSL encryption/decryption | ✅ | ✅ |
| Upload & registration | ✅ | ✅ |
| Secure Enclave encryption | ❌ | ✅ |
| Application installation | ❌ | ✅ |

---

## Encryption Methods

### Standard Encryption (OpenSSL)

- **Algorithm**: AES-256-CBC with PBKDF2 key derivation (1,000,000 iterations)
- **File extension**: `.enc`
- **Platform**: Linux and macOS
- **Authentication**: Password-based
- **Portability**: Decryptable on any platform with the correct password

### Secure Enclave Encryption (macOS only)

- **Algorithm**: AES-256-GCM for content, ECIES-P256 for key wrapping
- **File extension**: `.enc.se`
- **Platform**: macOS only (requires Secure Enclave hardware)
- **Authentication**: Biometric (Touch ID / Face ID)
- **Key storage**: Private keys stored in Secure Enclave, non-extractable
- **Portability**: Device-bound — files can only be decrypted on the originating device

For the Secure Enclave file format specification, see [SECURE_ENCLAVE_SPEC.md](SECURE_ENCLAVE_SPEC.md).

---

## Installation

### Building from Source

SDist is written in Swift. Build it with:

```bash
cd SDist
swiftc *.swift -o product && sudo mv product /usr/local/bin/sdist
```

### Requirements

- Swift 5.5+
- OpenSSL (for standard encryption — usually pre-installed)
- macOS 10.15+ (for Secure Enclave features)

---

## Usage

### Interactive Mode

Launch without arguments to enter interactive mode. SDist will load your saved password (or prompt for one), then display available commands with tab completion and inline hints:

```bash
./sdist
```

Features in interactive mode:
- **Tab completion** for command names and asset keys / local files
- **Inline hints** showing the closest match as you type
- **Command history** persisted to `~/.sdist_history`

### Command-Line Mode

Execute a single command non-interactively:

```bash
./sdist -c -p <manifest_password> -f <command> -a <arguments...>
```

Use `--args-only` to make missing arguments a hard error instead of falling back to interactive prompts:

```bash
./sdist -c -p <password> --args-only -f download -a my_asset output.zip
```

### Flags

| Flag | Description |
|------|-------------|
| `-c` | Run in command-line mode |
| `-p <password>` | Manifest password |
| `-f <command>` | Command to execute |
| `-a <args...>` | Arguments for the command (everything after `-a`) |
| `-h` | Print full documentation |
| `--args-only` | Exit with error if arguments are missing (no interactive fallback) |

Run `./sdist -h` for generated documentation including all commands and flags.

---

## Commands

### Manifest Management

| Command | Description |
|---------|-------------|
| `list` | List all assets in the manifest |
| `get` | Get the download URL for an asset key |
| `update` | Add or update an asset URL in the manifest |
| `rm-asset` | Remove an asset from the manifest |

### Asset Operations

| Command | Description |
|---------|-------------|
| `download` | Download an asset (prompts to decrypt if `.enc` detected) |
| `encrypt` | Encrypt a file locally using OpenSSL (`.enc`) |
| `decrypt` | Decrypt an OpenSSL-encrypted file locally |
| `config` | Configure the upload destination path and base URL |
| `upload` | Copy a file to the configured path and register it in the manifest |

### Secure Enclave Commands (macOS only)

| Command | Description |
|---------|-------------|
| `encrypt-se` | Encrypt a file using Secure Enclave (`.enc.se`) |
| `decrypt-se` | Decrypt a Secure Enclave-encrypted file |
| `list-se-keys` | List SE keys stored in Keychain |
| `cleanup-se-keys` | Remove old or orphaned SE keys |
| `install` | Download and install a macOS application bundle |
| `install-encrypted` | Download and install an OpenSSL-encrypted macOS app |
| `install-local-encrypted` | Install a macOS app from a local encrypted zip |

### Utility Commands

| Command | Description |
|---------|-------------|
| `save-password` | Save the manifest password to `~/.sdist` |
| `help` | Show available commands |
| `clear` | Clear the terminal screen |
| `ls` | List files in the current directory |
| `exit` | Exit the program |

---

## Upload Workflow

SDist includes a built-in upload system for registering assets directly from your machine.

### 1. Configure the upload destination

```bash
./sdist -c -p PASSWORD -f config -a /path/to/upload/dir https://cdn.example.com/assets
```

This saves `path_for_upload` and `url_for_upload` to `~/.sdist_config.json`.

### 2. Upload and register a file

```bash
./sdist -c -p PASSWORD -f upload -a /path/to/file.zip
```

SDist will:
1. Sanitize the filename (spaces → `-`, special characters stripped)
2. Copy the file to the configured upload path
3. Register the asset in the manifest with the computed URL as its location

The asset key and public URL are derived from the sanitized filename automatically.

---

## macOS Application Distribution

SDist handles the full lifecycle of distributing and installing macOS application bundles (`.app`).

### Installation Process

1. **Download or locate** the application zip from the manifest or a local path
2. **Decrypt** (if encrypted) using OpenSSL
3. **Extract** the zip to a temporary directory
4. **Remove quarantine attributes** (`xattr -d com.apple.quarantine`, `xattr -cr`)
5. **Set executable permissions** (`chmod +x`)
6. **Move** the `.app` bundle to the current working directory
7. **Clean up** temporary files

### Distribution Formats

| Format | Command |
|--------|---------|
| Plain zip (`.zip`) | `install` |
| OpenSSL-encrypted zip (`.zip.enc`) | `install-encrypted` |
| Local encrypted zip | `install-local-encrypted` |

### Requirements

The application zip must contain a single `.app` bundle at the root level following the standard macOS bundle structure (`Contents/MacOS/`).

---

## cURL Mods — Custom Download Configuration

cURL Mods let you inject custom HTTP headers and cURL parameters into download requests based on URL patterns. Useful for CDNs that require specific headers, referers, or user agents.

### Configuration File

Create `~/.sdist_config.json` to define your patterns:

```json
{
  "curl_mods": [
    {
      "pattern": "https://cdn.example.com",
      "additionalParameters": ["-H", "Authorization: Bearer token"]
    },
    {
      "pattern": "https://private.cdn.io",
      "additionalParameters": ["-H", "Referer: https://mysite.com", "-H", "User-Agent: MyAgent/1.0"]
    }
  ],
  "path_for_upload": "/srv/cdn/assets",
  "url_for_upload": "https://cdn.example.com/assets"
}
```

The legacy array-only format is still supported for backward compatibility.

### How It Works

When SDist performs a download, it checks the URL against all configured patterns. If a match is found, the corresponding parameters are appended to the cURL call transparently.

### Built-in Patterns

SDist ships with a built-in pattern for Mega.co.nz API transfers, which automatically includes the required `Referer` and `User-Agent` headers.

### Supported Parameters

Any valid cURL argument works:

```json
["-H", "Header-Name: value"]      // Custom header
["-H", "User-Agent: Agent/1.0"]   // User agent
["-H", "Referer: https://x.com"]  // Referer
["--compressed"]                   // Compression
["-k"]                             // Insecure (skip TLS verification)
```

---

## Password Storage

The manifest password can be saved to `~/.sdist` for automatic loading:

```bash
# In interactive mode
save-password

# In command-line mode
./sdist -c -p PASSWORD -f save-password -a PASSWORD
```

On subsequent runs, SDist loads the password from `~/.sdist` automatically — no prompt needed.

> The `.sdist` file is stored in plaintext. Set appropriate permissions on shared systems.



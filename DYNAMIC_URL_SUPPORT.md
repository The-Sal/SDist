# Dynamic URL Support for SDist

## Executive Summary

This document outlines a design proposal for adding dynamic URL resolution to SDist, enabling the system to query external endpoints on-demand rather than relying solely on the centralized manifest server. This feature would allow SDist to integrate with third-party asset repositories, CDNs, and other distribution systems dynamically.

---

## Current Architecture

### Existing Manifest Server Model

SDist currently operates with a centralized "Distribution Center" (manifest server) at:
- **Base URL**: `https://thesal.pythonanywhere.com/dc`
- **Endpoints**:
  - `/location?l={key}&p={password}` - Get asset URL
  - `/location/set?k={key}&v={url}&p={password}` - Set/update asset URL
  - `/location/all?p={password}` - List all assets
  - `/location/remove?k={key}&p={password}` - Remove asset

### Current Flow

1. User executes a command (e.g., `list`, `download`, `get`)
2. SDist queries the centralized manifest server with authentication
3. Server returns asset information (URLs, lists, etc.)
4. SDist processes the response and performs the requested operation

### Key Components

- **constants.swift**: Defines endpoint URLs and configuration
- **commands.swift**: Implements command logic that queries endpoints
- **subprocesses.swift**: Handles HTTP requests via cURL

---

## Proposed Dynamic URL Support

### Concept

Rather than always querying the static manifest server, SDist would support **dynamic URL providers** that can be specified at runtime or configured per-asset. When a command like `list` or `get` is executed, SDist would:

1. Check if the asset/operation is configured for dynamic resolution
2. Query the dynamic URL endpoint directly
3. Parse the response according to the provider's format
4. Return results to the user

This allows integration with:
- GitHub Releases API
- AWS S3 buckets with listing enabled
- Custom REST APIs
- Third-party package repositories
- Content delivery networks with metadata APIs

---

## Design Proposal

### 1. Configuration System

#### Option A: Per-Asset Dynamic URLs (Recommended)

Extend the manifest to support a special prefix or metadata flag indicating dynamic resolution:

```json
{
  "myapp": "https://cdn.example.com/packages/myapp",
  "dynamic:github-releases": "https://api.github.com/repos/owner/repo/releases",
  "dynamic:s3-bucket": "https://my-bucket.s3.amazonaws.com/manifest.json"
}
```

When an asset key starts with `dynamic:`, SDist would:
- Parse the URL as a dynamic endpoint
- Query it directly instead of treating it as a download URL
- Process the response according to the provider type

#### Option B: Global Dynamic Providers

Add a configuration file (`~/.sdist_dynamic_providers.json`) similar to the existing cURL mods:

```json
{
  "providers": [
    {
      "name": "github-releases",
      "type": "github-api",
      "baseUrl": "https://api.github.com/repos/myorg/myrepo/releases",
      "auth": {
        "type": "bearer",
        "token": "${GITHUB_TOKEN}"
      }
    },
    {
      "name": "custom-cdn",
      "type": "rest-api",
      "endpoints": {
        "list": "https://cdn.example.com/api/packages",
        "get": "https://cdn.example.com/api/packages/{key}",
        "download": "https://cdn.example.com/downloads/{key}"
      }
    }
  ]
}
```

Users would then reference providers in commands:
```bash
./sdist -c -p PASSWORD -f list -a --provider=github-releases
./sdist -c -p PASSWORD -f download -a package-name --provider=custom-cdn
```

### 2. Provider Architecture

Create a new file `providers.swift` with a provider abstraction:

```swift
protocol DynamicProvider {
    var name: String { get }
    func listAssets() throws -> [String]
    func getAssetURL(key: String) throws -> String
    func getAssetMetadata(key: String) throws -> [String: Any]
}

class GitHubReleasesProvider: DynamicProvider {
    let baseUrl: String
    let authToken: String?
    
    func listAssets() throws -> [String] {
        // Query GitHub API: GET /repos/{owner}/{repo}/releases
        // Parse JSON response
        // Return array of release tags/names
    }
    
    func getAssetURL(key: String) throws -> String {
        // Query specific release by tag
        // Find matching asset in release
        // Return browser_download_url
    }
}

class RestAPIProvider: DynamicProvider {
    let endpoints: [String: String]
    
    func listAssets() throws -> [String] {
        // Query custom endpoint
        // Parse response (JSON/XML)
        // Return asset list
    }
}

class S3BucketProvider: DynamicProvider {
    let bucketUrl: String
    
    func listAssets() throws -> [String] {
        // Query S3 XML listing endpoint
        // Parse XML response
        // Return object keys
    }
}
```

### 3. Modified Command Flow

Update command implementations in `commands.swift`:

```swift
func list_all(_ params: dynamicParams) throws {
    // Check if dynamic provider is specified
    if let providerName = params["provider"] {
        let provider = DynamicProviderManager.shared.getProvider(providerName)
        let assets = try provider.listAssets()
        print("Assets from \(providerName):")
        for asset in assets {
            print("*", asset)
        }
        return
    }
    
    // Fall back to existing manifest server logic
    let response = GET(url: .init(format: Endpoints.allLocation, PASSWORD))
    // ... existing code
}

func get_location(_ params: dynamicParams) throws {
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Enter Asset Key:"))
    
    // Check if key uses dynamic: prefix
    if key.starts(with: "dynamic:") {
        let components = key.split(separator: ":", maxSplits: 2)
        let providerName = String(components[1])
        let assetKey = components.count > 2 ? String(components[2]) : ""
        
        let provider = DynamicProviderManager.shared.getProvider(providerName)
        let url = try provider.getAssetURL(key: assetKey)
        print("URL:", url)
        return
    }
    
    // Fall back to existing manifest server logic
    let response = GET(url: .init(format: Endpoints.location, key, PASSWORD))
    // ... existing code
}
```

### 4. Response Format Adapters

Different APIs return data in different formats. Create adapters to normalize responses:

```swift
protocol ResponseAdapter {
    func parseListResponse(_ data: Data) throws -> [String]
    func parseAssetResponse(_ data: Data) throws -> String
}

class JSONResponseAdapter: ResponseAdapter {
    let listKeyPath: String  // e.g., "releases[].tag_name"
    let urlKeyPath: String   // e.g., "assets[0].browser_download_url"
    
    func parseListResponse(_ data: Data) throws -> [String] {
        // Parse JSON and extract values at keyPath
    }
}

class XMLResponseAdapter: ResponseAdapter {
    func parseListResponse(_ data: Data) throws -> [String] {
        // Parse XML (e.g., S3 ListBucket response)
    }
}
```

---

## Implementation Complexity

### Difficulty: Medium (3-5 days of work)

#### Phase 1: Foundation (1-2 days)
- Create `providers.swift` with base protocol and manager
- Add configuration loading for dynamic providers
- Implement basic REST API provider

#### Phase 2: Provider Implementations (1-2 days)
- GitHub Releases provider
- S3 bucket provider
- Generic REST API provider with customizable endpoints
- Response format adapters (JSON, XML)

#### Phase 3: Command Integration (1 day)
- Modify `list_all()` to check for dynamic providers
- Modify `get_location()` to support dynamic URLs
- Modify `download_asset()` to work with dynamic providers
- Add command-line flags for provider selection

#### Phase 4: Testing & Documentation (1 day)
- Test with real APIs (GitHub, S3)
- Update README with dynamic provider documentation
- Add example configurations
- Error handling and edge cases

### Breaking Changes: None

The proposed design is **fully backward compatible**:
- Existing manifest server functionality remains unchanged
- Dynamic providers are opt-in via configuration or command flags
- No changes to core commands if dynamic providers aren't used

### Dependencies

**New Dependencies**: None required
- Uses existing cURL for HTTP requests
- Swift standard library for JSON/XML parsing
- No external packages needed

**Code Changes**:
- New file: `providers.swift` (~300-500 lines)
- Modified: `commands.swift` (~50 lines added)
- Modified: `constants.swift` (~20 lines for config paths)
- Optional: `main.swift` for command-line flag parsing

---

## Integration Examples

### Example 1: GitHub Releases

**Configuration** (`~/.sdist_dynamic_providers.json`):
```json
{
  "providers": [
    {
      "name": "myapp-releases",
      "type": "github-releases",
      "repository": "myorg/myapp",
      "auth": "ghp_xxxxxxxxxxxxxxxxxxxx"
    }
  ]
}
```

**Usage**:
```bash
# List all releases
./sdist -c -p PASSWORD -f list -a --provider=myapp-releases

# Get download URL for specific release
./sdist -c -p PASSWORD -f get -a v1.2.3 --provider=myapp-releases

# Download a release asset
./sdist -c -p PASSWORD -f download -a v1.2.3 myapp.zip --provider=myapp-releases
```

### Example 2: S3 Bucket

**Configuration**:
```json
{
  "providers": [
    {
      "name": "s3-packages",
      "type": "s3-bucket",
      "bucketUrl": "https://my-packages.s3.amazonaws.com"
    }
  ]
}
```

**Usage**:
```bash
# List all objects in bucket
./sdist -c -p PASSWORD -f list -a --provider=s3-packages

# Download from S3
./sdist -c -p PASSWORD -f download -a path/to/file.zip output.zip --provider=s3-packages
```

### Example 3: Custom REST API

**Configuration**:
```json
{
  "providers": [
    {
      "name": "custom-api",
      "type": "rest-api",
      "endpoints": {
        "list": "https://api.example.com/v1/packages",
        "get": "https://api.example.com/v1/packages/{key}",
        "download": "https://cdn.example.com/files/{key}"
      },
      "responseFormat": "json",
      "listKeyPath": "packages[].name",
      "urlKeyPath": "download_url"
    }
  ]
}
```

---

## Alternative Approaches

### Approach 1: URL Rewriting (Simpler, Limited)

Instead of full provider support, add simple URL rewriting rules:

```json
{
  "urlRewrites": [
    {
      "pattern": "github:{owner}/{repo}/{tag}",
      "template": "https://github.com/{owner}/{repo}/releases/download/{tag}/"
    }
  ]
}
```

**Pros**: Very simple to implement (~1 day)
**Cons**: No dynamic listing, manual URL construction required

### Approach 2: Plugin System (Complex, Extensible)

Create a plugin architecture where providers are separate executables:

```bash
~/.sdist_plugins/
  github-provider
  s3-provider
  custom-provider
```

**Pros**: Maximum flexibility, third-party extensions
**Cons**: Complex, security concerns, harder to maintain

---

## Security Considerations

### Authentication

- **API Tokens**: Store in configuration file with proper file permissions (0600)
- **Environment Variables**: Support `${VARIABLE}` syntax in config for sensitive values
- **Keychain Integration**: On macOS, optionally store tokens in Keychain

### Validation

- **URL Validation**: Ensure dynamic URLs use HTTPS
- **Response Validation**: Verify JSON/XML structure before parsing
- **Rate Limiting**: Implement basic rate limiting for API calls
- **Error Handling**: Fail gracefully on network errors or invalid responses

### Permissions

- Dynamic providers should respect the same password authentication as the manifest server
- Consider adding a whitelist of allowed dynamic domains in configuration

---

## Migration Path

For users who want to move from static manifest to dynamic providers:

1. **Hybrid Mode**: Run both systems in parallel initially
   - Keep existing assets in manifest server
   - Add new assets via dynamic providers
   - Test dynamic providers with non-critical assets

2. **Gradual Migration**:
   - Identify assets that can be moved to external APIs
   - Update manifest entries to use `dynamic:` prefix
   - Verify functionality with existing workflows

3. **Full Migration** (optional):
   - Once stable, deprecate manifest server for certain asset types
   - Keep manifest server for legacy assets or as fallback

---

## Performance Considerations

### Caching

Implement simple response caching to reduce API calls:

```swift
class ProviderCache {
    var cache: [String: (data: Any, timestamp: Date)] = [:]
    let ttl: TimeInterval = 300 // 5 minutes
    
    func get(key: String) -> Any? {
        if let entry = cache[key] {
            if Date().timeIntervalSince(entry.timestamp) < ttl {
                return entry.data
            }
        }
        return nil
    }
}
```

### Parallel Requests

For listing operations, consider parallel requests if querying multiple providers:

```swift
func listAllProviders() throws -> [String: [String]] {
    let providers = DynamicProviderManager.shared.getAllProviders()
    let group = DispatchGroup()
    var results: [String: [String]] = [:]
    
    for provider in providers {
        group.enter()
        DispatchQueue.global().async {
            results[provider.name] = try? provider.listAssets()
            group.leave()
        }
    }
    
    group.wait()
    return results
}
```

---

## Testing Strategy

### Unit Tests

- Test each provider in isolation with mock responses
- Test response parsers with sample JSON/XML
- Test configuration loading and validation

### Integration Tests

- Test against real APIs (GitHub public repos, public S3 buckets)
- Test fallback to manifest server when provider unavailable
- Test error handling for network failures

### User Acceptance Testing

- Create example configurations for common use cases
- Test command-line interface with dynamic providers
- Verify backward compatibility with existing workflows

---

## Conclusion

Adding dynamic URL support to SDist is a **medium complexity** feature that would significantly enhance flexibility without breaking existing functionality. The recommended approach is:

1. **Start with Option A** (per-asset dynamic URLs with `dynamic:` prefix)
2. **Implement basic provider types** (GitHub, REST API, S3)
3. **Add configuration support** similar to existing cURL mods
4. **Keep it simple** - avoid over-engineering

**Estimated Timeline**: 3-5 days for a working implementation
**Risk Level**: Low (fully backward compatible)
**Value**: High (enables integration with existing ecosystems)

### Next Steps

1. Gather feedback on this design proposal
2. Prioritize which provider types to implement first
3. Create detailed implementation tasks
4. Begin development with the foundation layer
5. Iterate based on real-world testing

---

## Appendix: Code Structure

```
SDist/
├── SDist/
│   ├── main.swift              # Entry point (minor changes)
│   ├── commands.swift           # Command logic (modified)
│   ├── constants.swift          # Configuration (modified)
│   ├── providers.swift          # NEW: Provider protocol and implementations
│   ├── providerManager.swift   # NEW: Provider registry and loading
│   ├── responseAdapters.swift  # NEW: Response format parsing
│   ├── openssl.swift           # Unchanged
│   ├── secureEnclave.swift     # Unchanged
│   └── subprocesses.swift      # Unchanged (or minor additions)
├── DYNAMIC_URL_SUPPORT.md      # This document
└── README.md                   # Updated with dynamic provider docs
```

---

**Document Version**: 1.0  
**Date**: 2026-02-03  
**Author**: SDist Development Team

# File Search Store Management — Design Spec

**Date:** 2026-05-27
**Status:** Draft

## Summary

Add file search store (corpus) management to `InteractionsClient`. The spec-coach CLI needs to create, list, and delete Gemini file search stores, upload documents, and manage documents within stores via the API. These map to the `fileSearchStores` and `documents` REST resources at `generativelanguage.googleapis.com/v1beta`.

## Motivation

The spec-coach CLI uses a YAML reconciliation flow: it compares declared documents against what exists in a store, uploads missing ones, and removes stale ones. This requires store-level CRUD, document-level list/delete, and document upload with await-completion semantics.

## Scope

### In scope

- Store CRUD: create, list, get, delete
- Document management: list documents in a store, delete individual documents
- Upload documents directly to a store with await-completion (poll until indexed)
- All methods on `InteractionsClient` (same auth, same base URL)
- New file `FileSearchStores.swift`, no trait gate
- Unit tests with `MockURLProtocol`
- Spec file `Spec/what-filesearchstores.md`

### Out of scope

- Import from Files API (`importFile` endpoint)
- Get single document by name (list covers the CLI's needs)
- Streaming/chunking config on upload (use API defaults)
- Lazy/streaming pagination (auto-paginate and return full arrays)

## Types

### FileSearchStore

The store resource returned by the API.

```swift
public struct FileSearchStore: Codable, Sendable {
    public let name: String
    public let displayName: String?
    public let createTime: String?
    public let updateTime: String?
    public let activeDocumentsCount: String?
    public let pendingDocumentsCount: String?
    public let failedDocumentsCount: String?
    public let sizeBytes: String?
    public let embeddingModel: String?
}
```

CodingKeys: `display_name`, `create_time`, `update_time`, `active_documents_count`, `pending_documents_count`, `failed_documents_count`, `size_bytes`, `embedding_model`.

### FileSearchDocument

A document within a store.

```swift
public struct FileSearchDocument: Codable, Sendable {
    public let name: String
    public let displayName: String?
    public let customMetadata: [CustomMetadata]?
    public let updateTime: String?
    public let createTime: String?
    public let state: DocumentState?
    public let sizeBytes: String?
    public let mimeType: String?
}
```

CodingKeys: `display_name`, `custom_metadata`, `update_time`, `create_time`, `size_bytes`, `mime_type`.

### CustomMetadata

Key-value pairs on documents. Value is a union — exactly one of `stringValue`, `stringListValue`, or `numericValue` is set.

```swift
public struct CustomMetadata: Codable, Sendable {
    public let key: String
    public let stringValue: String?
    public let stringListValue: StringListValue?
    public let numericValue: Double?

    public struct StringListValue: Codable, Sendable {
        public let values: [String]
    }
}
```

CodingKeys: `string_value`, `string_list_value`, `numeric_value`.

### DocumentState

Lifecycle enum for documents.

```swift
public enum DocumentState: String, Codable, Sendable {
    case unspecified = "STATE_UNSPECIFIED"
    case pending = "STATE_PENDING"
    case active = "STATE_ACTIVE"
    case failed = "STATE_FAILED"
}
```

### Operation

Long-running operation response, used internally for upload polling.

```swift
public struct Operation: Codable, Sendable {
    public let name: String
    public let done: Bool?
    public let error: OperationError?

    public struct OperationError: Codable, Sendable {
        public let code: Int?
        public let message: String?
    }
}
```

## Client Methods

All methods added via `extension InteractionsClient` in `FileSearchStores.swift`.

### Store CRUD

```swift
public func createFileSearchStore(
    displayName: String? = nil,
    embeddingModel: String? = nil
) async throws -> FileSearchStore
```

POST to `/v1beta/fileSearchStores`. Request body contains `displayName` and `embeddingModel` if provided.

```swift
public func listFileSearchStores() async throws -> [FileSearchStore]
```

GET `/v1beta/fileSearchStores`. Auto-paginates using `pageSize=20` and `pageToken`. Returns the full array.

```swift
public func getFileSearchStore(name: String) async throws -> FileSearchStore
```

GET `/v1beta/{name}` where `name` is the full resource name (e.g. `fileSearchStores/my-store-123`).

```swift
public func deleteFileSearchStore(name: String, force: Bool = false) async throws
```

DELETE `/v1beta/{name}?force={force}`. Returns empty body on success.

### Document Management

```swift
public func listDocuments(inStore storeName: String) async throws -> [FileSearchDocument]
```

GET `/v1beta/{storeName}/documents`. Auto-paginates. Returns full array.

```swift
public func deleteDocument(name: String, force: Bool = false) async throws
```

DELETE `/v1beta/{name}?force={force}`. `name` is the full document resource name (e.g. `fileSearchStores/my-store-123/documents/doc-456`).

### Upload

```swift
public func uploadToFileSearchStore(
    storeName: String,
    data: Data,
    mimeType: String,
    displayName: String? = nil,
    customMetadata: [CustomMetadata]? = nil
) async throws -> FileSearchDocument
```

Uses Google's resumable upload protocol (two-step):

**Step 1 — Initiate upload (metadata request):**

POST to `/upload/v1beta/{storeName}:uploadToFileSearchStore` with headers:
- `X-Goog-Upload-Protocol: resumable`
- `X-Goog-Upload-Command: start`
- `X-Goog-Upload-Header-Content-Length: {data.count}`
- `X-Goog-Upload-Header-Content-Type: {mimeType}`
- `Content-Type: application/json`
- Standard auth headers (`x-goog-api-key`, `Api-Revision`)

Body: JSON with `displayName`, `customMetadata`, `mimeType` (if provided).

Response: Extract the upload URL from the `x-goog-upload-url` response header.

**Step 2 — Upload file bytes:**

POST to the upload URL from step 1 with headers:
- `X-Goog-Upload-Offset: 0`
- `X-Goog-Upload-Command: upload, finalize`
- `Content-Length: {data.count}`

Body: raw file bytes.

Response: an `Operation` object.

**Step 3 — Poll for completion:**

Poll `GET /v1beta/{operationName}` at 1-second intervals, timeout after 5 minutes.
- On `done == true` with `response`: extract and return the `FileSearchDocument`
- On `done == true` with `error`: throw `GeminiInteractionsError.httpError` with the error details

Note: `mimeType` is required (not optional) because the resumable upload protocol needs it in the initiation headers.

## URL Construction

New private helpers on `InteractionsClient`:

| Helper | URL |
|--------|-----|
| `fileSearchStoresURL()` | `{baseURL}/v1beta/fileSearchStores` |
| `fileSearchStoreURL(name:)` | `{baseURL}/v1beta/{name}` |
| `documentsURL(storeName:)` | `{baseURL}/v1beta/{storeName}/documents` |
| `documentURL(name:)` | `{baseURL}/v1beta/{name}` |
| `uploadInitiateURL(storeName:)` | `{baseURL}/upload/v1beta/{storeName}:uploadToFileSearchStore` |
| `operationURL(name:)` | `{baseURL}/v1beta/{name}` |

The `name` fields from the API are full resource paths (e.g. `fileSearchStores/my-store-123`), so URL construction appends them to `baseURL` directly.

Note: the upload endpoint uses `/upload/v1beta/` rather than `/v1beta/`.

## Error Handling

Follows the existing pattern:
- All `URLError` wrapped as `GeminiInteractionsError.networkError`
- All `DecodingError` wrapped as `.decodingError`
- HTTP 429 → `.rateLimitExceeded`
- Other non-2xx → `.httpError(statusCode:body:)`
- Upload operation errors (from `Operation.error`) → `.httpError` with the operation error code and message
- Upload timeout → `.httpError(statusCode: 0, body: "Upload operation timed out")`

## File Organization

| File | Contents |
|------|----------|
| `Sources/SwiftGeminiInteractions/FileSearchStores.swift` | All new types + `extension InteractionsClient` with store/document/upload methods |
| `Spec/what-filesearchstores.md` | Spec for all new types and methods |
| `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift` | Unit tests with MockURLProtocol |

No trait gate. No changes to `Core.swift` or `Package.swift`.

## Testing Strategy

Unit tests using `MockURLProtocol` (same pattern as existing tests):

- **Store CRUD:** Mock create/list/get/delete responses with canned JSON. Verify request URLs, methods, headers, and body encoding.
- **Document list/delete:** Mock paginated list responses (two pages), single delete response.
- **Upload flow:** Mock the operation response with `done: false` on first poll, `done: true` with document response on second poll. Verify polling behavior.
- **Error cases:** Mock HTTP error responses, operation errors, timeout scenarios.

Integration tests behind `RUN_INTEGRATION_TESTS=1` for live API validation.

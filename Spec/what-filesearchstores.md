---
status: alpha
---

# what-filesearchstores.md — File Search Store Types and Client Methods

## FileSearchStore
`public struct FileSearchStore: Codable, Sendable`. The store resource. Properties: `name: String`, `displayName: String?`, `createTime: String?`, `updateTime: String?`, `activeDocumentsCount: String?`, `pendingDocumentsCount: String?`, `failedDocumentsCount: String?`, `sizeBytes: String?`, `embeddingModel: String?`. JSON keys snake_case: `display_name`, `create_time`, `update_time`, `active_documents_count`, `pending_documents_count`, `failed_documents_count`, `size_bytes`, `embedding_model`.

## FileSearchDocument
`public struct FileSearchDocument: Codable, Sendable`. A document in a store. Properties: `name: String`, `displayName: String?`, `customMetadata: [CustomMetadata]?`, `updateTime: String?`, `createTime: String?`, `state: DocumentState?`, `sizeBytes: String?`, `mimeType: String?`. JSON keys snake_case: `display_name`, `custom_metadata`, `update_time`, `create_time`, `size_bytes`, `mime_type`.

## CustomMetadata
`public struct CustomMetadata: Codable, Sendable`. Key-value pair on documents. Value is a union — exactly one of three is set. Properties: `key: String`, `stringValue: String?`, `stringListValue: StringListValue?`, `numericValue: Double?`. JSON keys: `string_value`, `string_list_value`, `numeric_value`. Nested type `StringListValue` has `values: [String]`.

## DocumentState
`public enum DocumentState: String, Codable, Sendable`. Raw-value string enum. Cases: `unspecified` (`"STATE_UNSPECIFIED"`), `pending` (`"STATE_PENDING"`), `active` (`"STATE_ACTIVE"`), `failed` (`"STATE_FAILED"`).

## Operation
`struct Operation: Codable, Sendable`. Internal (not public). Long-running operation for upload polling. Properties: `name: String`, `done: Bool?`, `error: OperationError?`, `response: OperationResponse?`. Nested `OperationError`: `code: Int?`, `message: String?`. Nested `OperationResponse`: decoded from the `response` field which is a JSON object containing `@type` plus the `FileSearchDocument` fields — decoded by extracting the document fields directly.

## InteractionsClient extension (FileSearchStores.swift)

URL helpers (all internal):
- `fileSearchStoresURL() -> URL` — `{baseURL}/v1beta/fileSearchStores`
- `fileSearchStoreURL(name:) -> URL` — `{baseURL}/v1beta/{name}` where name is the full resource path
- `documentsURL(storeName:) -> URL` — `{baseURL}/v1beta/{storeName}/documents`
- `documentURL(name:) -> URL` — `{baseURL}/v1beta/{name}` where name is the full document resource path
- `uploadInitiateURL(storeName:) -> URL` — `{baseURL}/upload/v1beta/{storeName}:uploadToFileSearchStore`
- `operationURL(name:) -> URL` — `{baseURL}/v1beta/{name}` where name is the full operation resource path

Public methods:
- `createFileSearchStore(displayName:embeddingModel:) async throws -> FileSearchStore` — POST to `fileSearchStoresURL()`. Body: JSON with optional `displayName` and `embeddingModel`.
- `listFileSearchStores() async throws -> [FileSearchStore]` — GET `fileSearchStoresURL()` with `pageSize=20`. Auto-paginates via `pageToken`/`nextPageToken`. Returns full array.
- `getFileSearchStore(name:) async throws -> FileSearchStore` — GET `fileSearchStoreURL(name:)`.
- `deleteFileSearchStore(name:force:) async throws` — DELETE `fileSearchStoreURL(name:)` with `force` query parameter.
- `listDocuments(inStore:) async throws -> [FileSearchDocument]` — GET `documentsURL(storeName:)` with `pageSize=20`. Auto-paginates. Returns full array.
- `deleteDocument(name:force:) async throws` — DELETE `documentURL(name:)` with `force` query parameter.
- `uploadToFileSearchStore(storeName:data:mimeType:displayName:customMetadata:) async throws -> FileSearchDocument` — Three-phase: (1) POST metadata to `uploadInitiateURL` with `X-Goog-Upload-*` headers, extract `x-goog-upload-url` from response headers; (2) POST raw bytes to upload URL; (3) poll operation until done. Default poll interval 1s, timeout 5min.

# File Search Store Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add file search store CRUD, document management, and document upload to `InteractionsClient`.

**Architecture:** New file `FileSearchStores.swift` with types and an `extension InteractionsClient`. Requires widening access on a few private members in `Core.swift` so the cross-file extension can reach them, plus a new internal method that returns HTTP response headers (needed for the upload protocol). Project specs in `Spec/` are written first, then code is generated from them.

**Tech Stack:** Swift 6.3, Foundation (URLSession, JSONEncoder/Decoder), XCTest, MockURLProtocol

---

### Task 1: Write the project spec `Spec/what-filesearchstores.md`

**Files:**
- Create: `Spec/what-filesearchstores.md`

- [ ] **Step 1: Create the spec file**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add Spec/what-filesearchstores.md
git commit -m "spec: add what-filesearchstores.md"
```

---

### Task 2: Update `Spec/how-client.md` with file search store endpoints

**Files:**
- Modify: `Spec/how-client.md`

- [ ] **Step 1: Add file search store URL section and upload protocol section**

Append after the existing `RequestTimeout parameter` section:

```markdown

## File search store endpoints
File search store management lives under `v1beta/fileSearchStores` (not `v1beta/interactions`). URL helpers in `FileSearchStores.swift` construct paths against the same `baseURL`. The `name` fields from the API are full resource paths (e.g. `fileSearchStores/my-store-123`), so URL helpers append them directly to `{baseURL}/v1beta/`.

The upload endpoint uses a different path prefix: `{baseURL}/upload/v1beta/{storeName}:uploadToFileSearchStore` (note `/upload/` before `v1beta`).

List endpoints auto-paginate using `pageSize=20` query parameter and `pageToken`/`nextPageToken` fields. Both store and document list methods consume all pages and return a single array.

Delete endpoints accept a `force` boolean query parameter. When `force=true`, cascade-deletes child resources. When `force=false` (default), returns `FAILED_PRECONDITION` if the resource has children.

## Upload protocol
Document upload uses Google's resumable upload protocol (not multipart/related):

**Step 1 — Initiate:** POST to the upload URI with `Content-Type: application/json` body containing metadata fields (`displayName`, `customMetadata`, `mimeType`). Custom headers: `X-Goog-Upload-Protocol: resumable`, `X-Goog-Upload-Command: start`, `X-Goog-Upload-Header-Content-Length: {byteCount}`, `X-Goog-Upload-Header-Content-Type: {mimeType}`. Standard auth headers included. Response contains `x-goog-upload-url` header with the upload URL.

**Step 2 — Upload bytes:** POST raw file bytes to the upload URL from step 1. Headers: `X-Goog-Upload-Offset: 0`, `X-Goog-Upload-Command: upload, finalize`, `Content-Length: {byteCount}`. Response is an `Operation` JSON object.

**Step 3 — Poll:** GET the operation URL until `done == true`. On success, `response` contains the `FileSearchDocument`. On failure, `error` contains code and message. Poll interval: 1 second. Timeout: 5 minutes.

The initiation step requires `executeReturningResponse(_:)` (internal method on `InteractionsClient`) which returns `(Data, HTTPURLResponse)` so the caller can read the `x-goog-upload-url` response header. This method shares all error-handling logic with `execute(_:)`.
```

- [ ] **Step 2: Commit**

```bash
git add Spec/how-client.md
git commit -m "spec: add file search store endpoints and upload protocol to how-client.md"
```

---

### Task 3: Widen access levels in `Core.swift`

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Core.swift:1542-1621`

The `extension InteractionsClient` in `FileSearchStores.swift` needs access to members that are currently `private` in `Core.swift`. Swift's `private` is file-scoped, so cross-file extensions cannot see them. Change the following from `private` to internal (remove the `private` keyword):

- [ ] **Step 1: Change `baseURL` from private to internal**

In `Core.swift`, line 1545, change:
```swift
private let baseURL: URL
```
to:
```swift
let baseURL: URL
```

- [ ] **Step 2: Change `headers()` from private to internal**

In `Core.swift`, line 1572, change:
```swift
private func headers() -> [String: String] {
```
to:
```swift
func headers() -> [String: String] {
```

- [ ] **Step 3: Change `execute(_:)` from private to internal**

In `Core.swift`, line 1592, change:
```swift
private func execute(_ urlRequest: URLRequest) async throws -> Data {
```
to:
```swift
func execute(_ urlRequest: URLRequest) async throws -> Data {
```

- [ ] **Step 4: Change `decode(_:from:)` from private to internal**

In `Core.swift`, line 1613, change:
```swift
private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
```
to:
```swift
func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
```

- [ ] **Step 5: Add `executeReturningResponse(_:)` method**

Add this method immediately after `execute(_:)` (after line 1611), before the `decode` method:

```swift
func executeReturningResponse(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.data(for: urlRequest)
    } catch let urlError as URLError {
        throw GeminiInteractionsError.networkError(urlError)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response")
    }
    switch httpResponse.statusCode {
    case 200...299:
        return (data, httpResponse)
    case 429:
        throw GeminiInteractionsError.rateLimitExceeded
    default:
        let body = String(data: data, encoding: .utf8) ?? ""
        throw GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: body)
    }
}
```

- [ ] **Step 6: Build to verify no regressions**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds with no errors.

- [ ] **Step 7: Run existing tests to verify no regressions**

Run: `swift test 2>&1 | tail -20`
Expected: All existing tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Core.swift
git commit -m "refactor: widen access for cross-file InteractionsClient extension"
```

---

### Task 4: Types and decoding tests

**Files:**
- Create: `Sources/SwiftGeminiInteractions/FileSearchStores.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`

- [ ] **Step 1: Write the decoding tests**

Create `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`:

```swift
// Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class FileSearchStoreTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Type Decoding

    func testDecodeFileSearchStore() throws {
        let json = """
        {
            "name": "fileSearchStores/my-store-123",
            "displayName": "My Store",
            "createTime": "2026-05-27T10:00:00Z",
            "updateTime": "2026-05-27T10:00:00Z",
            "activeDocumentsCount": "5",
            "pendingDocumentsCount": "0",
            "failedDocumentsCount": "1",
            "sizeBytes": "1024",
            "embeddingModel": "models/gemini-embedding-2"
        }
        """.data(using: .utf8)!
        let store = try JSONDecoder().decode(FileSearchStore.self, from: json)
        XCTAssertEqual(store.name, "fileSearchStores/my-store-123")
        XCTAssertEqual(store.displayName, "My Store")
        XCTAssertEqual(store.activeDocumentsCount, "5")
        XCTAssertEqual(store.failedDocumentsCount, "1")
        XCTAssertEqual(store.sizeBytes, "1024")
        XCTAssertEqual(store.embeddingModel, "models/gemini-embedding-2")
    }

    func testDecodeFileSearchStoreMinimal() throws {
        let json = """
        {"name": "fileSearchStores/s-1"}
        """.data(using: .utf8)!
        let store = try JSONDecoder().decode(FileSearchStore.self, from: json)
        XCTAssertEqual(store.name, "fileSearchStores/s-1")
        XCTAssertNil(store.displayName)
        XCTAssertNil(store.embeddingModel)
    }

    func testDecodeFileSearchDocument() throws {
        let json = """
        {
            "name": "fileSearchStores/s-1/documents/doc-1",
            "displayName": "readme.txt",
            "customMetadata": [
                {"key": "author", "stringValue": "Alice"},
                {"key": "year", "numericValue": 2026}
            ],
            "createTime": "2026-05-27T10:00:00Z",
            "updateTime": "2026-05-27T10:00:00Z",
            "state": "STATE_ACTIVE",
            "sizeBytes": "512",
            "mimeType": "text/plain"
        }
        """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(FileSearchDocument.self, from: json)
        XCTAssertEqual(doc.name, "fileSearchStores/s-1/documents/doc-1")
        XCTAssertEqual(doc.displayName, "readme.txt")
        XCTAssertEqual(doc.state, .active)
        XCTAssertEqual(doc.mimeType, "text/plain")
        XCTAssertEqual(doc.customMetadata?.count, 2)
        XCTAssertEqual(doc.customMetadata?[0].key, "author")
        XCTAssertEqual(doc.customMetadata?[0].stringValue, "Alice")
        XCTAssertEqual(doc.customMetadata?[1].key, "year")
        XCTAssertEqual(doc.customMetadata?[1].numericValue, 2026)
    }

    func testDecodeDocumentState() throws {
        let json = """
        {"name": "fileSearchStores/s/documents/d", "state": "STATE_PENDING"}
        """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(FileSearchDocument.self, from: json)
        XCTAssertEqual(doc.state, .pending)
    }

    func testDecodeCustomMetadataStringList() throws {
        let json = """
        {"key": "tags", "stringListValue": {"values": ["swift", "api"]}}
        """.data(using: .utf8)!
        let meta = try JSONDecoder().decode(CustomMetadata.self, from: json)
        XCTAssertEqual(meta.key, "tags")
        XCTAssertEqual(meta.stringListValue?.values, ["swift", "api"])
        XCTAssertNil(meta.stringValue)
        XCTAssertNil(meta.numericValue)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: Compilation errors — `FileSearchStore`, `FileSearchDocument`, `CustomMetadata`, `DocumentState` are not defined yet.

- [ ] **Step 3: Write the types**

Create `Sources/SwiftGeminiInteractions/FileSearchStores.swift`:

```swift
// Sources/SwiftGeminiInteractions/FileSearchStores.swift
import Foundation

// MARK: - File Search Store Types

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

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case createTime = "create_time"
        case updateTime = "update_time"
        case activeDocumentsCount = "active_documents_count"
        case pendingDocumentsCount = "pending_documents_count"
        case failedDocumentsCount = "failed_documents_count"
        case sizeBytes = "size_bytes"
        case embeddingModel = "embedding_model"
    }
}

public struct FileSearchDocument: Codable, Sendable {
    public let name: String
    public let displayName: String?
    public let customMetadata: [CustomMetadata]?
    public let updateTime: String?
    public let createTime: String?
    public let state: DocumentState?
    public let sizeBytes: String?
    public let mimeType: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case customMetadata = "custom_metadata"
        case updateTime = "update_time"
        case createTime = "create_time"
        case state
        case sizeBytes = "size_bytes"
        case mimeType = "mime_type"
    }
}

public struct CustomMetadata: Codable, Sendable {
    public let key: String
    public let stringValue: String?
    public let stringListValue: StringListValue?
    public let numericValue: Double?

    public struct StringListValue: Codable, Sendable {
        public let values: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case stringValue = "string_value"
        case stringListValue = "string_list_value"
        case numericValue = "numeric_value"
    }
}

public enum DocumentState: String, Codable, Sendable {
    case unspecified = "STATE_UNSPECIFIED"
    case pending = "STATE_PENDING"
    case active = "STATE_ACTIVE"
    case failed = "STATE_FAILED"
}

struct Operation: Codable, Sendable {
    let name: String
    let done: Bool?
    let error: OperationError?
    let response: OperationResponse?

    struct OperationError: Codable, Sendable {
        let code: Int?
        let message: String?
    }

    struct OperationResponse: Codable, Sendable {
        let document: FileSearchDocument

        init(from decoder: any Decoder) throws {
            document = try FileSearchDocument(from: decoder)
        }

        func encode(to encoder: any Encoder) throws {
            try document.encode(to: encoder)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftGeminiInteractions/FileSearchStores.swift Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift
git commit -m "feat: add file search store types with decoding tests"
```

---

### Task 5: Store CRUD methods and tests

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/FileSearchStores.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`

- [ ] **Step 1: Write the store CRUD tests**

Add to `FileSearchStoreTests.swift`:

```swift
    // MARK: - Store CRUD

    func testCreateFileSearchStore() async throws {
        let responseJSON = """
        {
            "name": "fileSearchStores/new-store-abc",
            "displayName": "New Store",
            "createTime": "2026-05-27T10:00:00Z",
            "embeddingModel": "models/gemini-embedding-2"
        }
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let client = makeTestClient()
        let store = try await client.createFileSearchStore(displayName: "New Store", embeddingModel: "models/gemini-embedding-2")

        XCTAssertEqual(store.name, "fileSearchStores/new-store-abc")
        XCTAssertEqual(store.displayName, "New Store")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("fileSearchStores") ?? false)

        let body = requestBodyData(from: capturedRequest!)
        let bodyJSON = try JSONSerialization.jsonObject(with: body!) as! [String: String]
        XCTAssertEqual(bodyJSON["displayName"], "New Store")
        XCTAssertEqual(bodyJSON["embeddingModel"], "models/gemini-embedding-2")
    }

    func testListFileSearchStoresPaginated() async throws {
        let page1 = """
        {
            "fileSearchStores": [{"name": "fileSearchStores/s-1"}],
            "nextPageToken": "token-2"
        }
        """.data(using: .utf8)!
        let page2 = """
        {
            "fileSearchStores": [{"name": "fileSearchStores/s-2"}]
        }
        """.data(using: .utf8)!

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let data = callCount == 1 ? page1 : page2
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeTestClient()
        let stores = try await client.listFileSearchStores()

        XCTAssertEqual(stores.count, 2)
        XCTAssertEqual(stores[0].name, "fileSearchStores/s-1")
        XCTAssertEqual(stores[1].name, "fileSearchStores/s-2")
        XCTAssertEqual(callCount, 2)
    }

    func testGetFileSearchStore() async throws {
        let responseJSON = """
        {"name": "fileSearchStores/s-1", "displayName": "Store One"}
        """.data(using: .utf8)!

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let client = makeTestClient()
        let store = try await client.getFileSearchStore(name: "fileSearchStores/s-1")

        XCTAssertEqual(store.name, "fileSearchStores/s-1")
        XCTAssertTrue(capturedURL?.absoluteString.contains("fileSearchStores/s-1") ?? false)
    }

    func testDeleteFileSearchStore() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let client = makeTestClient()
        try await client.deleteFileSearchStore(name: "fileSearchStores/s-1", force: true)

        XCTAssertEqual(capturedRequest?.httpMethod, "DELETE")
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("force=true") ?? false)
    }

    func testDeleteFileSearchStoreDefaultForce() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let client = makeTestClient()
        try await client.deleteFileSearchStore(name: "fileSearchStores/s-1")

        XCTAssertTrue(capturedURL?.absoluteString.contains("force=false") ?? false)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: Compilation errors — `createFileSearchStore`, `listFileSearchStores`, etc. not defined.

- [ ] **Step 3: Write the store CRUD methods**

Add to `FileSearchStores.swift`, at the bottom of the file:

```swift
// MARK: - URL Helpers

extension InteractionsClient {

    func fileSearchStoresURL() -> URL {
        baseURL.appendingPathComponent("v1beta/fileSearchStores")
    }

    func fileSearchStoreURL(name: String) -> URL {
        baseURL.appendingPathComponent("v1beta").appendingPathComponent(name)
    }

    func documentsURL(storeName: String) -> URL {
        baseURL.appendingPathComponent("v1beta").appendingPathComponent(storeName).appendingPathComponent("documents")
    }

    func documentURL(name: String) -> URL {
        baseURL.appendingPathComponent("v1beta").appendingPathComponent(name)
    }

    func uploadInitiateURL(storeName: String) -> URL {
        baseURL.appendingPathComponent("upload/v1beta").appendingPathComponent(storeName + ":uploadToFileSearchStore")
    }

    func operationURL(name: String) -> URL {
        baseURL.appendingPathComponent("v1beta").appendingPathComponent(name)
    }
}

// MARK: - Store CRUD

extension InteractionsClient {

    public func createFileSearchStore(
        displayName: String? = nil,
        embeddingModel: String? = nil
    ) async throws -> FileSearchStore {
        var bodyDict: [String: String] = [:]
        if let displayName { bodyDict["displayName"] = displayName }
        if let embeddingModel { bodyDict["embeddingModel"] = embeddingModel }
        let body = try encode(bodyDict)
        let urlRequest = makeRequest(url: fileSearchStoresURL(), method: "POST", body: body)
        let data = try await execute(urlRequest)
        return try decode(FileSearchStore.self, from: data)
    }

    public func listFileSearchStores() async throws -> [FileSearchStore] {
        var allStores: [FileSearchStore] = []
        var pageToken: String? = nil
        repeat {
            var url = fileSearchStoresURL()
            var queryItems = [URLQueryItem(name: "pageSize", value: "20")]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            url = url.appending(queryItems: queryItems)
            let urlRequest = makeRequest(url: url, method: "GET")
            let data = try await execute(urlRequest)
            let page = try decode(FileSearchStoreListResponse.self, from: data)
            allStores.append(contentsOf: page.fileSearchStores ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return allStores
    }

    public func getFileSearchStore(name: String) async throws -> FileSearchStore {
        let urlRequest = makeRequest(url: fileSearchStoreURL(name: name), method: "GET")
        let data = try await execute(urlRequest)
        return try decode(FileSearchStore.self, from: data)
    }

    public func deleteFileSearchStore(name: String, force: Bool = false) async throws {
        var url = fileSearchStoreURL(name: name)
        url = url.appending(queryItems: [URLQueryItem(name: "force", value: "\(force)")])
        let urlRequest = makeRequest(url: url, method: "DELETE")
        _ = try await execute(urlRequest)
    }
}

// MARK: - List Response Wrappers

struct FileSearchStoreListResponse: Codable, Sendable {
    let fileSearchStores: [FileSearchStore]?
    let nextPageToken: String?

    private enum CodingKeys: String, CodingKey {
        case fileSearchStores
        case nextPageToken
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: All store CRUD tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftGeminiInteractions/FileSearchStores.swift Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift
git commit -m "feat: add file search store CRUD methods"
```

---

### Task 6: Document management methods and tests

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/FileSearchStores.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`

- [ ] **Step 1: Write the document management tests**

Add to `FileSearchStoreTests.swift`:

```swift
    // MARK: - Document Management

    func testListDocumentsPaginated() async throws {
        let page1 = """
        {
            "documents": [{"name": "fileSearchStores/s-1/documents/d-1", "state": "STATE_ACTIVE"}],
            "nextPageToken": "tok-2"
        }
        """.data(using: .utf8)!
        let page2 = """
        {
            "documents": [{"name": "fileSearchStores/s-1/documents/d-2", "state": "STATE_ACTIVE"}]
        }
        """.data(using: .utf8)!

        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            let data = callCount == 1 ? page1 : page2
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeTestClient()
        let docs = try await client.listDocuments(inStore: "fileSearchStores/s-1")

        XCTAssertEqual(docs.count, 2)
        XCTAssertEqual(docs[0].name, "fileSearchStores/s-1/documents/d-1")
        XCTAssertEqual(docs[1].name, "fileSearchStores/s-1/documents/d-2")
        XCTAssertEqual(callCount, 2)
    }

    func testListDocumentsEmpty() async throws {
        let json = """
        {}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = makeTestClient()
        let docs = try await client.listDocuments(inStore: "fileSearchStores/s-1")

        XCTAssertEqual(docs.count, 0)
    }

    func testDeleteDocument() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "{}".data(using: .utf8)!)
        }

        let client = makeTestClient()
        try await client.deleteDocument(name: "fileSearchStores/s-1/documents/d-1", force: true)

        XCTAssertEqual(capturedRequest?.httpMethod, "DELETE")
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("documents/d-1") ?? false)
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("force=true") ?? false)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: Compilation errors — `listDocuments`, `deleteDocument` not defined.

- [ ] **Step 3: Write the document management methods**

Add to `FileSearchStores.swift`:

```swift
// MARK: - Document Management

extension InteractionsClient {

    public func listDocuments(inStore storeName: String) async throws -> [FileSearchDocument] {
        var allDocs: [FileSearchDocument] = []
        var pageToken: String? = nil
        repeat {
            var url = documentsURL(storeName: storeName)
            var queryItems = [URLQueryItem(name: "pageSize", value: "20")]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            url = url.appending(queryItems: queryItems)
            let urlRequest = makeRequest(url: url, method: "GET")
            let data = try await execute(urlRequest)
            let page = try decode(FileSearchDocumentListResponse.self, from: data)
            allDocs.append(contentsOf: page.documents ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return allDocs
    }

    public func deleteDocument(name: String, force: Bool = false) async throws {
        var url = documentURL(name: name)
        url = url.appending(queryItems: [URLQueryItem(name: "force", value: "\(force)")])
        let urlRequest = makeRequest(url: url, method: "DELETE")
        _ = try await execute(urlRequest)
    }
}

struct FileSearchDocumentListResponse: Codable, Sendable {
    let documents: [FileSearchDocument]?
    let nextPageToken: String?

    private enum CodingKeys: String, CodingKey {
        case documents
        case nextPageToken
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: All document management tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftGeminiInteractions/FileSearchStores.swift Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift
git commit -m "feat: add document list and delete methods"
```

---

### Task 7: Upload with polling and tests

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/FileSearchStores.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`

- [ ] **Step 1: Write the upload tests**

Add to `FileSearchStoreTests.swift`:

```swift
    // MARK: - Upload

    func testUploadToFileSearchStore() async throws {
        let operationJSON = """
        {"name": "fileSearchStores/s-1/upload/operations/op-1", "done": false}
        """.data(using: .utf8)!
        let doneOperationJSON = """
        {
            "name": "fileSearchStores/s-1/upload/operations/op-1",
            "done": true,
            "response": {
                "@type": "type.googleapis.com/google.ai.generativelanguage.v1beta.Document",
                "name": "fileSearchStores/s-1/documents/doc-new",
                "displayName": "test.txt",
                "state": "STATE_ACTIVE",
                "mimeType": "text/plain"
            }
        }
        """.data(using: .utf8)!

        let uploadURL = "https://storage.googleapis.com/upload/abc123"
        var requestIndex = 0
        MockURLProtocol.requestHandler = { request in
            requestIndex += 1
            switch requestIndex {
            case 1:
                // Step 1: Initiate upload — return upload URL in header
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["x-goog-upload-url": uploadURL]
                )!
                return (response, "{}".data(using: .utf8)!)
            case 2:
                // Step 2: Upload bytes — return operation
                XCTAssertEqual(request.url?.absoluteString, uploadURL)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "upload, finalize")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, operationJSON)
            case 3:
                // Step 3: Poll — still not done
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, operationJSON)
            default:
                // Step 3 again: Poll — done
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, doneOperationJSON)
            }
        }

        let client = makeTestClient()
        let doc = try await client.uploadToFileSearchStore(
            storeName: "fileSearchStores/s-1",
            data: "hello world".data(using: .utf8)!,
            mimeType: "text/plain",
            displayName: "test.txt"
        )

        XCTAssertEqual(doc.name, "fileSearchStores/s-1/documents/doc-new")
        XCTAssertEqual(doc.displayName, "test.txt")
        XCTAssertEqual(doc.state, .active)
        XCTAssertEqual(requestIndex, 4)
    }

    func testUploadInitiateHeaders() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            if capturedRequest == nil { capturedRequest = request }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-goog-upload-url": "https://example.com/upload"]
            )!
            let doneOp = """
            {
                "name": "op-1", "done": true,
                "response": {"name": "fileSearchStores/s/documents/d", "state": "STATE_ACTIVE"}
            }
            """.data(using: .utf8)!
            return (response, doneOp)
        }

        let client = makeTestClient()
        let fileData = Data(repeating: 0x41, count: 100)
        _ = try await client.uploadToFileSearchStore(
            storeName: "fileSearchStores/s-1",
            data: fileData,
            mimeType: "application/pdf"
        )

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Goog-Upload-Protocol"), "resumable")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Goog-Upload-Command"), "start")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length"), "100")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type"), "application/pdf")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(capturedRequest?.url?.absoluteString.contains("upload/v1beta") ?? false)
    }

    func testUploadOperationError() async throws {
        let errorOp = """
        {
            "name": "op-1", "done": true,
            "error": {"code": 400, "message": "Invalid file format"}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-goog-upload-url": "https://example.com/upload"]
            )!
            return (response, errorOp)
        }

        let client = makeTestClient()
        do {
            _ = try await client.uploadToFileSearchStore(
                storeName: "fileSearchStores/s-1",
                data: "data".data(using: .utf8)!,
                mimeType: "text/plain"
            )
            XCTFail("Expected error")
        } catch let error as GeminiInteractionsError {
            if case .httpError(let code, let body) = error {
                XCTAssertEqual(code, 400)
                XCTAssertTrue(body.contains("Invalid file format"))
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: Compilation errors — `uploadToFileSearchStore` not defined.

- [ ] **Step 3: Write the upload method**

Add to `FileSearchStores.swift`:

```swift
// MARK: - Upload

extension InteractionsClient {

    public func uploadToFileSearchStore(
        storeName: String,
        data: Data,
        mimeType: String,
        displayName: String? = nil,
        customMetadata: [CustomMetadata]? = nil,
        pollInterval: Duration = .seconds(1),
        timeout: Duration = .seconds(300)
    ) async throws -> FileSearchDocument {
        // Step 1: Initiate upload
        let initiateURL = uploadInitiateURL(storeName: storeName)
        var initiateRequest = makeRequest(url: initiateURL, method: "POST", body: try encode(
            UploadMetadata(displayName: displayName, customMetadata: customMetadata, mimeType: mimeType)
        ))
        initiateRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        initiateRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        initiateRequest.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        initiateRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")

        let (_, initiateResponse) = try await executeReturningResponse(initiateRequest)
        guard let uploadURLString = initiateResponse.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiInteractionsError.httpError(statusCode: 0, body: "Missing x-goog-upload-url header in initiation response")
        }

        // Step 2: Upload bytes
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.httpBody = data
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        let uploadData = try await execute(uploadRequest)
        var operation = try decode(Operation.self, from: uploadData)

        // Step 3: Poll for completion
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while operation.done != true {
            if clock.now >= deadline {
                throw GeminiInteractionsError.httpError(statusCode: 0, body: "Upload operation timed out")
            }
            let remaining = deadline - clock.now
            try await Task.sleep(for: min(pollInterval, remaining))
            let pollRequest = makeRequest(url: operationURL(name: operation.name), method: "GET")
            let pollData = try await execute(pollRequest)
            operation = try decode(Operation.self, from: pollData)
        }

        if let error = operation.error {
            throw GeminiInteractionsError.httpError(
                statusCode: error.code ?? 0,
                body: error.message ?? "Upload operation failed"
            )
        }

        guard let response = operation.response else {
            throw GeminiInteractionsError.httpError(statusCode: 0, body: "Upload operation completed without response")
        }

        return response.document
    }
}

struct UploadMetadata: Codable, Sendable {
    let displayName: String?
    let customMetadata: [CustomMetadata]?
    let mimeType: String?

    private enum CodingKeys: String, CodingKey {
        case displayName
        case customMetadata
        case mimeType
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileSearchStoreTests 2>&1 | tail -10`
Expected: All upload tests pass.

- [ ] **Step 5: Run the full test suite to verify no regressions**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftGeminiInteractions/FileSearchStores.swift Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift
git commit -m "feat: add document upload with resumable upload protocol and polling"
```

---

### Task 8: Final verification

**Files:** (none — read-only checks)

- [ ] **Step 1: Verify all tests pass**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass, including all existing tests and all new FileSearchStoreTests.

- [ ] **Step 2: Verify the build succeeds on all platforms**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Verify file organization matches the design spec**

Check that these files exist:
- `Sources/SwiftGeminiInteractions/FileSearchStores.swift`
- `Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift`
- `Spec/what-filesearchstores.md`

Run: `ls -la Sources/SwiftGeminiInteractions/FileSearchStores.swift Tests/SwiftGeminiInteractionsTests/FileSearchStoreTests.swift Spec/what-filesearchstores.md`
Expected: All three files exist.

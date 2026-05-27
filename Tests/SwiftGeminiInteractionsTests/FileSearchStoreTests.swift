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
            "display_name": "My Store",
            "create_time": "2026-05-27T10:00:00Z",
            "update_time": "2026-05-27T10:00:00Z",
            "active_documents_count": "5",
            "pending_documents_count": "0",
            "failed_documents_count": "1",
            "size_bytes": "1024",
            "embedding_model": "models/gemini-embedding-2"
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
            "display_name": "readme.txt",
            "custom_metadata": [
                {"key": "author", "string_value": "Alice"},
                {"key": "year", "numeric_value": 2026}
            ],
            "create_time": "2026-05-27T10:00:00Z",
            "update_time": "2026-05-27T10:00:00Z",
            "state": "STATE_ACTIVE",
            "size_bytes": "512",
            "mime_type": "text/plain"
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
        {"key": "tags", "string_list_value": {"values": ["swift", "api"]}}
        """.data(using: .utf8)!
        let meta = try JSONDecoder().decode(CustomMetadata.self, from: json)
        XCTAssertEqual(meta.key, "tags")
        XCTAssertEqual(meta.stringListValue?.values, ["swift", "api"])
        XCTAssertNil(meta.stringValue)
        XCTAssertNil(meta.numericValue)
    }

    // MARK: - Store CRUD

    func testCreateFileSearchStore() async throws {
        let responseJSON = """
        {
            "name": "fileSearchStores/new-store-abc",
            "display_name": "New Store",
            "create_time": "2026-05-27T10:00:00Z",
            "embedding_model": "models/gemini-embedding-2"
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
        {"name": "fileSearchStores/s-1", "display_name": "Store One"}
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
}

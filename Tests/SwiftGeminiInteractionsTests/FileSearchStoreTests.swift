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
                "display_name": "test.txt",
                "state": "STATE_ACTIVE",
                "mime_type": "text/plain"
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
            displayName: "test.txt",
            pollInterval: .milliseconds(10)
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
            mimeType: "application/pdf",
            pollInterval: .milliseconds(10)
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
                mimeType: "text/plain",
                pollInterval: .milliseconds(10)
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
}

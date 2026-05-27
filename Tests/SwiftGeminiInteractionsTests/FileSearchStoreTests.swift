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

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

    private enum CodingKeys: String, CodingKey {
        case key
        case stringValue = "string_value"
        case stringListValue = "string_list_value"
        case numericValue = "numeric_value"
    }

    public struct StringListValue: Codable, Sendable {
        public let values: [String]
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

// MARK: - List Response Wrappers

struct FileSearchStoreListResponse: Codable, Sendable {
    let fileSearchStores: [FileSearchStore]?
    let nextPageToken: String?

    private enum CodingKeys: String, CodingKey {
        case fileSearchStores
        case nextPageToken
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

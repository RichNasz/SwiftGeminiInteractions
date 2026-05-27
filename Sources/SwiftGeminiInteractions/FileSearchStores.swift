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

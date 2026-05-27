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
}

public struct CustomMetadata: Codable, Sendable {
    public let key: String
    public let stringValue: String?
    public let stringListValue: StringListValue?
    public let numericValue: Double?

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

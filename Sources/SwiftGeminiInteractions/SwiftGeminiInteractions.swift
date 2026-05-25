// Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
import Foundation
import SwiftLLMToolMacros

public enum InteractionStatus: String, Codable, Sendable {
    case inProgress     = "in_progress"
    case requiresAction = "requires_action"
    case completed      = "completed"
    case failed         = "failed"
    case cancelled      = "cancelled"
    case incomplete     = "incomplete"
    case budgetExceeded = "budget_exceeded"
}

public enum ServiceTier: String, Codable, Sendable {
    case flex, standard, priority
}

public enum ResponseModality: String, Codable, Sendable {
    case text, image, audio, video, document
}

public enum ThinkingLevel: String, Codable, Sendable {
    case none, low, medium, high
}

public enum ThinkingSummaries: String, Codable, Sendable {
    case enabled, disabled
}

public enum ToolChoiceMode: String, Codable, Sendable {
    case auto, none, required
}

public struct ToolChoiceConfig: Codable, Sendable {
    public let mode: ToolChoiceMode
    public let allowedTools: [String]?

    public init(mode: ToolChoiceMode, allowedTools: [String]? = nil) {
        self.mode = mode
        self.allowedTools = allowedTools
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case allowedTools = "allowed_tools"
    }
}

public struct ModalityTokens: Codable, Sendable {
    public let modality: String
    public let tokens: Int

    public init(modality: String, tokens: Int) {
        self.modality = modality
        self.tokens = tokens
    }
}

public enum Annotation: Codable, Sendable {
    case urlCitation(url: String, title: String?, startIndex: Int, endIndex: Int)
    case fileCitation(documentUri: String, fileName: String, source: String, pageNumber: Int?, startIndex: Int, endIndex: Int)
    case placeCitation(name: String, startIndex: Int, endIndex: Int)

    private enum CodingKeys: String, CodingKey {
        case type, url, title, source, name
        case startIndex  = "start_index"
        case endIndex    = "end_index"
        case documentUri = "document_uri"
        case fileName    = "file_name"
        case pageNumber  = "page_number"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "url_citation":
            self = .urlCitation(
                url: try container.decode(String.self, forKey: .url),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                startIndex: try container.decode(Int.self, forKey: .startIndex),
                endIndex: try container.decode(Int.self, forKey: .endIndex)
            )
        case "file_citation":
            self = .fileCitation(
                documentUri: try container.decode(String.self, forKey: .documentUri),
                fileName: try container.decode(String.self, forKey: .fileName),
                source: try container.decode(String.self, forKey: .source),
                pageNumber: try container.decodeIfPresent(Int.self, forKey: .pageNumber),
                startIndex: try container.decode(Int.self, forKey: .startIndex),
                endIndex: try container.decode(Int.self, forKey: .endIndex)
            )
        case "place_citation":
            self = .placeCitation(
                name: try container.decode(String.self, forKey: .name),
                startIndex: try container.decode(Int.self, forKey: .startIndex),
                endIndex: try container.decode(Int.self, forKey: .endIndex)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown annotation type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .urlCitation(let url, let title, let start, let end):
            try container.encode("url_citation", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encode(start, forKey: .startIndex)
            try container.encode(end, forKey: .endIndex)
        case .fileCitation(let uri, let name, let source, let page, let start, let end):
            try container.encode("file_citation", forKey: .type)
            try container.encode(uri, forKey: .documentUri)
            try container.encode(name, forKey: .fileName)
            try container.encode(source, forKey: .source)
            try container.encodeIfPresent(page, forKey: .pageNumber)
            try container.encode(start, forKey: .startIndex)
            try container.encode(end, forKey: .endIndex)
        case .placeCitation(let name, let start, let end):
            try container.encode("place_citation", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(start, forKey: .startIndex)
            try container.encode(end, forKey: .endIndex)
        }
    }
}

public enum Content: Codable, Sendable {
    case text(String, annotations: [Annotation]?)
    case image(data: Data?, mimeType: String?, uri: String?)
    case document(data: Data?, mimeType: String?, uri: String?)
    case video(data: Data?, mimeType: String?, uri: String?)

    private enum CodingKeys: String, CodingKey {
        case type, text, data, annotations, uri
        case mimeType = "mime_type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(
                try container.decode(String.self, forKey: .text),
                annotations: try container.decodeIfPresent([Annotation].self, forKey: .annotations)
            )
        case "image":
            self = .image(
                data: try container.decodeIfPresent(Data.self, forKey: .data),
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType),
                uri: try container.decodeIfPresent(String.self, forKey: .uri)
            )
        case "document":
            self = .document(
                data: try container.decodeIfPresent(Data.self, forKey: .data),
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType),
                uri: try container.decodeIfPresent(String.self, forKey: .uri)
            )
        case "video":
            self = .video(
                data: try container.decodeIfPresent(Data.self, forKey: .data),
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType),
                uri: try container.decodeIfPresent(String.self, forKey: .uri)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let annotations):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(annotations, forKey: .annotations)
        case .image(let data, let mimeType, let uri):
            try container.encode("image", forKey: .type)
            try container.encodeIfPresent(data, forKey: .data)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(uri, forKey: .uri)
        case .document(let data, let mimeType, let uri):
            try container.encode("document", forKey: .type)
            try container.encodeIfPresent(data, forKey: .data)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(uri, forKey: .uri)
        case .video(let data, let mimeType, let uri):
            try container.encode("video", forKey: .type)
            try container.encodeIfPresent(data, forKey: .data)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(uri, forKey: .uri)
        }
    }
}

public struct Usage: Codable, Sendable {
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalThoughtTokens: Int
    public let totalCachedTokens: Int
    public let totalToolUseTokens: Int
    public let totalTokens: Int
    public let inputTokensByModality: [ModalityTokens]

    public init(
        totalInputTokens: Int, totalOutputTokens: Int, totalThoughtTokens: Int,
        totalCachedTokens: Int, totalToolUseTokens: Int, totalTokens: Int,
        inputTokensByModality: [ModalityTokens]
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalThoughtTokens = totalThoughtTokens
        self.totalCachedTokens = totalCachedTokens
        self.totalToolUseTokens = totalToolUseTokens
        self.totalTokens = totalTokens
        self.inputTokensByModality = inputTokensByModality
    }

    private enum CodingKeys: String, CodingKey {
        case totalInputTokens    = "total_input_tokens"
        case totalOutputTokens   = "total_output_tokens"
        case totalThoughtTokens  = "total_thought_tokens"
        case totalCachedTokens   = "total_cached_tokens"
        case totalToolUseTokens  = "total_tool_use_tokens"
        case totalTokens         = "total_tokens"
        case inputTokensByModality = "input_tokens_by_modality"
    }
}

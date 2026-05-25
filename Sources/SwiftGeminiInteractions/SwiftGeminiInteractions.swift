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

public struct GoogleSearchResult: Codable, Sendable {
    public let title: String?
    public let url: String?
    public let snippet: String?

    public init(title: String? = nil, url: String? = nil, snippet: String? = nil) {
        self.title = title; self.url = url; self.snippet = snippet
    }

    private enum CodingKeys: String, CodingKey {
        case title, url, snippet
    }
}

public struct FileSearchResult: Codable, Sendable {
    public let fileId: String?
    public let fileName: String?
    public let snippet: String?
    public let score: Double?

    public init(fileId: String? = nil, fileName: String? = nil, snippet: String? = nil, score: Double? = nil) {
        self.fileId = fileId; self.fileName = fileName; self.snippet = snippet; self.score = score
    }

    private enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
        case snippet, score
    }
}

public enum Step: Codable, Sendable {
    case userInput(content: [Content])
    case modelOutput(content: [Content])
    case thought(content: [Content], summary: String?)
    case functionCall(id: String, name: String, arguments: String)
    case functionResult(callId: String, result: String, name: String?, isError: Bool?)
    case codeExecutionCall(id: String, code: String)
    case codeExecutionResult(callId: String, output: String, isError: Bool?)
    case googleSearchCall(id: String)
    case googleSearchResult(callId: String, results: [GoogleSearchResult])
    case urlContextCall(id: String, urls: [String])
    case urlContextResult(callId: String, content: String)
    case mcpToolCall(id: String, name: String, arguments: String)
    case mcpToolResult(callId: String, result: String)
    case fileSearchCall(id: String)
    case fileSearchResult(callId: String, results: [FileSearchResult])
    case googleMapsCall(id: String)
    case googleMapsResult(callId: String, result: String)

    private enum CodingKeys: String, CodingKey {
        case type, id, name, content, summary, arguments, result
        case callId  = "call_id"
        case isError = "is_error"
        case code, output, results, urls
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "user_input":
            self = .userInput(content: try container.decode([Content].self, forKey: .content))
        case "model_output":
            self = .modelOutput(content: try container.decode([Content].self, forKey: .content))
        case "thought":
            self = .thought(
                content: try container.decode([Content].self, forKey: .content),
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "function_call":
            self = .functionCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: try container.decode(String.self, forKey: .arguments)
            )
        case "function_result":
            self = .functionResult(
                callId: try container.decode(String.self, forKey: .callId),
                result: try container.decode(String.self, forKey: .result),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                isError: try container.decodeIfPresent(Bool.self, forKey: .isError)
            )
        case "code_execution_call":
            self = .codeExecutionCall(
                id: try container.decode(String.self, forKey: .id),
                code: try container.decode(String.self, forKey: .code)
            )
        case "code_execution_result":
            self = .codeExecutionResult(
                callId: try container.decode(String.self, forKey: .callId),
                output: try container.decode(String.self, forKey: .output),
                isError: try container.decodeIfPresent(Bool.self, forKey: .isError)
            )
        case "google_search_call":
            self = .googleSearchCall(id: try container.decode(String.self, forKey: .id))
        case "google_search_result":
            self = .googleSearchResult(
                callId: try container.decode(String.self, forKey: .callId),
                results: try container.decode([GoogleSearchResult].self, forKey: .results)
            )
        case "url_context_call":
            self = .urlContextCall(
                id: try container.decode(String.self, forKey: .id),
                urls: try container.decode([String].self, forKey: .urls)
            )
        case "url_context_result":
            self = .urlContextResult(
                callId: try container.decode(String.self, forKey: .callId),
                content: try container.decode(String.self, forKey: .content)
            )
        case "mcp_server_tool_call":
            self = .mcpToolCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: try container.decode(String.self, forKey: .arguments)
            )
        case "mcp_server_tool_result":
            self = .mcpToolResult(
                callId: try container.decode(String.self, forKey: .callId),
                result: try container.decode(String.self, forKey: .result)
            )
        case "file_search_call":
            self = .fileSearchCall(id: try container.decode(String.self, forKey: .id))
        case "file_search_result":
            self = .fileSearchResult(
                callId: try container.decode(String.self, forKey: .callId),
                results: try container.decode([FileSearchResult].self, forKey: .results)
            )
        case "google_maps_call":
            self = .googleMapsCall(id: try container.decode(String.self, forKey: .id))
        case "google_maps_result":
            self = .googleMapsResult(
                callId: try container.decode(String.self, forKey: .callId),
                result: try container.decode(String.self, forKey: .result)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown step type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userInput(let content):
            try container.encode("user_input", forKey: .type)
            try container.encode(content, forKey: .content)
        case .modelOutput(let content):
            try container.encode("model_output", forKey: .type)
            try container.encode(content, forKey: .content)
        case .thought(let content, let summary):
            try container.encode("thought", forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(summary, forKey: .summary)
        case .functionCall(let id, let name, let arguments):
            try container.encode("function_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionResult(let callId, let result, let name, let isError):
            try container.encode("function_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(result, forKey: .result)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(isError, forKey: .isError)
        case .codeExecutionCall(let id, let code):
            try container.encode("code_execution_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(code, forKey: .code)
        case .codeExecutionResult(let callId, let output, let isError):
            try container.encode("code_execution_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(output, forKey: .output)
            try container.encodeIfPresent(isError, forKey: .isError)
        case .googleSearchCall(let id):
            try container.encode("google_search_call", forKey: .type)
            try container.encode(id, forKey: .id)
        case .googleSearchResult(let callId, let results):
            try container.encode("google_search_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(results, forKey: .results)
        case .urlContextCall(let id, let urls):
            try container.encode("url_context_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(urls, forKey: .urls)
        case .urlContextResult(let callId, let content):
            try container.encode("url_context_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(content, forKey: .content)
        case .mcpToolCall(let id, let name, let arguments):
            try container.encode("mcp_server_tool_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .mcpToolResult(let callId, let result):
            try container.encode("mcp_server_tool_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(result, forKey: .result)
        case .fileSearchCall(let id):
            try container.encode("file_search_call", forKey: .type)
            try container.encode(id, forKey: .id)
        case .fileSearchResult(let callId, let results):
            try container.encode("file_search_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(results, forKey: .results)
        case .googleMapsCall(let id):
            try container.encode("google_maps_call", forKey: .type)
            try container.encode(id, forKey: .id)
        case .googleMapsResult(let callId, let result):
            try container.encode("google_maps_result", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(result, forKey: .result)
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

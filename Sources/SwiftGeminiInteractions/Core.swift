// Sources/SwiftGeminiInteractions/Core.swift
import Foundation
@_exported import SwiftLLMToolMacros

// MARK: - GeminiInteractionsError

/// Errors thrown by all SwiftGeminiInteractions public API methods.
public enum GeminiInteractionsError: Error, LocalizedError, @unchecked Sendable {
    /// Network connectivity failure (no internet, DNS resolution, timeout).
    case networkError(URLError)
    /// Non-2xx HTTP response. HTTP 429 is reported as `.rateLimitExceeded` instead.
    case httpError(statusCode: Int, body: String)
    /// HTTP 429 rate limit. Retry after a short delay.
    case rateLimitExceeded
    /// Failed to decode a response from the API.
    case decodingError(DecodingError)
    /// Failed to encode a request for the API.
    case encodingError(EncodingError)
    /// Invalid input provided by the caller.
    case invalidInput(String)
    /// A tool handler threw an error during execution.
    case toolExecutionFailed(name: String, error: any Error)
    /// Tool loop exceeded the configured maximum iteration count.
    case maxIterationsExceeded(Int)
    /// Background poll timed out waiting for completion.
    case pollTimeout(id: String)
    /// Interaction ended in a failure state.
    case interactionFailed(id: String, status: InteractionStatus)

    public var errorDescription: String? {
        switch self {
        case .networkError(let e):             return "Network error: \(e.localizedDescription)"
        case .httpError(let code, let body):   return "HTTP \(code): \(body)"
        case .rateLimitExceeded:               return "Rate limit exceeded. Retry after a short delay."
        case .decodingError(let e):            return "Failed to decode response: \(e.localizedDescription)"
        case .encodingError(let e):            return "Failed to encode request: \(e.localizedDescription)"
        case .invalidInput(let msg):           return "Invalid input: \(msg)"
        case .toolExecutionFailed(let name, let e): return "Tool '\(name)' failed: \(e.localizedDescription)"
        case .maxIterationsExceeded(let n):    return "Exceeded maximum tool iterations (\(n))."
        case .pollTimeout(let id):             return "Poll timed out for interaction '\(id)'."
        case .interactionFailed(let id, let status): return "Interaction '\(id)' ended with status: \(status.rawValue)"
        }
    }
}

/// The lifecycle status of an interaction.
public enum InteractionStatus: String, Codable, Sendable {
    /// The interaction is currently processing.
    case inProgress     = "in_progress"
    /// The model is waiting for tool results or user input.
    case requiresAction = "requires_action"
    /// The interaction finished successfully.
    case completed      = "completed"
    /// The interaction failed with an error.
    case failed         = "failed"
    /// The interaction was explicitly cancelled.
    case cancelled      = "cancelled"
    /// The interaction ended without completing.
    case incomplete     = "incomplete"
    /// Token or request budget was exceeded.
    case budgetExceeded = "budget_exceeded"
}

/// Service tier for request prioritization and rate limits.
public enum ServiceTier: String, Codable, Sendable {
    /// Flexible service tier with elastic capacity.
    case flex
    /// Standard service tier.
    case standard
    /// Priority service tier with higher rate limits.
    case priority
}

/// Output modality returned by the model.
public enum ResponseModality: String, Codable, Sendable {
    case text, image, audio, video, document
}

/// Extended thinking depth level.
public enum ThinkingLevel: String, Codable, Sendable {
    case none, low, medium, high
}

/// Whether to include summaries of extended thinking steps.
public enum ThinkingSummaries: String, Codable, Sendable {
    case enabled, disabled
}

/// Controls how the model selects tools to call.
public enum ToolChoiceMode: String, Codable, Sendable {
    /// Let the model decide whether to call tools.
    case auto
    /// Prevent the model from calling tools.
    case none
    /// Require the model to call at least one tool.
    case required
}

/// Configuration for tool selection behavior.
public struct ToolChoiceConfig: Codable, Sendable {
    /// The tool selection mode.
    public let mode: ToolChoiceMode
    /// Optional list of tool names the model may call. Restricts `.auto` or `.required` modes.
    public let allowedTools: [String]?

    /// Creates a tool choice configuration.
    /// - Parameter mode: The tool selection mode.
    /// - Parameter allowedTools: Optional list of permitted tool names.
    public init(mode: ToolChoiceMode, allowedTools: [String]? = nil) {
        self.mode = mode
        self.allowedTools = allowedTools
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case allowedTools = "allowed_tools"
    }
}

/// Token usage by modality (text, image, audio, etc.).
public struct ModalityTokens: Codable, Sendable {
    /// The modality name.
    public let modality: String
    /// Token count for this modality.
    public let tokens: Int

    public init(modality: String, tokens: Int) {
        self.modality = modality
        self.tokens = tokens
    }
}

/// Count of grounding tool invocations by type.
public struct GroundingToolCount: Codable, Sendable {
    /// The grounding tool type.
    public let type: String
    /// Number of invocations.
    public let count: Int

    public init(type: String, count: Int) {
        self.type = type
        self.count = count
    }
}

/// Inline citation annotations in model text output.
public enum Annotation: Codable, Sendable {
    /// Citation to a web URL.
    case urlCitation(url: String, title: String?, startIndex: Int, endIndex: Int)
    /// Citation to a document file.
    case fileCitation(documentUri: String, fileName: String, source: String, pageNumber: Int?, startIndex: Int, endIndex: Int)
    /// Citation to a place or location.
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

/// A content item in a conversation step (text, image, document, or video).
public enum Content: Codable, Sendable {
    /// Text content with optional inline citations.
    case text(String, annotations: [Annotation]?)
    /// Image content provided inline or by URI.
    case image(data: Data?, mimeType: String?, uri: String?)
    /// Document content provided inline or by URI.
    case document(data: Data?, mimeType: String?, uri: String?)
    /// Video content provided inline or by URI.
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

/// A single result from a Google Search tool call.
public struct GoogleSearchResult: Codable, Sendable {
    /// Search result title.
    public let title: String?
    /// Search result URL.
    public let url: String?
    /// Search result snippet or description.
    public let snippet: String?

    public init(title: String? = nil, url: String? = nil, snippet: String? = nil) {
        self.title = title; self.url = url; self.snippet = snippet
    }

    private enum CodingKeys: String, CodingKey {
        case title, url, snippet
    }
}

/// A single result from a file search tool call.
public struct FileSearchResult: Codable, Sendable {
    /// File identifier in the file search store.
    public let fileId: String?
    /// File name.
    public let fileName: String?
    /// Relevant text snippet from the file.
    public let snippet: String?
    /// Relevance score.
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

/// A single step in an interaction's conversation history.
///
/// The API uses a unified steps array for both sent and received content.
public enum Step: Codable, Sendable {
    /// User-provided input with text, images, documents, or video.
    case userInput(content: [Content])
    /// Model-generated text or multimodal output.
    case modelOutput(content: [Content])
    /// Extended thinking step with optional summary.
    case thought(content: [Content], summary: String?)
    /// Function tool call initiated by the model.
    case functionCall(id: String, name: String, arguments: String)
    /// Result of a function tool execution.
    case functionResult(callId: String, result: String, name: String?, isError: Bool?)
    /// Code execution tool call.
    case codeExecutionCall(id: String, code: String)
    /// Result of code execution.
    case codeExecutionResult(callId: String, output: String, isError: Bool?)
    /// Google Search tool call.
    case googleSearchCall(id: String)
    /// Google Search tool results.
    case googleSearchResult(callId: String, results: [GoogleSearchResult])
    /// URL context tool call.
    case urlContextCall(id: String, urls: [String])
    /// URL context tool result.
    case urlContextResult(callId: String, content: String)
    /// MCP server tool call.
    case mcpToolCall(id: String, name: String, arguments: String)
    /// MCP server tool result.
    case mcpToolResult(callId: String, result: String)
    /// File search tool call.
    case fileSearchCall(id: String)
    /// File search tool results.
    case fileSearchResult(callId: String, results: [FileSearchResult])
    /// Google Maps tool call.
    case googleMapsCall(id: String)
    /// Google Maps tool result.
    case googleMapsResult(callId: String, result: String)
    /// Unknown step type, ignored for forward compatibility.
    case unknown

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
            self = .userInput(content: try container.decodeIfPresent([Content].self, forKey: .content) ?? [])
        case "model_output":
            self = .modelOutput(content: try container.decodeIfPresent([Content].self, forKey: .content) ?? [])
        case "thought":
            self = .thought(
                content: try container.decodeIfPresent([Content].self, forKey: .content) ?? [],
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        case "function_call":
            let fcArgs: String
            if let s = try? container.decode(String.self, forKey: .arguments) {
                fcArgs = s
            } else {
                let raw = try container.decode(RawJSON.self, forKey: .arguments)
                fcArgs = String(data: try JSONSerialization.data(withJSONObject: raw.any), encoding: .utf8) ?? "{}"
            }
            self = .functionCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: fcArgs
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
            let mcpArgs: String
            if let s = try? container.decode(String.self, forKey: .arguments) {
                mcpArgs = s
            } else {
                let raw = try container.decode(RawJSON.self, forKey: .arguments)
                mcpArgs = String(data: try JSONSerialization.data(withJSONObject: raw.any), encoding: .utf8) ?? "{}"
            }
            self = .mcpToolCall(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                arguments: mcpArgs
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
            self = .unknown
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
        case .unknown:
            break
        }
    }
}

// MARK: - JSONSchemaValue decoding support (local, encoding-only upstream type)

private func jsonSchemaValueFromAny(_ any: Any) throws -> JSONSchemaValue {
    guard let dict = any as? [String: Any],
          let typeStr = dict["type"] as? String else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "JSONSchemaValue must be a JSON object with a 'type' key")
        )
    }
    switch typeStr {
    case "object":
        let propsDict = dict["properties"] as? [String: Any] ?? [:]
        let required = dict["required"] as? [String] ?? []
        let properties: [(String, JSONSchemaValue)] = try propsDict.sorted { $0.key < $1.key }.map { key, value in
            (key, try jsonSchemaValueFromAny(value))
        }
        return .object(properties: properties, required: required)
    case "array":
        guard let items = dict["items"] else {
            return .array(items: .null)
        }
        return .array(items: try jsonSchemaValueFromAny(items))
    case "string":
        let description = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]
        return .string(description: description, enumValues: enumValues)
    case "integer":
        let description = dict["description"] as? String
        let minimum = (dict["minimum"] as? Int) ?? (dict["minimum"] as? Double).map(Int.init)
        let maximum = (dict["maximum"] as? Int) ?? (dict["maximum"] as? Double).map(Int.init)
        return .integer(description: description, minimum: minimum, maximum: maximum)
    case "number":
        let description = dict["description"] as? String
        let minimum = (dict["minimum"] as? Double) ?? (dict["minimum"] as? Int).map(Double.init)
        let maximum = (dict["maximum"] as? Double) ?? (dict["maximum"] as? Int).map(Double.init)
        return .number(description: description, minimum: minimum, maximum: maximum)
    case "boolean":
        return .boolean(description: dict["description"] as? String)
    case "null":
        return .null
    default:
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Unknown JSONSchemaValue type: \(typeStr)")
        )
    }
}

private struct JSONSchemaValueWrapper: Decodable {
    let value: JSONSchemaValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as raw JSON via a Dictionary<String, AnyCodingValue>
        let raw = try container.decode(RawJSON.self)
        self.value = try jsonSchemaValueFromAny(raw.any)
    }
}

private struct RawJSON: Decodable {
    let any: Any

    init(from decoder: any Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var result: [Any] = []
            while !container.isAtEnd {
                let element = try container.decode(RawJSON.self)
                result.append(element.any)
            }
            self.any = result
        } else if let container = try? decoder.container(keyedBy: RawJSONKey.self) {
            var result: [String: Any] = [:]
            for key in container.allKeys {
                let value = try container.decode(RawJSON.self, forKey: key)
                result[key.stringValue] = value.any
            }
            self.any = result
        } else {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) {
                self.any = bool
            } else if let int = try? container.decode(Int.self) {
                self.any = int
            } else if let double = try? container.decode(Double.self) {
                self.any = double
            } else if let string = try? container.decode(String.self) {
                self.any = string
            } else if container.decodeNil() {
                self.any = NSNull()
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot decode RawJSON value")
                )
            }
        }
    }
}

private struct RawJSONKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - InteractionTool

/// A tool the model can use during an interaction.
public enum InteractionTool: Codable, Sendable {
    /// Custom function tool executed locally via `ToolSession` or `Agent`.
    case function(name: String, description: String, parameters: JSONSchemaValue)
    /// Server-side Python code execution.
    case codeExecution
    /// Server-side Google Search.
    case googleSearch
    /// Server-side URL fetching and parsing.
    case urlContext
    /// Server-side file search across document stores.
    case fileSearch(storeNames: [String], topK: Int?, metadataFilter: String?)
    /// Server-side Google Maps integration.
    case googleMaps(latitude: Double, longitude: Double, enableWidget: Bool?)
    /// Server-side MCP tool invocation.
    case mcpServer

    private enum CodingKeys: String, CodingKey {
        case type, name, description, parameters
        case storeNames     = "file_search_store_names"
        case topK           = "top_k"
        case metadataFilter = "metadata_filter"
        case latitude, longitude
        case enableWidget   = "enable_widget"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "function":
            let wrapper = try container.decode(JSONSchemaValueWrapper.self, forKey: .parameters)
            self = .function(
                name: try container.decode(String.self, forKey: .name),
                description: try container.decode(String.self, forKey: .description),
                parameters: wrapper.value
            )
        case "code_execution": self = .codeExecution
        case "google_search":  self = .googleSearch
        case "url_context":    self = .urlContext
        case "mcp_server":     self = .mcpServer
        case "file_search":
            self = .fileSearch(
                storeNames: try container.decode([String].self, forKey: .storeNames),
                topK: try container.decodeIfPresent(Int.self, forKey: .topK),
                metadataFilter: try container.decodeIfPresent(String.self, forKey: .metadataFilter)
            )
        case "google_maps":
            self = .googleMaps(
                latitude: try container.decode(Double.self, forKey: .latitude),
                longitude: try container.decode(Double.self, forKey: .longitude),
                enableWidget: try container.decodeIfPresent(Bool.self, forKey: .enableWidget)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown tool type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .function(let name, let description, let parameters):
            try container.encode("function", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
            try container.encode(parameters, forKey: .parameters)
        case .codeExecution: try container.encode("code_execution", forKey: .type)
        case .googleSearch:  try container.encode("google_search", forKey: .type)
        case .urlContext:    try container.encode("url_context", forKey: .type)
        case .mcpServer:     try container.encode("mcp_server", forKey: .type)
        case .fileSearch(let storeNames, let topK, let metadataFilter):
            try container.encode("file_search", forKey: .type)
            try container.encode(storeNames, forKey: .storeNames)
            try container.encodeIfPresent(topK, forKey: .topK)
            try container.encodeIfPresent(metadataFilter, forKey: .metadataFilter)
        case .googleMaps(let lat, let lon, let widget):
            try container.encode("google_maps", forKey: .type)
            try container.encode(lat, forKey: .latitude)
            try container.encode(lon, forKey: .longitude)
            try container.encodeIfPresent(widget, forKey: .enableWidget)
        }
    }
}

public extension InteractionTool {
    /// Creates a `.function` tool from a `ToolDefinition` produced by the `@LLMTool` macro.
    /// - Parameter definition: Tool definition from `@LLMTool`.
    init(_ definition: ToolDefinition) {
        self = .function(
            name: definition.name,
            description: definition.description,
            parameters: definition.parameters
        )
    }
}

// MARK: - InteractionInput

/// Input to an interaction, either a simple text prompt or a full steps array.
public enum InteractionInput: Codable, Sendable {
    /// Simple text prompt.
    case text(String)
    /// Full conversation history as steps array.
    case steps([Step])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .steps(try container.decode([Step].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let t):   try container.encode(t)
        case .steps(let s):  try container.encode(s)
        }
    }
}

// MARK: - GenerationConfig

/// Model generation parameters (sampling, output length, thinking, tool choice).
public struct GenerationConfig: Codable, Sendable {
    /// Sampling temperature (0.0–2.0).
    public var temperature: Double?
    /// Nucleus sampling probability (0.0–1.0).
    public var topP: Double?
    /// Maximum output tokens.
    public var maxOutputTokens: Int?
    /// Random seed for deterministic sampling.
    public var seed: Int?
    /// Stop sequences that halt generation.
    public var stopSequences: [String]?
    /// Extended thinking depth level.
    public var thinkingLevel: ThinkingLevel?
    /// Whether to include thinking summaries.
    public var thinkingSummaries: ThinkingSummaries?
    /// Tool selection behavior.
    public var toolChoice: ToolChoiceConfig?

    public init(
        temperature: Double? = nil, topP: Double? = nil, maxOutputTokens: Int? = nil,
        seed: Int? = nil, stopSequences: [String]? = nil, thinkingLevel: ThinkingLevel? = nil,
        thinkingSummaries: ThinkingSummaries? = nil, toolChoice: ToolChoiceConfig? = nil
    ) {
        self.temperature = temperature; self.topP = topP; self.maxOutputTokens = maxOutputTokens
        self.seed = seed; self.stopSequences = stopSequences; self.thinkingLevel = thinkingLevel
        self.thinkingSummaries = thinkingSummaries; self.toolChoice = toolChoice
    }

    private enum CodingKeys: String, CodingKey {
        case temperature, seed
        case topP              = "top_p"
        case maxOutputTokens   = "max_output_tokens"
        case stopSequences     = "stop_sequences"
        case thinkingLevel     = "thinking_level"
        case thinkingSummaries = "thinking_summaries"
        case toolChoice        = "tool_choice"
    }
}

// MARK: - ResponseFormat, ResponseDelivery, and AudioOutputMimeType

/// How the model delivers response content (inline data or URI reference).
public enum ResponseDelivery: String, Codable, Sendable {
    case inline, uri
}

/// Audio output MIME type for audio response format.
public enum AudioOutputMimeType: String, Codable, Sendable {
    case mp3     = "audio/mp3"
    case oggOpus = "audio/ogg_opus"
    case l16     = "audio/l16"
    case wav     = "audio/wav"
    case alaw    = "audio/alaw"
    case mulaw   = "audio/mulaw"
}

/// Desired response format (text, image, or audio) with format-specific parameters.
public enum ResponseFormat: Codable, Sendable {
    /// Text output with optional MIME type and JSON schema constraint.
    case text(mimeType: String? = nil, schema: JSONSchemaValue? = nil)
    /// Image output with MIME type, aspect ratio, size, and delivery mode.
    case image(mimeType: String, aspectRatio: String? = nil, imageSize: String? = nil, delivery: ResponseDelivery? = nil)
    /// Audio output with MIME type, sample rate, bit rate, and delivery mode.
    case audio(mimeType: AudioOutputMimeType, sampleRate: Int? = nil, bitRate: Int? = nil, delivery: ResponseDelivery? = nil)

    private enum CodingKeys: String, CodingKey {
        case type, schema, delivery
        case mimeType    = "mime_type"
        case aspectRatio = "aspect_ratio"
        case imageSize   = "image_size"
        case sampleRate  = "sample_rate"
        case bitRate     = "bit_rate"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType),
                schema: nil  // JSONSchemaValue is Encodable-only; schema cannot be decoded
            )
        case "image":
            self = .image(
                mimeType: try container.decode(String.self, forKey: .mimeType),
                aspectRatio: try container.decodeIfPresent(String.self, forKey: .aspectRatio),
                imageSize: try container.decodeIfPresent(String.self, forKey: .imageSize),
                delivery: try container.decodeIfPresent(ResponseDelivery.self, forKey: .delivery)
            )
        case "audio":
            self = .audio(
                mimeType: try container.decode(AudioOutputMimeType.self, forKey: .mimeType),
                sampleRate: try container.decodeIfPresent(Int.self, forKey: .sampleRate),
                bitRate: try container.decodeIfPresent(Int.self, forKey: .bitRate),
                delivery: try container.decodeIfPresent(ResponseDelivery.self, forKey: .delivery)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown response format type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let mimeType, let schema):
            try container.encode("text", forKey: .type)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(schema, forKey: .schema)
        case .image(let mimeType, let aspectRatio, let imageSize, let delivery):
            try container.encode("image", forKey: .type)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
            try container.encodeIfPresent(imageSize, forKey: .imageSize)
            try container.encodeIfPresent(delivery, forKey: .delivery)
        case .audio(let mimeType, let sampleRate, let bitRate, let delivery):
            try container.encode("audio", forKey: .type)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
            try container.encodeIfPresent(bitRate, forKey: .bitRate)
            try container.encodeIfPresent(delivery, forKey: .delivery)
        }
    }
}

// MARK: - Network and Environment Configuration

/// A network allowlist entry for remote environment configuration.
public struct NetworkAllowlistEntry: Codable, Sendable {
    /// Permitted domain.
    public let domain: String
    /// Optional URL transformation rules.
    public let transform: [String: String]?

    public init(domain: String, transform: [String: String]? = nil) {
        self.domain = domain; self.transform = transform
    }
}

/// Network access policy for remote code execution environments.
public enum EnvironmentNetwork: Codable, Sendable {
    /// Allow access only to specified domains.
    case allowlist([NetworkAllowlistEntry])
    /// Disable all network access.
    case disabled

    private struct AllowlistWrapper: Codable {
        let allowlist: [NetworkAllowlistEntry]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self), str == "disabled" {
            self = .disabled
        } else {
            let wrapper = try container.decode(AllowlistWrapper.self)
            self = .allowlist(wrapper.allowlist)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .disabled:
            try container.encode("disabled")
        case .allowlist(let entries):
            try container.encode(AllowlistWrapper(allowlist: entries))
        }
    }
}

/// A file source for populating a remote code execution environment.
public enum EnvironmentSource: Codable, Sendable {
    /// Inline file content.
    case inline(target: String, content: String)
    /// File from a repository.
    case repository(source: String, target: String)
    /// File from Google Cloud Storage.
    case gcs(source: String, target: String)

    private enum CodingKeys: String, CodingKey {
        case type, target, content, source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "inline":
            self = .inline(
                target: try container.decode(String.self, forKey: .target),
                content: try container.decode(String.self, forKey: .content)
            )
        case "repository":
            self = .repository(
                source: try container.decode(String.self, forKey: .source),
                target: try container.decode(String.self, forKey: .target)
            )
        case "gcs":
            self = .gcs(
                source: try container.decode(String.self, forKey: .source),
                target: try container.decode(String.self, forKey: .target)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown source type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inline(let target, let content):
            try container.encode("inline", forKey: .type)
            try container.encode(target, forKey: .target)
            try container.encode(content, forKey: .content)
        case .repository(let source, let target):
            try container.encode("repository", forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        case .gcs(let source, let target):
            try container.encode("gcs", forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        }
    }
}

/// Configuration for remote code execution environment (files and network access).
public struct EnvironmentConfig: Codable, Sendable {
    /// File sources to populate the environment.
    public let sources: [EnvironmentSource]?
    /// Network access policy.
    public let network: EnvironmentNetwork?

    public init(sources: [EnvironmentSource]? = nil, network: EnvironmentNetwork? = nil) {
        self.sources = sources; self.network = network
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sources = try container.decodeIfPresent([EnvironmentSource].self, forKey: .sources)
        self.network = try container.decodeIfPresent(EnvironmentNetwork.self, forKey: .network)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("remote", forKey: .type)
        try container.encodeIfPresent(sources, forKey: .sources)
        try container.encodeIfPresent(network, forKey: .network)
    }

    private enum CodingKeys: String, CodingKey {
        case type, sources, network
    }
}

/// Webhook configuration for background interaction notifications.
public struct WebhookConfig: Codable, Sendable {
    /// Notification endpoint URLs.
    public let notificationEndpoints: [String]
    /// Optional metadata included in webhook payloads.
    public let userMetadata: [String: String]?

    public init(notificationEndpoints: [String], userMetadata: [String: String]? = nil) {
        self.notificationEndpoints = notificationEndpoints; self.userMetadata = userMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case notificationEndpoints = "notification_endpoints"
        case userMetadata          = "user_metadata"
    }
}

// MARK: - InteractionRequest

/// A request to the Interactions API.
public struct InteractionRequest: Codable, Sendable {
    /// Model identifier (e.g., "gemini-2.5-flash").
    public var model: String?
    /// Named agent identifier (mutually exclusive with `model`).
    public var agent: String?
    /// Input prompt or steps array.
    public var input: InteractionInput
    /// System instruction for the model.
    public var systemInstruction: String?
    /// Tools available to the model.
    public var tools: [InteractionTool]?
    /// Whether to stream the response.
    public var stream: Bool?
    /// Whether to store the interaction for resumption via `previousInteractionId`.
    public var store: Bool?
    /// Whether to run the interaction in the background.
    public var background: Bool?
    /// Generation parameters (temperature, topP, maxOutputTokens, etc.).
    public var generationConfig: GenerationConfig?
    /// Desired response format (text, image, audio).
    public var responseFormat: ResponseFormat?
    /// Allowed response modalities.
    public var responseModalities: [ResponseModality]?
    /// Previous interaction ID for conversation chaining.
    public var previousInteractionId: String?
    /// Environment configuration for code execution tools.
    public var environment: EnvironmentConfig?
    /// Webhook configuration for background interactions.
    public var webhookConfig: WebhookConfig?
    /// Service tier for prioritization and rate limiting.
    public var serviceTier: ServiceTier?

    /// Creates a new interaction request.
    /// - Parameter input: The input prompt or steps array.
    public init(input: InteractionInput) {
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case model, agent, input, tools, stream, store, background
        case systemInstruction   = "system_instruction"
        case generationConfig    = "generation_config"
        case responseFormat      = "response_format"
        case responseModalities  = "response_modalities"
        case previousInteractionId = "previous_interaction_id"
        case environment
        case webhookConfig       = "webhook_config"
        case serviceTier         = "service_tier"
    }
}

// MARK: - Usage

/// Token usage statistics for an interaction.
public struct Usage: Codable, Sendable {
    /// Total input tokens.
    public let totalInputTokens: Int
    /// Total output tokens.
    public let totalOutputTokens: Int
    /// Total extended thinking tokens.
    public let totalThoughtTokens: Int
    /// Total cached tokens.
    public let totalCachedTokens: Int
    /// Total tool use tokens.
    public let totalToolUseTokens: Int
    /// Total of all token types.
    public let totalTokens: Int
    /// Input token counts by modality.
    public let inputTokensByModality: [ModalityTokens]
    /// Output token counts by modality.
    public let outputTokensByModality: [ModalityTokens]
    /// Cached token counts by modality.
    public let cachedTokensByModality: [ModalityTokens]
    /// Tool use token counts by modality.
    public let toolUseTokensByModality: [ModalityTokens]
    /// Grounding tool invocation counts.
    public let groundingToolCount: [GroundingToolCount]

    public init(
        totalInputTokens: Int, totalOutputTokens: Int, totalThoughtTokens: Int,
        totalCachedTokens: Int, totalToolUseTokens: Int, totalTokens: Int,
        inputTokensByModality: [ModalityTokens] = [],
        outputTokensByModality: [ModalityTokens] = [],
        cachedTokensByModality: [ModalityTokens] = [],
        toolUseTokensByModality: [ModalityTokens] = [],
        groundingToolCount: [GroundingToolCount] = []
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalThoughtTokens = totalThoughtTokens
        self.totalCachedTokens = totalCachedTokens
        self.totalToolUseTokens = totalToolUseTokens
        self.totalTokens = totalTokens
        self.inputTokensByModality = inputTokensByModality
        self.outputTokensByModality = outputTokensByModality
        self.cachedTokensByModality = cachedTokensByModality
        self.toolUseTokensByModality = toolUseTokensByModality
        self.groundingToolCount = groundingToolCount
    }

    private enum CodingKeys: String, CodingKey {
        case totalInputTokens         = "total_input_tokens"
        case totalOutputTokens        = "total_output_tokens"
        case totalThoughtTokens       = "total_thought_tokens"
        case totalCachedTokens        = "total_cached_tokens"
        case totalToolUseTokens       = "total_tool_use_tokens"
        case totalTokens              = "total_tokens"
        case inputTokensByModality    = "input_tokens_by_modality"
        case outputTokensByModality   = "output_tokens_by_modality"
        case cachedTokensByModality   = "cached_tokens_by_modality"
        case toolUseTokensByModality  = "tool_use_tokens_by_modality"
        case groundingToolCount       = "grounding_tool_count"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalInputTokens        = try c.decodeIfPresent(Int.self, forKey: .totalInputTokens) ?? 0
        totalOutputTokens       = try c.decodeIfPresent(Int.self, forKey: .totalOutputTokens) ?? 0
        totalThoughtTokens      = try c.decodeIfPresent(Int.self, forKey: .totalThoughtTokens) ?? 0
        totalCachedTokens       = try c.decodeIfPresent(Int.self, forKey: .totalCachedTokens) ?? 0
        totalToolUseTokens      = try c.decodeIfPresent(Int.self, forKey: .totalToolUseTokens) ?? 0
        totalTokens             = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        inputTokensByModality   = try c.decodeIfPresent([ModalityTokens].self, forKey: .inputTokensByModality) ?? []
        outputTokensByModality  = try c.decodeIfPresent([ModalityTokens].self, forKey: .outputTokensByModality) ?? []
        cachedTokensByModality  = try c.decodeIfPresent([ModalityTokens].self, forKey: .cachedTokensByModality) ?? []
        toolUseTokensByModality = try c.decodeIfPresent([ModalityTokens].self, forKey: .toolUseTokensByModality) ?? []
        groundingToolCount      = try c.decodeIfPresent([GroundingToolCount].self, forKey: .groundingToolCount) ?? []
    }
}

// MARK: - Interaction

/// A completed or in-progress interaction with the Gemini API.
public struct Interaction: Codable, Sendable {
    /// Unique interaction identifier.
    public let id: String
    /// Object type, always `"interaction"`.
    public let object: String
    /// Model identifier (e.g., "gemini-2.5-flash").
    public let model: String?
    /// Named agent identifier.
    public let agent: String?
    /// Lifecycle status.
    public let status: InteractionStatus
    /// Creation timestamp (ISO 8601).
    public let created: String?
    /// Last update timestamp (ISO 8601).
    public let updated: String?
    /// Conversation steps array.
    public let steps: [Step]
    /// Token usage statistics.
    public let usage: Usage?
    /// Service tier used for this interaction.
    public let serviceTier: ServiceTier?

    public init(id: String, object: String = "interaction", model: String? = nil,
                agent: String? = nil, status: InteractionStatus, created: String? = nil,
                updated: String? = nil, steps: [Step] = [], usage: Usage? = nil,
                serviceTier: ServiceTier? = nil) {
        self.id = id
        self.object = object
        self.model = model
        self.agent = agent
        self.status = status
        self.created = created
        self.updated = updated
        self.steps = steps
        self.usage = usage
        self.serviceTier = serviceTier
    }

    /// The last text output from the model, or `nil` if no text was produced.
    public var outputText: String? {
        for step in steps.reversed() {
            if case .modelOutput(let content) = step {
                for item in content {
                    if case .text(let text, _) = item { return text }
                }
            }
        }
        return nil
    }

    /// Whether the interaction requires action (tool results or user input).
    public var requiresAction: Bool { status == .requiresAction }

    /// All function call steps in the interaction.
    public var functionCalls: [Step] {
        steps.filter { step in
            if case .functionCall = step { return true }
            return false
        }
    }

    /// Whether the interaction has reached a terminal status.
    public var isComplete: Bool {
        switch status {
        case .completed, .failed, .cancelled, .incomplete, .budgetExceeded: return true
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, object, model, agent, status, created, updated, steps, usage
        case serviceTier = "service_tier"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object) ?? "interaction"
        model = try container.decodeIfPresent(String.self, forKey: .model)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        status = try container.decode(InteractionStatus.self, forKey: .status)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        steps = try container.decodeIfPresent([Step].self, forKey: .steps) ?? []
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        serviceTier = try container.decodeIfPresent(ServiceTier.self, forKey: .serviceTier)
    }
}

// MARK: - Convenience Constructors

/// Creates a `.userInput` step with a single text content item.
/// - Parameter text: The user's text input.
/// - Returns: A `.userInput` step.
public func User(_ text: String) -> Step {
    .userInput(content: [.text(text, annotations: nil)])
}

/// Creates a `.userInput` step with the given content array.
/// - Parameter content: Array of content items (text, images, documents, video).
/// - Returns: A `.userInput` step.
public func User(_ content: [Content]) -> Step {
    .userInput(content: content)
}

/// Creates a `.functionResult` step.
/// - Parameter callId: The function call ID this result corresponds to.
/// - Parameter result: The function execution result (JSON string or plain text).
/// - Parameter isError: Whether the function execution failed.
/// - Returns: A `.functionResult` step.
public func FunctionOutput(callId: String, result: String, isError: Bool = false) -> Step {
    .functionResult(callId: callId, result: result, name: nil, isError: isError)
}

// MARK: - InteractionConfigParameter

/// A parameter that modifies an `InteractionRequest`.
///
/// Implemented by all parameter structs (`Temperature`, `TopP`, `SystemInstruction`, etc.).
public protocol InteractionConfigParameter: Sendable {
    /// Applies this parameter to a mutable interaction request.
    /// - Parameter request: The request to modify.
    func apply(to request: inout InteractionRequest)
}

private extension InteractionRequest {
    mutating func ensureGenerationConfig() {
        if generationConfig == nil { generationConfig = GenerationConfig() }
    }
}

/// Sampling temperature. Values outside 0.0–2.0 are silently ignored.
public struct Temperature: InteractionConfigParameter {
    private let value: Double
    public init(_ value: Double) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value >= 0.0, value <= 2.0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.temperature = value
    }
}

/// Nucleus sampling probability. Values outside 0.0–1.0 are silently ignored.
public struct TopP: InteractionConfigParameter {
    private let value: Double
    public init(_ value: Double) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value >= 0.0, value <= 1.0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.topP = value
    }
}

/// Maximum output tokens. Values ≤ 0 are silently ignored.
public struct MaxOutputTokens: InteractionConfigParameter {
    private let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value > 0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.maxOutputTokens = value
    }
}

/// Random seed for deterministic sampling.
public struct Seed: InteractionConfigParameter {
    private let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.seed = value
    }
}

/// System instruction for the model. Empty strings are silently ignored.
public struct SystemInstruction: InteractionConfigParameter {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.systemInstruction = value
    }
}

/// Previous interaction ID for conversation chaining. Empty strings are silently ignored.
///
/// Do NOT set this manually when using `ToolSession` or `Agent` — both manage chaining automatically.
public struct PreviousInteractionId: InteractionConfigParameter {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.previousInteractionId = value
    }
}

/// Whether to store the interaction for resumption via `previousInteractionId`.
public struct Store: InteractionConfigParameter {
    private let value: Bool
    public init(_ value: Bool) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.store = value }
}

/// Whether to run the interaction in the background.
public struct Background: InteractionConfigParameter {
    private let value: Bool
    public init(_ value: Bool) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.background = value }
}

/// Service tier for prioritization and rate limiting.
public struct ServiceTierParam: InteractionConfigParameter {
    private let value: ServiceTier
    public init(_ value: ServiceTier) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.serviceTier = value }
}

/// Extended thinking depth level.
public struct ThinkingLevelParam: InteractionConfigParameter {
    private let value: ThinkingLevel
    public init(_ value: ThinkingLevel) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.thinkingLevel = value
    }
}

/// Whether to include summaries of extended thinking steps.
public struct ThinkingSummariesParam: InteractionConfigParameter {
    private let value: ThinkingSummaries
    public init(_ value: ThinkingSummaries) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.thinkingSummaries = value
    }
}

/// Desired response format (text, image, or audio).
public struct ResponseFormatParam: InteractionConfigParameter {
    private let value: ResponseFormat
    public init(_ value: ResponseFormat) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.responseFormat = value }
}

/// Allowed response modalities. Empty arrays are silently ignored.
public struct ResponseModalitiesParam: InteractionConfigParameter {
    private let value: [ResponseModality]
    public init(_ value: [ResponseModality]) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.responseModalities = value
    }
}

/// Maximum tool loop iterations. Consumed by `ToolSession`, not sent to the API.
public struct MaxToolCalls: InteractionConfigParameter {
    /// The maximum iteration count.
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by ToolSession */ }
}

/// Environment configuration for remote code execution.
public struct EnvironmentParam: InteractionConfigParameter {
    private let value: EnvironmentConfig
    public init(_ value: EnvironmentConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.environment = value }
}

/// Webhook configuration for background interaction notifications.
public struct WebhookConfigParam: InteractionConfigParameter {
    private let value: WebhookConfig
    public init(_ value: WebhookConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.webhookConfig = value }
}

// MARK: - Result Builders

/// Result builder for `InteractionConfigParameter` arrays.
///
/// Used by `ToolSession` and `Agent` to accept config DSL.
@resultBuilder
public struct InteractionConfigBuilder {
    public static func buildBlock(_ components: [any InteractionConfigParameter]...) -> [any InteractionConfigParameter] {
        components.flatMap { $0 }
    }
    public static func buildOptional(_ component: [any InteractionConfigParameter]?) -> [any InteractionConfigParameter] {
        component ?? []
    }
    public static func buildEither(first component: [any InteractionConfigParameter]) -> [any InteractionConfigParameter] {
        component
    }
    public static func buildEither(second component: [any InteractionConfigParameter]) -> [any InteractionConfigParameter] {
        component
    }
    public static func buildArray(_ components: [[any InteractionConfigParameter]]) -> [any InteractionConfigParameter] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: any InteractionConfigParameter) -> [any InteractionConfigParameter] {
        [expression]
    }
}

/// Result builder for `Step` arrays.
///
/// Used to construct conversation steps with a declarative DSL.
@resultBuilder
public struct StepsBuilder {
    public static func buildBlock(_ components: [Step]...) -> [Step] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [Step]?) -> [Step] { component ?? [] }
    public static func buildEither(first component: [Step]) -> [Step] { component }
    public static func buildEither(second component: [Step]) -> [Step] { component }
    public static func buildArray(_ components: [[Step]]) -> [Step] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: Step) -> [Step] { [expression] }
}

/// Result builder for `InteractionTool` arrays.
///
/// Used by `ToolSession` and `Agent` to accept tools DSL.
@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ components: [InteractionTool]...) -> [InteractionTool] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [InteractionTool]?) -> [InteractionTool] { component ?? [] }
    public static func buildEither(first component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildEither(second component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildArray(_ components: [[InteractionTool]]) -> [InteractionTool] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: InteractionTool) -> [InteractionTool] { [expression] }
}

// MARK: - Retry

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let initialBackoff: Duration
    public let backoffMultiplier: Double
    public let initialTimeout: Duration
    public let timeoutMultiplier: Double
    public let maxTimeout: Duration
    public let retryableStatusCodes: Set<Int>
    public let onRetry: (@Sendable (RetryEvent) -> Void)?

    public init(
        maxAttempts: Int = 3,
        initialBackoff: Duration = .seconds(2),
        backoffMultiplier: Double = 2.0,
        initialTimeout: Duration = .seconds(120),
        timeoutMultiplier: Double = 1.5,
        maxTimeout: Duration = .seconds(300),
        retryableStatusCodes: Set<Int> = [429, 500, 503],
        onRetry: (@Sendable (RetryEvent) -> Void)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.backoffMultiplier = backoffMultiplier
        self.initialTimeout = initialTimeout
        self.timeoutMultiplier = timeoutMultiplier
        self.maxTimeout = maxTimeout
        self.retryableStatusCodes = retryableStatusCodes
        self.onRetry = onRetry
    }
}

public struct RetryEvent: Sendable {
    public let attempt: Int
    public let maxAttempts: Int
    public let error: GeminiInteractionsError
    public let backoffDuration: Duration
    public let nextTimeout: Duration

    public init(
        attempt: Int,
        maxAttempts: Int,
        error: GeminiInteractionsError,
        backoffDuration: Duration,
        nextTimeout: Duration
    ) {
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.error = error
        self.backoffDuration = backoffDuration
        self.nextTimeout = nextTimeout
    }
}

// MARK: - InteractionsClient

/// A client for the Gemini Interactions API.
///
/// Safe to share across tasks. Handles authentication, encoding, error wrapping, and HTTP transport.
public actor InteractionsClient {
    private let apiKey: String
    private let apiRevision: String
    private let retryPolicy: RetryPolicy?
    let session: URLSession
    let baseURL: URL

    /// Creates a new Interactions API client.
    /// - Parameter apiKey: Your Gemini API key.
    /// - Parameter apiRevision: API revision date (default: "2026-05-20").
    /// - Parameter retryPolicy: Optional retry policy (default: RetryPolicy()). Pass nil to disable retries.
    public init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy()) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.retryPolicy = retryPolicy
        self.session = URLSession.shared
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy(), session: URLSession) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.retryPolicy = retryPolicy
        self.session = session
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    func interactionsURL() -> URL {
        baseURL.appendingPathComponent("v1beta/interactions")
    }

    func interactionURL(id: String) -> URL {
        interactionsURL().appendingPathComponent(id)
    }

    func headers() -> [String: String] {
        [
            "x-goog-api-key": apiKey,
            "Api-Revision": apiRevision
        ]
    }

    func makeRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        for (key, value) in headers() {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    func execute(_ urlRequest: URLRequest) async throws -> Data {
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
            return data
        case 429:
            throw GeminiInteractionsError.rateLimitExceeded
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }

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

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let decodingError as DecodingError {
            throw GeminiInteractionsError.decodingError(decodingError)
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch let encodingError as EncodingError {
            throw GeminiInteractionsError.encodingError(encodingError)
        }
    }

    /// Sends an interaction request and returns the completed interaction.
    /// - Parameter request: The interaction request to send.
    /// - Returns: The decoded interaction response.
    public func send(_ request: InteractionRequest) async throws -> Interaction {
        let body = try encode(request)
        let urlRequest = makeRequest(url: interactionsURL(), method: "POST", body: body)
        let data = try await execute(urlRequest)
        return try decode(Interaction.self, from: data)
    }

    /// Retrieves an interaction by ID.
    /// - Parameter id: The interaction ID.
    /// - Returns: The decoded interaction.
    public func get(id: String) async throws -> Interaction {
        let urlRequest = makeRequest(url: interactionURL(id: id), method: "GET")
        let data = try await execute(urlRequest)
        return try decode(Interaction.self, from: data)
    }

    /// Deletes a stored interaction.
    /// - Parameter id: The interaction ID.
    public func delete(id: String) async throws {
        let urlRequest = makeRequest(url: interactionURL(id: id), method: "DELETE")
        _ = try await execute(urlRequest)
    }

    /// Cancels a running background interaction.
    /// - Parameter id: The interaction ID.
    public func cancel(id: String) async throws {
        let cancelURL = interactionURL(id: id).appendingPathComponent("cancel")
        let urlRequest = makeRequest(url: cancelURL, method: "POST")
        _ = try await execute(urlRequest)
    }
}

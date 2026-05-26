// Sources/SwiftGeminiInteractions/Core.swift
import Foundation
@_exported import SwiftLLMToolMacros

// MARK: - GeminiInteractionsError

public enum GeminiInteractionsError: Error, LocalizedError, @unchecked Sendable {
    case networkError(URLError)
    case httpError(statusCode: Int, body: String)
    case rateLimitExceeded
    case decodingError(DecodingError)
    case encodingError(EncodingError)
    case invalidInput(String)
    case toolExecutionFailed(name: String, error: any Error)
    case maxIterationsExceeded(Int)
    case pollTimeout(id: String)
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

public enum InteractionTool: Codable, Sendable {
    case function(name: String, description: String, parameters: JSONSchemaValue)
    case codeExecution
    case googleSearch
    case urlContext
    case fileSearch(storeNames: [String], topK: Int?, metadataFilter: String?)
    case googleMaps(latitude: Double, longitude: Double, enableWidget: Bool?)
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
    init(_ definition: ToolDefinition) {
        self = .function(
            name: definition.name,
            description: definition.description,
            parameters: definition.parameters
        )
    }
}

// MARK: - InteractionInput

public enum InteractionInput: Codable, Sendable {
    case text(String)
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

public struct GenerationConfig: Codable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var seed: Int?
    public var stopSequences: [String]?
    public var thinkingLevel: ThinkingLevel?
    public var thinkingSummaries: ThinkingSummaries?
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

public enum ResponseDelivery: String, Codable, Sendable {
    case inline, uri
}

public enum AudioOutputMimeType: String, Codable, Sendable {
    case mp3     = "audio/mp3"
    case oggOpus = "audio/ogg_opus"
    case l16     = "audio/l16"
    case wav     = "audio/wav"
    case alaw    = "audio/alaw"
    case mulaw   = "audio/mulaw"
}

public enum ResponseFormat: Codable, Sendable {
    case text(mimeType: String? = nil, schema: JSONSchemaValue? = nil)
    case image(mimeType: String, aspectRatio: String? = nil, imageSize: String? = nil, delivery: ResponseDelivery? = nil)
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

public struct NetworkAllowlistEntry: Codable, Sendable {
    public let domain: String
    public let transform: [String: String]?

    public init(domain: String, transform: [String: String]? = nil) {
        self.domain = domain; self.transform = transform
    }
}

public enum EnvironmentNetwork: Codable, Sendable {
    case allowlist([NetworkAllowlistEntry])
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

public enum EnvironmentSource: Codable, Sendable {
    case inline(target: String, content: String)
    case repository(source: String, target: String)
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

public struct EnvironmentConfig: Codable, Sendable {
    public let sources: [EnvironmentSource]?
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

public struct WebhookConfig: Codable, Sendable {
    public let notificationEndpoints: [String]
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

public struct InteractionRequest: Codable, Sendable {
    public var model: String?
    public var agent: String?
    public var input: InteractionInput
    public var systemInstruction: String?
    public var tools: [InteractionTool]?
    public var stream: Bool?
    public var store: Bool?
    public var background: Bool?
    public var generationConfig: GenerationConfig?
    public var responseFormat: ResponseFormat?
    public var responseModalities: [ResponseModality]?
    public var previousInteractionId: String?
    public var environment: EnvironmentConfig?
    public var webhookConfig: WebhookConfig?
    public var serviceTier: ServiceTier?

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

// MARK: - Interaction

public struct Interaction: Codable, Sendable {
    public let id: String
    public let object: String
    public let model: String?
    public let agent: String?
    public let status: InteractionStatus
    public let created: String?
    public let updated: String?
    public let steps: [Step]
    public let usage: Usage?
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

    public var requiresAction: Bool { status == .requiresAction }

    public var functionCalls: [Step] {
        steps.filter { step in
            if case .functionCall = step { return true }
            return false
        }
    }

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
public func User(_ text: String) -> Step {
    .userInput(content: [.text(text, annotations: nil)])
}

/// Creates a `.userInput` step with the given content array.
public func User(_ content: [Content]) -> Step {
    .userInput(content: content)
}

/// Creates a `.functionResult` step.
public func FunctionOutput(callId: String, result: String, isError: Bool = false) -> Step {
    .functionResult(callId: callId, result: result, name: nil, isError: isError)
}

// MARK: - InteractionConfigParameter

public protocol InteractionConfigParameter: Sendable {
    func apply(to request: inout InteractionRequest)
}

private extension InteractionRequest {
    mutating func ensureGenerationConfig() {
        if generationConfig == nil { generationConfig = GenerationConfig() }
    }
}

public struct Temperature: InteractionConfigParameter {
    private let value: Double
    public init(_ value: Double) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value >= 0.0, value <= 2.0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.temperature = value
    }
}

public struct TopP: InteractionConfigParameter {
    private let value: Double
    public init(_ value: Double) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value >= 0.0, value <= 1.0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.topP = value
    }
}

public struct MaxOutputTokens: InteractionConfigParameter {
    private let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard value > 0 else { return }
        request.ensureGenerationConfig()
        request.generationConfig!.maxOutputTokens = value
    }
}

public struct Seed: InteractionConfigParameter {
    private let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.seed = value
    }
}

public struct SystemInstruction: InteractionConfigParameter {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.systemInstruction = value
    }
}

public struct PreviousInteractionId: InteractionConfigParameter {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.previousInteractionId = value
    }
}

public struct Store: InteractionConfigParameter {
    private let value: Bool
    public init(_ value: Bool) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.store = value }
}

public struct Background: InteractionConfigParameter {
    private let value: Bool
    public init(_ value: Bool) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.background = value }
}

public struct ServiceTierParam: InteractionConfigParameter {
    private let value: ServiceTier
    public init(_ value: ServiceTier) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.serviceTier = value }
}

public struct ThinkingLevelParam: InteractionConfigParameter {
    private let value: ThinkingLevel
    public init(_ value: ThinkingLevel) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.thinkingLevel = value
    }
}

public struct ThinkingSummariesParam: InteractionConfigParameter {
    private let value: ThinkingSummaries
    public init(_ value: ThinkingSummaries) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        request.ensureGenerationConfig()
        request.generationConfig!.thinkingSummaries = value
    }
}

public struct ResponseFormatParam: InteractionConfigParameter {
    private let value: ResponseFormat
    public init(_ value: ResponseFormat) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.responseFormat = value }
}

public struct ResponseModalitiesParam: InteractionConfigParameter {
    private let value: [ResponseModality]
    public init(_ value: [ResponseModality]) { self.value = value }
    public func apply(to request: inout InteractionRequest) {
        guard !value.isEmpty else { return }
        request.responseModalities = value
    }
}

public struct MaxToolCalls: InteractionConfigParameter {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by ToolSession */ }
}

public struct EnvironmentParam: InteractionConfigParameter {
    private let value: EnvironmentConfig
    public init(_ value: EnvironmentConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.environment = value }
}

public struct RequestTimeout: InteractionConfigParameter {
    public let value: TimeInterval
    public init(_ value: TimeInterval) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by client */ }
}

public struct WebhookConfigParam: InteractionConfigParameter {
    private let value: WebhookConfig
    public init(_ value: WebhookConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.webhookConfig = value }
}

// MARK: - Result Builders

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

@resultBuilder
public struct StepsBuilder {
    public static func buildBlock(_ components: [Step]...) -> [Step] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [Step]?) -> [Step] { component ?? [] }
    public static func buildEither(first component: [Step]) -> [Step] { component }
    public static func buildEither(second component: [Step]) -> [Step] { component }
    public static func buildArray(_ components: [[Step]]) -> [Step] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: Step) -> [Step] { [expression] }
}

@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ components: [InteractionTool]...) -> [InteractionTool] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [InteractionTool]?) -> [InteractionTool] { component ?? [] }
    public static func buildEither(first component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildEither(second component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildArray(_ components: [[InteractionTool]]) -> [InteractionTool] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: InteractionTool) -> [InteractionTool] { [expression] }
}

// MARK: - InteractionsClient

public actor InteractionsClient {
    private let apiKey: String
    private let apiRevision: String
    let session: URLSession
    private let baseURL: URL

    public init(apiKey: String, apiRevision: String = "2026-05-20") {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.session = URLSession.shared
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    init(apiKey: String, apiRevision: String = "2026-05-20", session: URLSession) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.session = session
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    func interactionsURL() -> URL {
        baseURL.appendingPathComponent("v1beta/interactions")
    }

    func interactionURL(id: String) -> URL {
        interactionsURL().appendingPathComponent(id)
    }

    private func headers() -> [String: String] {
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

    private func execute(_ urlRequest: URLRequest) async throws -> Data {
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
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

    public func send(_ request: InteractionRequest) async throws -> Interaction {
        let body = try encode(request)
        let urlRequest = makeRequest(url: interactionsURL(), method: "POST", body: body)
        let data = try await execute(urlRequest)
        return try decode(Interaction.self, from: data)
    }

    public func get(id: String) async throws -> Interaction {
        let urlRequest = makeRequest(url: interactionURL(id: id), method: "GET")
        let data = try await execute(urlRequest)
        return try decode(Interaction.self, from: data)
    }

    public func delete(id: String) async throws {
        let urlRequest = makeRequest(url: interactionURL(id: id), method: "DELETE")
        _ = try await execute(urlRequest)
    }

    public func cancel(id: String) async throws {
        let cancelURL = interactionURL(id: id).appendingPathComponent("cancel")
        let urlRequest = makeRequest(url: cancelURL, method: "POST")
        _ = try await execute(urlRequest)
    }
}

---
status: alpha
---

# what-core.md — Public Types in SwiftGeminiInteractions.swift

## GeminiInteractionsError
`public enum GeminiInteractionsError: Error, LocalizedError, @unchecked Sendable`. Uses `@unchecked Sendable` because associated values include `any Error`, `DecodingError`, and `EncodingError`, which are not natively Sendable. Cases: `networkError(URLError)`, `httpError(statusCode: Int, body: String)`, `rateLimitExceeded`, `decodingError(DecodingError)`, `encodingError(EncodingError)`, `invalidInput(String)`, `toolExecutionFailed(name: String, error: any Error)`, `maxIterationsExceeded(Int)`, `pollTimeout(id: String)`, `interactionFailed(id: String, status: InteractionStatus)`. Implements `errorDescription` for human-readable messages.

## InteractionStatus
`public enum InteractionStatus: String, Codable, Sendable`. Raw-value string enum. Cases: `inProgress` (`"in_progress"`), `requiresAction` (`"requires_action"`), `completed`, `failed`, `cancelled`, `incomplete`, `budgetExceeded` (`"budget_exceeded"`).

## ServiceTier
`public enum ServiceTier: String, Codable, Sendable`. Cases: `flex`, `standard`, `priority`.

## ResponseModality
`public enum ResponseModality: String, Codable, Sendable`. Cases: `text`, `image`, `audio`, `video`, `document`.

## ThinkingLevel
`public enum ThinkingLevel: String, Codable, Sendable`. Cases: `none`, `low`, `medium`, `high`.

## ThinkingSummaries
`public enum ThinkingSummaries: String, Codable, Sendable`. Cases: `enabled`, `disabled`.

## ToolChoiceMode
`public enum ToolChoiceMode: String, Codable, Sendable`. Cases: `auto`, `none`, `required`.

## ToolChoiceConfig
`public struct ToolChoiceConfig: Codable, Sendable`. Properties: `mode: ToolChoiceMode`, `allowedTools: [String]?`. JSON keys: `mode`, `allowed_tools`. Init: `(mode:allowedTools:)`.

## ModalityTokens
`public struct ModalityTokens: Codable, Sendable`. Properties: `modality: String`, `tokens: Int`. Init: `(modality:tokens:)`.

## Annotation
`public enum Annotation: Codable, Sendable`. Three cases, all discriminated on `"type"` key: `urlCitation(url: String, title: String?, startIndex: Int, endIndex: Int)`, `fileCitation(documentUri: String, fileName: String, source: String, pageNumber: Int?, startIndex: Int, endIndex: Int)`, `placeCitation(name: String, startIndex: Int, endIndex: Int)`. JSON type strings: `"url_citation"`, `"file_citation"`, `"place_citation"`. Snake_case keys via CodingKeys.

## Content
`public enum Content: Codable, Sendable`. Four cases discriminated on `"type"` key: `text(String, annotations: [Annotation]?)`, `image(data: Data?, mimeType: String?, uri: String?)`, `document(data: Data?, mimeType: String?, uri: String?)`, `video(data: Data?, mimeType: String?, uri: String?)`. JSON type strings: `"text"`, `"image"`, `"document"`, `"video"`. JSON key `mime_type` for `mimeType`.

## GoogleSearchResult
`public struct GoogleSearchResult: Codable, Sendable`. Properties: `title: String?`, `url: String?`, `snippet: String?`. All optional; init with defaults nil.

## FileSearchResult
`public struct FileSearchResult: Codable, Sendable`. Properties: `fileId: String?`, `fileName: String?`, `snippet: String?`, `score: Double?`. JSON keys `file_id`, `file_name`.

## Step
`public enum Step: Codable, Sendable`. 17 cases, all discriminated on `"type"` key. Cases: `userInput(content: [Content])`, `modelOutput(content: [Content])`, `thought(content: [Content], summary: String?)`, `functionCall(id: String, name: String, arguments: String)`, `functionResult(callId: String, result: String, name: String?, isError: Bool?)`, `codeExecutionCall(id: String, code: String)`, `codeExecutionResult(callId: String, output: String, isError: Bool?)`, `googleSearchCall(id: String)`, `googleSearchResult(callId: String, results: [GoogleSearchResult])`, `urlContextCall(id: String, urls: [String])`, `urlContextResult(callId: String, content: String)`, `mcpToolCall(id: String, name: String, arguments: String)`, `mcpToolResult(callId: String, result: String)`, `fileSearchCall(id: String)`, `fileSearchResult(callId: String, results: [FileSearchResult])`, `googleMapsCall(id: String)`, `googleMapsResult(callId: String, result: String)`. JSON wire type for `mcpToolCall` is `"mcp_server_tool_call"` and for `mcpToolResult` is `"mcp_server_tool_result"`. Key `call_id` for `callId`, `is_error` for `isError`.

## InteractionTool
`public enum InteractionTool: Codable, Sendable`. Cases: `function(name: String, description: String, parameters: JSONSchemaValue)`, `codeExecution`, `googleSearch`, `urlContext`, `fileSearch(storeNames: [String], topK: Int?, metadataFilter: String?)`, `googleMaps(latitude: Double, longitude: Double, enableWidget: Bool?)`, `mcpServer`. Extension adds `init(_ definition: ToolDefinition)` that maps `@LLMTool` macro output directly to `.function`. JSON keys: `file_search_store_names`, `top_k`, `metadata_filter`, `enable_widget`.

## InteractionInput
`public enum InteractionInput: Codable, Sendable`. Two cases: `text(String)`, `steps([Step])`. Custom Codable uses `singleValueContainer`: `.text` encodes/decodes as a bare string, `.steps` encodes/decodes as an array. No `"type"` discriminator — shape of the JSON value determines which case.

## GenerationConfig
`public struct GenerationConfig: Codable, Sendable`. Properties: `temperature: Double?`, `topP: Double?`, `maxOutputTokens: Int?`, `seed: Int?`, `stopSequences: [String]?`, `thinkingLevel: ThinkingLevel?`, `thinkingSummaries: ThinkingSummaries?`, `toolChoice: ToolChoiceConfig?`. JSON keys snake_case: `top_p`, `max_output_tokens`, `stop_sequences`, `thinking_level`, `thinking_summaries`, `tool_choice`.

## ResponseDelivery
`public enum ResponseDelivery: String, Codable, Sendable`. Cases: `inline`, `uri`.

## AudioOutputMimeType
`public enum AudioOutputMimeType: String, Codable, Sendable`. Cases: `mp3` (`"audio/mp3"`), `oggOpus` (`"audio/ogg_opus"`), `l16` (`"audio/l16"`), `wav` (`"audio/wav"`), `alaw` (`"audio/alaw"`), `mulaw` (`"audio/mulaw"`).

## ResponseFormat
`public enum ResponseFormat: Codable, Sendable`. Three cases discriminated on `"type"` key: `text(mimeType: String?, schema: JSONSchemaValue?)`, `image(mimeType: String, aspectRatio: String?, imageSize: String?, delivery: ResponseDelivery?)`, `audio(mimeType: AudioOutputMimeType, sampleRate: Int?, bitRate: Int?, delivery: ResponseDelivery?)`. Note: `schema` is Encodable-only; during decoding `schema` is always set to `nil` because `JSONSchemaValue` has no `Decodable` conformance. JSON keys: `mime_type`, `aspect_ratio`, `image_size`, `sample_rate`, `bit_rate`.

## NetworkAllowlistEntry
`public struct NetworkAllowlistEntry: Codable, Sendable`. Properties: `domain: String`, `transform: [String: String]?`.

## EnvironmentNetwork
`public enum EnvironmentNetwork: Codable, Sendable`. Cases: `allowlist([NetworkAllowlistEntry])`, `disabled`. Custom Codable uses `singleValueContainer`: `.disabled` encodes as the literal string `"disabled"`; `.allowlist` encodes as `{"allowlist": [...]}` object.

## EnvironmentSource
`public enum EnvironmentSource: Codable, Sendable`. Three cases discriminated on `"type"` key: `inline(target: String, content: String)`, `repository(source: String, target: String)`, `gcs(source: String, target: String)`.

## EnvironmentConfig
`public struct EnvironmentConfig: Codable, Sendable`. Properties: `sources: [EnvironmentSource]?`, `network: EnvironmentNetwork?`. When encoding, always writes `"type": "remote"` in addition to the optional fields.

## WebhookConfig
`public struct WebhookConfig: Codable, Sendable`. Properties: `notificationEndpoints: [String]`, `userMetadata: [String: String]?`. JSON keys: `notification_endpoints`, `user_metadata`.

## InteractionRequest
`public struct InteractionRequest: Codable, Sendable`. The request body sent to the Interactions API. Properties: `model: String?`, `agent: String?`, `input: InteractionInput`, `systemInstruction: String?`, `tools: [InteractionTool]?`, `stream: Bool?`, `store: Bool?`, `background: Bool?`, `generationConfig: GenerationConfig?`, `responseFormat: ResponseFormat?`, `responseModalities: [ResponseModality]?`, `previousInteractionId: String?`, `environment: EnvironmentConfig?`, `webhookConfig: WebhookConfig?`, `serviceTier: ServiceTier?`. Init requires only `input`; all other fields default nil. JSON keys snake_case.

## Usage
`public struct Usage: Codable, Sendable`. Token accounting for one interaction. Properties: `totalInputTokens: Int`, `totalOutputTokens: Int`, `totalThoughtTokens: Int`, `totalCachedTokens: Int`, `totalToolUseTokens: Int`, `totalTokens: Int`, `inputTokensByModality: [ModalityTokens]`. All JSON keys snake_case.

## Interaction
`public struct Interaction: Codable, Sendable`. The API response object. Properties: `id: String`, `object: String`, `model: String?`, `agent: String?`, `status: InteractionStatus`, `created: String`, `updated: String?`, `steps: [Step]`, `usage: Usage?`. Computed properties: `outputText: String?` (last model_output text), `requiresAction: Bool`, `functionCalls: [Step]` (all `.functionCall` steps), `isComplete: Bool` (true when status is `.completed`, `.failed`, `.cancelled`, `.incomplete`, or `.budgetExceeded`).

## Convenience functions
`public func User(_ text: String) -> Step` — creates `.userInput` with a single text content item. `public func User(_ content: [Content]) -> Step` — creates `.userInput` with the given content array. `public func FunctionOutput(callId:result:isError:) -> Step` — creates `.functionResult` with `name: nil`.

## InteractionConfigParameter
`public protocol InteractionConfigParameter: Sendable`. Single required method: `func apply(to request: inout InteractionRequest)`. Conforming types write their value into the request; `MaxToolCalls` and `RequestTimeout` intentionally do nothing in `apply` and are consumed at a higher level.

## Config parameter structs (17 total)
Each is `public struct X: InteractionConfigParameter` with a single public or private stored value and a public `init`. Types: `Temperature(Double)` (validates 0.0–2.0, sets `generationConfig.temperature`), `TopP(Double)` (validates 0.0–1.0, sets `generationConfig.topP`), `MaxOutputTokens(Int)` (validates > 0, sets `generationConfig.maxOutputTokens`), `Seed(Int)` (sets `generationConfig.seed`), `SystemInstruction(String)` (non-empty guard, sets `systemInstruction`), `PreviousInteractionId(String)` (non-empty guard, sets `previousInteractionId`), `Store(Bool)` (sets `store`), `Background(Bool)` (sets `background`), `ServiceTierParam(ServiceTier)` (sets `serviceTier`), `ThinkingLevelParam(ThinkingLevel)` (sets `generationConfig.thinkingLevel`), `ThinkingSummariesParam(ThinkingSummaries)` (sets `generationConfig.thinkingSummaries`), `ResponseFormatParam(ResponseFormat)` (sets `responseFormat`), `ResponseModalitiesParam([ResponseModality])` (non-empty guard, sets `responseModalities`), `MaxToolCalls(Int)` (`apply` is a no-op; `value` is `public let` so callers can read it), `EnvironmentParam(EnvironmentConfig)` (sets `environment`), `RequestTimeout(TimeInterval)` (`apply` is a no-op; `value` is `public let` so callers can read it), `WebhookConfigParam(WebhookConfig)` (sets `webhookConfig`).

## InteractionConfigBuilder
`@resultBuilder public struct InteractionConfigBuilder`. Produces `[any InteractionConfigParameter]`. Supports: `buildBlock`, `buildOptional`, `buildEither(first:)`, `buildEither(second:)`, `buildArray`, `buildExpression`.

## StepsBuilder
`@resultBuilder public struct StepsBuilder`. Produces `[Step]`. Supports: `buildBlock`, `buildOptional`, `buildEither(first:)`, `buildEither(second:)`, `buildArray`, `buildExpression`.

## ToolsBuilder
`@resultBuilder public struct ToolsBuilder`. Produces `[InteractionTool]`. Supports: `buildBlock`, `buildOptional`, `buildEither(first:)`, `buildEither(second:)`, `buildArray`, `buildExpression`.

## InteractionsClient
`public actor InteractionsClient`. The primary HTTP client. Public init: `init(apiKey: String, apiRevision: String = "2026-05-20")` — uses `URLSession.shared`. Internal init: `init(apiKey:apiRevision:session:)` — not public, used in tests with `MockURLProtocol`. Base URL: `https://generativelanguage.googleapis.com`. All requests go to `v1beta/interactions` (or a subpath). Every request includes headers `x-goog-api-key` and `Api-Revision`; `Content-Type: application/json` is added only when a request body is present. `RequestTimeout` param is consumed here (not in `apply`). Public methods: `send(_ request: InteractionRequest) async throws -> Interaction`, `get(id: String) async throws -> Interaction`, `delete(id: String) async throws`, `cancel(id: String) async throws`, `poll(id:timeout:interval:) async throws -> Interaction`, `nonisolated func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error>`, `nonisolated func resumeStream(id:lastEventId:) -> AsyncThrowingStream<InteractionStreamEvent, Error>`.

## InteractionStreamDelta
`public enum InteractionStreamDelta: Sendable`. Cases: `text(String)`, `image(Data)`, `functionCallArguments(delta: String, callId: String)`, `codeExecutionArguments(delta: String, id: String)`, `googleSearchQuery(String)`, `urlContextUrl(String)`, `thoughtSummary(String)`, `annotation(Annotation)`, `unknown`. Not `public Decodable` — decoded internally via package-internal `init(from:)`.

## InteractionStreamEvent
`public enum InteractionStreamEvent: Codable, Sendable`. Cases: `interactionCreated(Interaction)`, `interactionStatusUpdate(InteractionStatus)`, `stepStart(stepType: String, index: Int)`, `stepDelta(InteractionStreamDelta, stepIndex: Int)`, `stepStop(index: Int)`, `interactionCompleted(Interaction)`, `error(String)`, `unknown`. Decoded via `event_type` key. `encode(to:)` is a no-op (events are receive-only). Unknown event types decode to `.unknown` and are silently dropped by `parseSSE`.

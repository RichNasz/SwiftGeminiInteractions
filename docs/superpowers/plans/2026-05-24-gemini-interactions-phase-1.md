# SwiftGeminiInteractions — Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the package scaffold, all core types, the configuration parameter system, and the `InteractionsClient` actor for the Gemini Interactions API.

**Architecture:** Three-file package (SwiftGeminiInteractions.swift, ToolSession.swift, Agent.swift) following SwiftOpenResponsesDSL conventions. This phase covers the first file in full — all Codable types, config parameters, result builders, and the HTTP client actor. Phase 2 covers ToolSession, Agent, and documentation.

**Tech Stack:** Swift 6.3, SwiftLLMToolMacros (for JSONSchemaValue and LLMTool), XCTest, URLProtocol mocking for HTTP-level tests.

---

## File Map

| File | Role | Phase |
|------|------|-------|
| `Package.swift` | Package manifest | 1 |
| `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift` | All core types, config system, client, streaming | 1 |
| `Sources/SwiftGeminiInteractions/ToolSession.swift` | ToolSession, ToolSessionEvent, ToolSessionResult | 2 |
| `Sources/SwiftGeminiInteractions/Agent.swift` | Agent actor, AgentTool, TranscriptEntry | 2 |
| `Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift` | URLProtocol test double for HTTP-level tests | 1 |
| `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift` | JSON encoding round-trips for all Codable types | 1 |
| `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift` | JSON decoding for Interaction, Step variants, Usage | 1 |
| `Tests/SwiftGeminiInteractionsTests/ConfigTests.swift` | Parameter validation, apply(to:), builder composition | 1 |
| `Tests/SwiftGeminiInteractionsTests/SSEParserTests.swift` | Raw SSE byte → InteractionStreamEvent sequence | 2 |
| `Tests/SwiftGeminiInteractionsTests/ToolSessionTests.swift` | Tool loop, parallel execution, maxIterations | 2 |
| `Tests/SwiftGeminiInteractionsTests/AgentTests.swift` | Transcript, reset, dual init, tool delegation | 2 |
| `Tests/SwiftGeminiInteractionsTests/IntegrationTests.swift` | Live API tests (skipped unless GEMINI_API_KEY set) | 2 |

---

## Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift` (stub)
- Create: `Tests/SwiftGeminiInteractionsTests/SwiftGeminiInteractionsTests.swift` (stub)

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftGeminiInteractions",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SwiftGeminiInteractions", targets: ["SwiftGeminiInteractions"])
    ],
    dependencies: [
        .package(url: "https://github.com/RichNasz/SwiftLLMToolMacros", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftGeminiInteractions",
            dependencies: ["SwiftLLMToolMacros"]
        ),
        .testTarget(
            name: "SwiftGeminiInteractionsTests",
            dependencies: ["SwiftGeminiInteractions"]
        )
    ]
)
```

- [ ] **Step 2: Create stub source file**

```swift
// Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
import Foundation
import SwiftLLMToolMacros
```

- [ ] **Step 3: Create stub test file**

```swift
// Tests/SwiftGeminiInteractionsTests/SwiftGeminiInteractionsTests.swift
import XCTest
@testable import SwiftGeminiInteractions
```

- [ ] **Step 4: Verify the package builds**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "chore: initialize package scaffold"
```

---

## Task 2: Status enums and simple value types

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests for status enums**

```swift
// Tests/SwiftGeminiInteractionsTests/EncodingTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class EncodingTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testInteractionStatusRawValues() {
        XCTAssertEqual(InteractionStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(InteractionStatus.requiresAction.rawValue, "requires_action")
        XCTAssertEqual(InteractionStatus.budgetExceeded.rawValue, "budget_exceeded")
    }

    func testServiceTierRawValues() {
        XCTAssertEqual(ServiceTier.flex.rawValue, "flex")
        XCTAssertEqual(ServiceTier.priority.rawValue, "priority")
    }

    func testResponseModalityRawValues() {
        XCTAssertEqual(ResponseModality.text.rawValue, "text")
        XCTAssertEqual(ResponseModality.document.rawValue, "document")
    }

    func testThinkingLevelRawValues() {
        XCTAssertEqual(ThinkingLevel.none.rawValue, "none")
        XCTAssertEqual(ThinkingLevel.high.rawValue, "high")
    }

    func testThinkingSummariesRawValues() {
        XCTAssertEqual(ThinkingSummaries.enabled.rawValue, "enabled")
        XCTAssertEqual(ThinkingSummaries.disabled.rawValue, "disabled")
    }

    func testToolChoiceModeRawValues() {
        XCTAssertEqual(ToolChoiceMode.auto.rawValue, "auto")
        XCTAssertEqual(ToolChoiceMode.required.rawValue, "required")
    }

    func testToolChoiceConfigEncoding() throws {
        let config = ToolChoiceConfig(mode: .auto, allowedTools: ["myTool"])
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["mode"] as? String, "auto")
        XCTAssertEqual((json["allowed_tools"] as? [String])?.first, "myTool")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter EncodingTests
```
Expected: Compile error — types not defined yet.

- [ ] **Step 3: Implement the types**

```swift
// In SwiftGeminiInteractions.swift

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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter EncodingTests
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add status enums and simple value types"
```

---

## Task 3: ModalityTokens and Usage

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testUsageEncoding() throws {
    let usage = Usage(
        totalInputTokens: 10,
        totalOutputTokens: 20,
        totalThoughtTokens: 5,
        totalCachedTokens: 0,
        totalToolUseTokens: 3,
        totalTokens: 38,
        inputTokensByModality: [ModalityTokens(modality: "text", tokens: 10)]
    )
    let data = try encoder.encode(usage)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["total_input_tokens"] as? Int, 10)
    XCTAssertEqual(json["total_tokens"] as? Int, 38)
    let modalities = json["input_tokens_by_modality"] as? [[String: Any]]
    XCTAssertEqual(modalities?.first?["modality"] as? String, "text")
}
```

Create `DecodingTests.swift`:
```swift
// Tests/SwiftGeminiInteractionsTests/DecodingTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testUsageDecoding() throws {
        let json = """
        {
            "total_input_tokens": 10,
            "total_output_tokens": 20,
            "total_thought_tokens": 5,
            "total_cached_tokens": 0,
            "total_tool_use_tokens": 3,
            "total_tokens": 38,
            "input_tokens_by_modality": [{"modality": "text", "tokens": 10}]
        }
        """.data(using: .utf8)!
        let usage = try decoder.decode(Usage.self, from: json)
        XCTAssertEqual(usage.totalInputTokens, 10)
        XCTAssertEqual(usage.totalTokens, 38)
        XCTAssertEqual(usage.inputTokensByModality.first?.modality, "text")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testUsageEncoding|DecodingTests/testUsageDecoding"
```
Expected: Compile error — types not defined.

- [ ] **Step 3: Implement ModalityTokens and Usage**

```swift
public struct ModalityTokens: Codable, Sendable {
    public let modality: String
    public let tokens: Int

    public init(modality: String, tokens: Int) {
        self.modality = modality
        self.tokens = tokens
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testUsageEncoding|DecodingTests/testUsageDecoding"
```
Expected: Both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add ModalityTokens and Usage types"
```

---

## Task 4: Content and Annotation

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testTextContentEncoding() throws {
    let content = Content.text("Hello world", annotations: nil)
    let data = try encoder.encode(content)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "text")
    XCTAssertEqual(json["text"] as? String, "Hello world")
}

func testImageContentEncoding() throws {
    let imageData = Data([0xFF, 0xD8])
    let content = Content.image(data: imageData, mimeType: "image/jpeg", uri: nil)
    let data = try encoder.encode(content)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "image")
    XCTAssertEqual(json["mime_type"] as? String, "image/jpeg")
    XCTAssertNotNil(json["data"])
}

func testUrlCitationEncoding() throws {
    let annotation = Annotation.urlCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 5)
    let data = try encoder.encode(annotation)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "url_citation")
    XCTAssertEqual(json["url"] as? String, "https://example.com")
}
```

Add to `DecodingTests`:
```swift
func testTextContentDecoding() throws {
    let json = """
    {"type": "text", "text": "Hello world"}
    """.data(using: .utf8)!
    let content = try decoder.decode(Content.self, from: json)
    if case .text(let text, _) = content {
        XCTAssertEqual(text, "Hello world")
    } else {
        XCTFail("Expected .text case")
    }
}

func testFileCitationDecoding() throws {
    let json = """
    {
        "type": "file_citation",
        "document_uri": "gs://bucket/file.pdf",
        "file_name": "file.pdf",
        "source": "upload",
        "start_index": 0,
        "end_index": 10
    }
    """.data(using: .utf8)!
    let annotation = try decoder.decode(Annotation.self, from: json)
    if case .fileCitation(let uri, let name, _, _, _, _) = annotation {
        XCTAssertEqual(uri, "gs://bucket/file.pdf")
        XCTAssertEqual(name, "file.pdf")
    } else {
        XCTFail("Expected .fileCitation case")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testTextContentEncoding|EncodingTests/testImageContentEncoding|DecodingTests/testTextContentDecoding"
```
Expected: Compile error.

- [ ] **Step 3: Implement Content and Annotation**

```swift
public enum Annotation: Codable, Sendable {
    case urlCitation(url: String, title: String?, startIndex: Int, endIndex: Int)
    case fileCitation(documentUri: String, fileName: String, source: String, pageNumber: Int?, startIndex: Int, endIndex: Int)
    case placeCitation(name: String, startIndex: Int, endIndex: Int)

    private enum CodingKeys: String, CodingKey {
        case type, url, title
        case startIndex = "start_index"
        case endIndex   = "end_index"
        case documentUri = "document_uri"
        case fileName    = "file_name"
        case source, pageNumber = "page_number", name
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
        case type, text, data, annotations
        case mimeType = "mime_type"
        case uri
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testTextContent|EncodingTests/testImageContent|EncodingTests/testUrlCitation|DecodingTests/testTextContent|DecodingTests/testFileCitation"
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add Content and Annotation types with custom Codable"
```

---

## Task 5: Step type

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testUserInputStepEncoding() throws {
    let step = Step.userInput(content: [.text("Hello", annotations: nil)])
    let data = try encoder.encode(step)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "user_input")
    let content = json["content"] as? [[String: Any]]
    XCTAssertEqual(content?.first?["text"] as? String, "Hello")
}

func testFunctionCallStepEncoding() throws {
    let step = Step.functionCall(id: "call-1", name: "myFn", arguments: "{\"x\": 1}")
    let data = try encoder.encode(step)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "function_call")
    XCTAssertEqual(json["id"] as? String, "call-1")
    XCTAssertEqual(json["name"] as? String, "myFn")
    XCTAssertEqual(json["arguments"] as? String, "{\"x\": 1}")
}

func testFunctionResultStepEncoding() throws {
    let step = Step.functionResult(callId: "call-1", result: "42", name: "myFn", isError: false)
    let data = try encoder.encode(step)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "function_result")
    XCTAssertEqual(json["call_id"] as? String, "call-1")
    XCTAssertEqual(json["result"] as? String, "42")
}

func testGoogleSearchCallStepEncoding() throws {
    let step = Step.googleSearchCall(id: "search-1")
    let data = try encoder.encode(step)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "google_search_call")
    XCTAssertEqual(json["id"] as? String, "search-1")
}
```

Add to `DecodingTests`:
```swift
func testModelOutputStepDecoding() throws {
    let json = """
    {
        "type": "model_output",
        "content": [{"type": "text", "text": "Hi there"}]
    }
    """.data(using: .utf8)!
    let step = try decoder.decode(Step.self, from: json)
    if case .modelOutput(let content) = step {
        if case .text(let text, _) = content.first {
            XCTAssertEqual(text, "Hi there")
        } else { XCTFail("Expected text content") }
    } else { XCTFail("Expected .modelOutput") }
}

func testFunctionCallStepDecoding() throws {
    let json = """
    {"type": "function_call", "id": "call-1", "name": "myFn", "arguments": "{\\"x\\": 1}"}
    """.data(using: .utf8)!
    let step = try decoder.decode(Step.self, from: json)
    if case .functionCall(let id, let name, let args) = step {
        XCTAssertEqual(id, "call-1")
        XCTAssertEqual(name, "myFn")
        XCTAssertEqual(args, "{\"x\": 1}")
    } else { XCTFail("Expected .functionCall") }
}

func testUnknownStepTypeThrows() {
    let json = """
    {"type": "unknown_future_type", "id": "x"}
    """.data(using: .utf8)!
    XCTAssertThrowsError(try decoder.decode(Step.self, from: json))
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testUserInputStep|EncodingTests/testFunctionCallStep|DecodingTests/testModelOutputStep"
```
Expected: Compile error.

- [ ] **Step 3: Add GoogleSearchResult and FileSearchResult**

```swift
public struct GoogleSearchResult: Codable, Sendable {
    public let title: String?
    public let url: String?
    public let snippet: String?

    public init(title: String? = nil, url: String? = nil, snippet: String? = nil) {
        self.title = title; self.url = url; self.snippet = snippet
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
```

- [ ] **Step 4: Implement Step**

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testUserInputStep|EncodingTests/testFunctionCallStep|EncodingTests/testFunctionResultStep|EncodingTests/testGoogleSearchCallStep|DecodingTests/testModelOutputStep|DecodingTests/testFunctionCallStep|DecodingTests/testUnknownStepType"
```
Expected: All 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add Step type with full discriminated Codable for all 17 cases"
```

---

## Task 6: InteractionTool

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testFunctionToolEncoding() throws {
    let schema = JSONSchemaValue.object(["x": .number(nil, nil, nil)])
    let tool = InteractionTool.function(name: "myFn", description: "Does something", parameters: schema)
    let data = try encoder.encode(tool)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "function")
    XCTAssertEqual(json["name"] as? String, "myFn")
    XCTAssertNotNil(json["parameters"])
}

func testGoogleSearchToolEncoding() throws {
    let tool = InteractionTool.googleSearch
    let data = try encoder.encode(tool)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "google_search")
    XCTAssertNil(json["name"])
}

func testFileSearchToolEncoding() throws {
    let tool = InteractionTool.fileSearch(storeNames: ["myStore"], topK: 5, metadataFilter: nil)
    let data = try encoder.encode(tool)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "file_search")
    XCTAssertEqual((json["file_search_store_names"] as? [String])?.first, "myStore")
    XCTAssertEqual(json["top_k"] as? Int, 5)
}

func testGoogleMapsToolEncoding() throws {
    let tool = InteractionTool.googleMaps(latitude: 37.7749, longitude: -122.4194, enableWidget: true)
    let data = try encoder.encode(tool)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "google_maps")
    XCTAssertEqual(json["latitude"] as? Double, 37.7749, accuracy: 0.0001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testFunctionTool|EncodingTests/testGoogleSearchTool|EncodingTests/testFileSearchTool|EncodingTests/testGoogleMapsTool"
```
Expected: Compile error.

- [ ] **Step 3: Implement InteractionTool**

```swift
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
            self = .function(
                name: try container.decode(String.self, forKey: .name),
                description: try container.decode(String.self, forKey: .description),
                parameters: try container.decode(JSONSchemaValue.self, forKey: .parameters)
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testFunctionTool|EncodingTests/testGoogleSearchTool|EncodingTests/testFileSearchTool|EncodingTests/testGoogleMapsTool"
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add InteractionTool with discriminated Codable for all 7 tool types"
```

---

## Task 7: InteractionInput, GenerationConfig, and InteractionRequest

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testInteractionInputTextEncoding() throws {
    let input = InteractionInput.text("Hello!")
    let data = try encoder.encode(input)
    let str = String(data: data, encoding: .utf8)!
    XCTAssertEqual(str, "\"Hello!\"")
}

func testInteractionInputStepsEncoding() throws {
    let input = InteractionInput.steps([.userInput(content: [.text("Hi", annotations: nil)])])
    let data = try encoder.encode(input)
    let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertNotNil(arr)
    XCTAssertEqual(arr?.first?["type"] as? String, "user_input")
}

func testGenerationConfigEncoding() throws {
    let config = GenerationConfig(temperature: 0.7, topP: 0.9, maxOutputTokens: 1024,
                                   seed: nil, stopSequences: nil, thinkingLevel: .medium,
                                   thinkingSummaries: nil, toolChoice: nil)
    let data = try encoder.encode(config)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["temperature"] as? Double, 0.7, accuracy: 0.001)
    XCTAssertEqual(json["max_output_tokens"] as? Int, 1024)
    XCTAssertEqual(json["thinking_level"] as? String, "medium")
}

func testInteractionRequestEncoding() throws {
    var request = InteractionRequest(input: .text("Hello"))
    request.model = "gemini-3-flash-preview"
    request.store = true
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["model"] as? String, "gemini-3-flash-preview")
    XCTAssertEqual(json["store"] as? Bool, true)
    XCTAssertNotNil(json["input"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testInteractionInput|EncodingTests/testGenerationConfig|EncodingTests/testInteractionRequest"
```
Expected: Compile error.

- [ ] **Step 3: Implement types**

```swift
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
```

Note: `ResponseFormat`, `EnvironmentConfig`, and `WebhookConfig` are referenced here but defined in Tasks 8–9. The compiler will resolve them when those tasks are complete. Add `// TODO: defined in Task 8/9` comments temporarily if needed to build.

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testInteractionInput|EncodingTests/testGenerationConfig|EncodingTests/testInteractionRequest"
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add InteractionInput, GenerationConfig, and InteractionRequest"
```

---

## Task 8: ResponseFormat, AudioOutputMimeType, ResponseDelivery

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testTextResponseFormatEncoding() throws {
    let format = ResponseFormat.text(mimeType: "application/json", schema: nil)
    let data = try encoder.encode(format)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "text")
    XCTAssertEqual(json["mime_type"] as? String, "application/json")
}

func testImageResponseFormatEncoding() throws {
    let format = ResponseFormat.image(mimeType: "image/png", aspectRatio: "16:9", imageSize: nil, delivery: .inline)
    let data = try encoder.encode(format)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "image")
    XCTAssertEqual(json["mime_type"] as? String, "image/png")
    XCTAssertEqual(json["delivery"] as? String, "inline")
}

func testAudioResponseFormatEncoding() throws {
    let format = ResponseFormat.audio(mimeType: .mp3, sampleRate: 44100, bitRate: 128, delivery: .uri)
    let data = try encoder.encode(format)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "audio")
    XCTAssertEqual(json["mime_type"] as? String, "audio/mp3")
    XCTAssertEqual(json["sample_rate"] as? Int, 44100)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testTextResponseFormat|EncodingTests/testImageResponseFormat|EncodingTests/testAudioResponseFormat"
```
Expected: Compile error.

- [ ] **Step 3: Implement types**

```swift
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
                schema: try container.decodeIfPresent(JSONSchemaValue.self, forKey: .schema)
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testTextResponseFormat|EncodingTests/testImageResponseFormat|EncodingTests/testAudioResponseFormat"
```
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add ResponseFormat, AudioOutputMimeType, ResponseDelivery"
```

---

## Task 9: EnvironmentConfig, WebhookConfig

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testEnvironmentConfigWithInlineSource() throws {
    let env = EnvironmentConfig(
        sources: [.inline(target: "/workspace/main.py", content: "print('hello')")],
        network: .disabled
    )
    let data = try encoder.encode(env)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["type"] as? String, "remote")
    XCTAssertEqual(json["network"] as? String, "disabled")
    let sources = json["sources"] as? [[String: Any]]
    XCTAssertEqual(sources?.first?["type"] as? String, "inline")
}

func testEnvironmentConfigWithAllowlist() throws {
    let entry = NetworkAllowlistEntry(domain: "pypi.org", transform: nil)
    let env = EnvironmentConfig(sources: nil, network: .allowlist([entry]))
    let data = try encoder.encode(env)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let network = json["network"] as? [String: Any]
    let allowlist = network?["allowlist"] as? [[String: Any]]
    XCTAssertEqual(allowlist?.first?["domain"] as? String, "pypi.org")
}

func testWebhookConfigEncoding() throws {
    let webhook = WebhookConfig(notificationEndpoints: ["https://example.com/hook"], userMetadata: ["jobId": "123"])
    let data = try encoder.encode(webhook)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual((json["notification_endpoints"] as? [String])?.first, "https://example.com/hook")
    XCTAssertEqual((json["user_metadata"] as? [String: String])?["jobId"], "123")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testEnvironmentConfig|EncodingTests/testWebhookConfig"
```
Expected: Compile error.

- [ ] **Step 3: Implement types**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testEnvironmentConfig|EncodingTests/testWebhookConfig"
```
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add EnvironmentConfig, EnvironmentSource, EnvironmentNetwork, WebhookConfig"
```

---

## Task 10: Interaction response type

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `DecodingTests`:
```swift
func testInteractionDecoding() throws {
    let json = """
    {
        "id": "v1_abc123",
        "object": "interaction",
        "model": "gemini-3-flash-preview",
        "status": "completed",
        "created": "2026-05-24T10:00:00Z",
        "steps": [
            {"type": "user_input", "content": [{"type": "text", "text": "Hello"}]},
            {"type": "model_output", "content": [{"type": "text", "text": "Hi there!"}]}
        ],
        "usage": {
            "total_input_tokens": 5, "total_output_tokens": 10,
            "total_thought_tokens": 0, "total_cached_tokens": 0,
            "total_tool_use_tokens": 0, "total_tokens": 15,
            "input_tokens_by_modality": []
        }
    }
    """.data(using: .utf8)!
    let interaction = try decoder.decode(Interaction.self, from: json)
    XCTAssertEqual(interaction.id, "v1_abc123")
    XCTAssertEqual(interaction.status, .completed)
    XCTAssertEqual(interaction.steps.count, 2)
    XCTAssertEqual(interaction.outputText, "Hi there!")
    XCTAssertFalse(interaction.requiresAction)
    XCTAssertTrue(interaction.isComplete)
}

func testInteractionRequiresActionConvenience() throws {
    let json = """
    {
        "id": "v1_xyz",
        "object": "interaction",
        "model": "gemini-3-flash-preview",
        "status": "requires_action",
        "created": "2026-05-24T10:00:00Z",
        "steps": [
            {"type": "function_call", "id": "call-1", "name": "myFn", "arguments": "{}"}
        ]
    }
    """.data(using: .utf8)!
    let interaction = try decoder.decode(Interaction.self, from: json)
    XCTAssertTrue(interaction.requiresAction)
    XCTAssertFalse(interaction.isComplete)
    XCTAssertEqual(interaction.functionCalls.count, 1)
    XCTAssertNil(interaction.outputText)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "DecodingTests/testInteractionDecoding|DecodingTests/testInteractionRequiresAction"
```
Expected: Compile error.

- [ ] **Step 3: Implement Interaction**

```swift
public struct Interaction: Codable, Sendable {
    public let id: String
    public let object: String
    public let model: String?
    public let agent: String?
    public let status: InteractionStatus
    public let created: String
    public let updated: String?
    public let steps: [Step]
    public let usage: Usage?

    public init(id: String, object: String = "interaction", model: String? = nil,
                agent: String? = nil, status: InteractionStatus, created: String,
                updated: String? = nil, steps: [Step] = [], usage: Usage? = nil) {
        self.id = id; self.object = object; self.model = model; self.agent = agent
        self.status = status; self.created = created; self.updated = updated
        self.steps = steps; self.usage = usage
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
        steps.filter { if case .functionCall = $0 { return true }; return false }
    }

    public var isComplete: Bool {
        switch status {
        case .completed, .failed, .cancelled, .incomplete, .budgetExceeded: return true
        default: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, object, model, agent, status, created, updated, steps, usage
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "DecodingTests/testInteractionDecoding|DecodingTests/testInteractionRequiresAction"
```
Expected: Both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add Interaction response type with convenience properties"
```

---

## Task 11: GeminiInteractionsError and convenience constructors

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/EncodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `EncodingTests`:
```swift
func testGeminiInteractionsErrorLocalizedDescription() {
    let error = GeminiInteractionsError.rateLimitExceeded
    XCTAssertFalse(error.errorDescription!.isEmpty)

    let toolError = GeminiInteractionsError.toolExecutionFailed(name: "myFn", error: URLError(.badURL))
    XCTAssertTrue(toolError.errorDescription!.contains("myFn"))

    let maxIter = GeminiInteractionsError.maxIterationsExceeded(10)
    XCTAssertTrue(maxIter.errorDescription!.contains("10"))

    let timeout = GeminiInteractionsError.pollTimeout(id: "v1_abc")
    XCTAssertTrue(timeout.errorDescription!.contains("v1_abc"))
}

func testConvenienceConstructors() throws {
    let userStep = User("Hello!")
    if case .userInput(let content) = userStep,
       case .text(let text, _) = content.first {
        XCTAssertEqual(text, "Hello!")
    } else { XCTFail("User() should produce .userInput with text content") }

    let resultStep = FunctionOutput(callId: "call-1", result: "42")
    if case .functionResult(let callId, let result, _, let isError) = resultStep {
        XCTAssertEqual(callId, "call-1")
        XCTAssertEqual(result, "42")
        XCTAssertEqual(isError, false)
    } else { XCTFail("FunctionOutput() should produce .functionResult") }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "EncodingTests/testGeminiInteractionsError|EncodingTests/testConvenienceConstructors"
```
Expected: Compile error.

- [ ] **Step 3: Implement GeminiInteractionsError and convenience constructors**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "EncodingTests/testGeminiInteractionsError|EncodingTests/testConvenienceConstructors"
```
Expected: Both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add GeminiInteractionsError and convenience step constructors"
```

---

## Task 12: InteractionConfigParameter protocol and all parameter types

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/ConfigTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SwiftGeminiInteractionsTests/ConfigTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class ConfigTests: XCTestCase {

    func testTemperatureAppliesAndValidates() {
        var request = InteractionRequest(input: .text("hi"))
        Temperature(0.7).apply(to: &request)
        XCTAssertEqual(request.generationConfig?.temperature, 0.7, accuracy: 0.001)
        // Out of range — should clamp or be caught at init
        let invalid = Temperature(-0.1)
        var r2 = InteractionRequest(input: .text("hi"))
        invalid.apply(to: &r2)
        // Temperature below 0 should not apply (or clamps to 0)
        XCTAssertNil(r2.generationConfig?.temperature)
    }

    func testMaxOutputTokensApplies() {
        var request = InteractionRequest(input: .text("hi"))
        MaxOutputTokens(512).apply(to: &request)
        XCTAssertEqual(request.generationConfig?.maxOutputTokens, 512)
    }

    func testSystemInstructionApplies() {
        var request = InteractionRequest(input: .text("hi"))
        SystemInstruction("Be helpful.").apply(to: &request)
        XCTAssertEqual(request.systemInstruction, "Be helpful.")
    }

    func testEmptySystemInstructionDoesNotApply() {
        var request = InteractionRequest(input: .text("hi"))
        SystemInstruction("").apply(to: &request)
        XCTAssertNil(request.systemInstruction)
    }

    func testStoreApplies() {
        var request = InteractionRequest(input: .text("hi"))
        Store(true).apply(to: &request)
        XCTAssertEqual(request.store, true)
    }

    func testPreviousInteractionIdApplies() {
        var request = InteractionRequest(input: .text("hi"))
        PreviousInteractionId("v1_abc").apply(to: &request)
        XCTAssertEqual(request.previousInteractionId, "v1_abc")
    }

    func testEmptyPreviousInteractionIdDoesNotApply() {
        var request = InteractionRequest(input: .text("hi"))
        PreviousInteractionId("").apply(to: &request)
        XCTAssertNil(request.previousInteractionId)
    }

    func testMultipleParamsApplyInOrder() {
        var request = InteractionRequest(input: .text("hi"))
        let params: [any InteractionConfigParameter] = [
            Temperature(0.5),
            MaxOutputTokens(1024),
            Store(true)
        ]
        for p in params { p.apply(to: &request) }
        XCTAssertEqual(request.generationConfig?.temperature, 0.5, accuracy: 0.001)
        XCTAssertEqual(request.generationConfig?.maxOutputTokens, 1024)
        XCTAssertEqual(request.store, true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ConfigTests
```
Expected: Compile error — types not defined.

- [ ] **Step 3: Implement the protocol and all parameter types**

```swift
public protocol InteractionConfigParameter: Sendable {
    func apply(to request: inout InteractionRequest)
}

// Helper: ensure GenerationConfig exists on the request
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
    let value: Int   // internal — read by ToolSession
    public init(_ value: Int) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by ToolSession */ }
}

public struct EnvironmentParam: InteractionConfigParameter {
    private let value: EnvironmentConfig
    public init(_ value: EnvironmentConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.environment = value }
}

public struct RequestTimeout: InteractionConfigParameter {
    let value: TimeInterval   // internal — read by InteractionsClient
    public init(_ value: TimeInterval) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by client */ }
}

public struct WebhookConfigParam: InteractionConfigParameter {
    private let value: WebhookConfig
    public init(_ value: WebhookConfig) { self.value = value }
    public func apply(to request: inout InteractionRequest) { request.webhookConfig = value }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter ConfigTests
```
Expected: All 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add InteractionConfigParameter protocol and all 17 parameter types"
```

---

## Task 13: Result builders

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/ConfigTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ConfigTests`:
```swift
func testInteractionConfigBuilderComposesParams() {
    @InteractionConfigBuilder func buildConfig() -> [any InteractionConfigParameter] {
        Temperature(0.8)
        MaxOutputTokens(2048)
        Store(true)
    }
    var request = InteractionRequest(input: .text("hi"))
    for p in buildConfig() { p.apply(to: &request) }
    XCTAssertEqual(request.generationConfig?.temperature, 0.8, accuracy: 0.001)
    XCTAssertEqual(request.generationConfig?.maxOutputTokens, 2048)
    XCTAssertEqual(request.store, true)
}

func testStepsBuilderComposesSteps() {
    @StepsBuilder func buildSteps() -> [Step] {
        User("Hello")
        FunctionOutput(callId: "c1", result: "done")
    }
    let steps = buildSteps()
    XCTAssertEqual(steps.count, 2)
    if case .userInput = steps[0] { } else { XCTFail("First step should be userInput") }
    if case .functionResult = steps[1] { } else { XCTFail("Second step should be functionResult") }
}

func testToolsBuilderComposesTools() {
    let schema = JSONSchemaValue.object([:])
    @ToolsBuilder func buildTools() -> [InteractionTool] {
        InteractionTool.googleSearch
        InteractionTool.function(name: "myFn", description: "desc", parameters: schema)
    }
    let tools = buildTools()
    XCTAssertEqual(tools.count, 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ConfigTests/testInteractionConfigBuilder|ConfigTests/testStepsBuilder|ConfigTests/testToolsBuilder"
```
Expected: Compile error.

- [ ] **Step 3: Implement result builders**

```swift
@resultBuilder
public struct InteractionConfigBuilder {
    public static func buildBlock(_ components: any InteractionConfigParameter...) -> [any InteractionConfigParameter] {
        components
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
    public static func buildBlock(_ components: Step...) -> [Step] { components }
    public static func buildOptional(_ component: [Step]?) -> [Step] { component ?? [] }
    public static func buildEither(first component: [Step]) -> [Step] { component }
    public static func buildEither(second component: [Step]) -> [Step] { component }
    public static func buildArray(_ components: [[Step]]) -> [Step] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: Step) -> [Step] { [expression] }
}

@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ components: InteractionTool...) -> [InteractionTool] { components }
    public static func buildOptional(_ component: [InteractionTool]?) -> [InteractionTool] { component ?? [] }
    public static func buildEither(first component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildEither(second component: [InteractionTool]) -> [InteractionTool] { component }
    public static func buildArray(_ components: [[InteractionTool]]) -> [InteractionTool] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: InteractionTool) -> [InteractionTool] { [expression] }
}

@resultBuilder
public struct AgentToolBuilder {
    public static func buildBlock(_ components: AgentTool...) -> [AgentTool] { components }
    public static func buildOptional(_ component: [AgentTool]?) -> [AgentTool] { component ?? [] }
    public static func buildEither(first component: [AgentTool]) -> [AgentTool] { component }
    public static func buildEither(second component: [AgentTool]) -> [AgentTool] { component }
    public static func buildArray(_ components: [[AgentTool]]) -> [AgentTool] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: AgentTool) -> [AgentTool] { [expression] }
}
```

Note: `AgentTool` is defined in `Agent.swift` (Phase 2). Add a forward declaration comment here so the builder compiles once Agent.swift exists.

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ConfigTests/testInteractionConfigBuilder|ConfigTests/testStepsBuilder|ConfigTests/testToolsBuilder"
```
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add result builders for config, steps, tools, and agent tools"
```

---

## Task 14: InteractionsClient — HTTP core

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Create MockURLProtocol test helper**

```swift
// Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift
import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeTestClient(apiKey: String = "test-key", apiRevision: String = "2026-05-20") -> InteractionsClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return InteractionsClient(apiKey: apiKey, apiRevision: apiRevision, session: session)
}

func makeInteractionJSON(id: String = "v1_test", status: String = "completed", model: String = "gemini-3-flash-preview") -> Data {
    """
    {
        "id": "\(id)",
        "object": "interaction",
        "model": "\(model)",
        "status": "\(status)",
        "created": "2026-05-24T10:00:00Z",
        "steps": [
            {"type": "model_output", "content": [{"type": "text", "text": "Hello!"}]}
        ]
    }
    """.data(using: .utf8)!
}
```

- [ ] **Step 2: Write failing client tests**

Add to `DecodingTests`:
```swift
func testClientSendReturnsInteraction() async throws {
    MockURLProtocol.requestHandler = { request in
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Revision"), "2026-05-20")
        XCTAssertEqual(request.httpMethod, "POST")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }
    let client = makeTestClient()
    var request = InteractionRequest(input: .text("Hello"))
    request.model = "gemini-3-flash-preview"
    let interaction = try await client.send(request)
    XCTAssertEqual(interaction.id, "v1_test")
    XCTAssertEqual(interaction.status, .completed)
}

func testClientSend429ThrowsRateLimit() async {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        return (response, Data())
    }
    let client = makeTestClient()
    var request = InteractionRequest(input: .text("Hello"))
    request.model = "gemini-3-flash-preview"
    do {
        _ = try await client.send(request)
        XCTFail("Should have thrown")
    } catch GeminiInteractionsError.rateLimitExceeded {
        // pass
    } catch {
        XCTFail("Wrong error: \(error)")
    }
}

func testClientGetReturnsInteraction() async throws {
    MockURLProtocol.requestHandler = { request in
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url!.path.hasSuffix("/v1_test"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }
    let client = makeTestClient()
    let interaction = try await client.get(id: "v1_test")
    XCTAssertEqual(interaction.id, "v1_test")
}

func testClientDeleteSends204() async throws {
    MockURLProtocol.requestHandler = { request in
        XCTAssertEqual(request.httpMethod, "DELETE")
        let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        return (response, Data())
    }
    let client = makeTestClient()
    try await client.delete(id: "v1_test")  // should not throw
}

func testClientCancelSendsPostToCancel() async throws {
    MockURLProtocol.requestHandler = { request in
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.hasSuffix("/cancel"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON(status: "cancelled"))
    }
    let client = makeTestClient()
    try await client.cancel(id: "v1_test")  // should not throw
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter "DecodingTests/testClientSend|DecodingTests/testClientGet|DecodingTests/testClientDelete|DecodingTests/testClientCancel"
```
Expected: Compile error — InteractionsClient not defined.

- [ ] **Step 4: Implement InteractionsClient**

```swift
public actor InteractionsClient {
    private let apiKey: String
    private let apiRevision: String
    private let session: URLSession
    let baseURL: URL

    public init(apiKey: String, apiRevision: String = "2026-05-20") {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.session = URLSession.shared
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    // Internal init for testing — injects a URLSession with MockURLProtocol
    init(apiKey: String, apiRevision: String = "2026-05-20", session: URLSession) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.session = session
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    // MARK: - Private helpers

    private func interactionsURL() -> URL {
        baseURL.appendingPathComponent("v1beta/interactions")
    }

    private func interactionURL(id: String) -> URL {
        interactionsURL().appendingPathComponent(id)
    }

    private func headers() -> [String: String] {
        [
            "x-goog-api-key": apiKey,
            "Api-Revision": apiRevision,
            "Content-Type": "application/json"
        ]
    }

    private func makeRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        for (key, value) in headers() {
            urlRequest.setValue(value, forHTTPHeaderField: key)
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

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch let encodingError as EncodingError {
            throw GeminiInteractionsError.encodingError(encodingError)
        }
    }

    // MARK: - Public API

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
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter "DecodingTests/testClientSend|DecodingTests/testClientGet|DecodingTests/testClientDelete|DecodingTests/testClientCancel"
```
Expected: All 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add InteractionsClient actor with send, get, delete, cancel"
```

---

## Task 15: InteractionsClient — poll()

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/DecodingTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `DecodingTests`:
```swift
func testPollReturnsImmediatelyOnCompleted() async throws {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON(status: "completed"))
    }
    let client = makeTestClient()
    let interaction = try await client.poll(id: "v1_test", timeout: .seconds(5), interval: .milliseconds(100))
    XCTAssertEqual(interaction.status, .completed)
}

func testPollReturnOnCancelled() async throws {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON(status: "cancelled"))
    }
    let client = makeTestClient()
    let interaction = try await client.poll(id: "v1_test", timeout: .seconds(5), interval: .milliseconds(100))
    XCTAssertEqual(interaction.status, .cancelled)
}

func testPollTimeoutThrows() async {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON(status: "in_progress"))
    }
    let client = makeTestClient()
    do {
        _ = try await client.poll(id: "v1_timeout", timeout: .milliseconds(200), interval: .milliseconds(50))
        XCTFail("Should have thrown pollTimeout")
    } catch GeminiInteractionsError.pollTimeout(let id) {
        XCTAssertEqual(id, "v1_timeout")
    } catch {
        XCTFail("Wrong error type: \(error)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "DecodingTests/testPoll"
```
Expected: Compile error — `poll` not defined on InteractionsClient.

- [ ] **Step 3: Add poll() to InteractionsClient**

```swift
// Add inside the InteractionsClient actor body:

public func poll(
    id: String,
    timeout: Duration = .seconds(300),
    interval: Duration = .seconds(5)
) async throws -> Interaction {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        let interaction = try await get(id: id)
        if interaction.isComplete { return interaction }
        try await Task.sleep(for: interval)
    }
    throw GeminiInteractionsError.pollTimeout(id: id)
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "DecodingTests/testPoll"
```
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add poll() background interaction helper to InteractionsClient"
```

---

## Phase 1 complete

At this point the package has:
- ✅ All Codable types (Status enums, Usage, Content, Annotation, Step, InteractionTool, InteractionRequest, GenerationConfig, ResponseFormat, EnvironmentConfig, WebhookConfig, Interaction, GeminiInteractionsError)
- ✅ All 17 `InteractionConfigParameter` types
- ✅ All 4 result builders
- ✅ `InteractionsClient` with `send`, `get`, `delete`, `cancel`, `poll`
- ✅ Unit tests covering encoding, decoding, config application, and HTTP behavior

**Run full test suite before moving to Phase 2:**

```bash
swift test
```
Expected: All tests pass, no warnings about Sendable or concurrency.

**Phase 2 covers:** `InteractionStreamEvent`, SSE parser, `stream()`, `resumeStream()`, `ToolSession`, `Agent`, spec files, CLAUDE.md, README, Examples, and guide docs.

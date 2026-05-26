# Configuration

SwiftGeminiInteractions provides 17 configuration parameters for controlling model behavior, request processing, and output formats. Parameters are applied using the `InteractionConfigParameter` protocol and can be composed with result builders.

## Using Config Parameters

Each parameter conforms to `InteractionConfigParameter` and implements an `apply(to:)` method that modifies an `InteractionRequest`. Apply parameters directly or use the `@InteractionConfigBuilder` result builder with `Agent`.

### Direct Application

```swift
var request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("What is the capital of France?"))
}

// Apply individual parameters
Temperature(0.7).apply(to: &request)
MaxOutputTokens(1024).apply(to: &request)
SystemInstruction("You are a helpful assistant.").apply(to: &request)

let interaction = try await client.send(request)
```

### Using the Result Builder with Agent

The `@InteractionConfigBuilder` supports conditionals and loops for dynamic configuration:

```swift
let useExtendedThinking = true
let maxTokens = 2048

let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20",
    instructions: "You are a helpful assistant."
) {
    // Conditionals work seamlessly
    if useExtendedThinking {
        ThinkingLevelParam(.high)
        ThinkingSummariesParam(.enabled)
    }
    
    Temperature(0.7)
    MaxOutputTokens(maxTokens)
    
    // Loops are supported
    for modality in [ResponseModality.text, .image] {
        // Parameters are collected and deduplicated
    }
    
    ServiceTierParam(.flex)
}

let response = try await agent.send("Explain quantum computing.")
```

## Parameter Reference

### GenerationConfig Parameters

These parameters are set on `request.generationConfig` and control model sampling behavior:

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `Temperature(Double)` | `Double` | 0.0–2.0 | Sampling temperature. Higher values increase randomness. |
| `TopP(Double)` | `Double` | 0.0–1.0 | Nucleus sampling probability threshold. |
| `MaxOutputTokens(Int)` | `Int` | 1+ | Maximum number of tokens in the output. |
| `Seed(Int)` | `Int` | any | Deterministic seed for reproducible outputs. |
| `ThinkingLevelParam(ThinkingLevel)` | `ThinkingLevel` | `.none`, `.low`, `.medium`, `.high` | Extended thinking depth. |
| `ThinkingSummariesParam(ThinkingSummaries)` | `ThinkingSummaries` | `.enabled`, `.disabled` | Whether to include thinking summaries. |

```swift
Temperature(1.2).apply(to: &request)
TopP(0.95).apply(to: &request)
MaxOutputTokens(4096).apply(to: &request)
Seed(42).apply(to: &request)
ThinkingLevelParam(.high).apply(to: &request)
ThinkingSummariesParam(.enabled).apply(to: &request)
```

### Request-Level Parameters

These parameters are set directly on `InteractionRequest` and control request behavior:

| Parameter | Type | Description |
|-----------|------|-------------|
| `SystemInstruction(String)` | `String` | System prompt that sets the model's behavior. |
| `Store(Bool)` | `Bool` | Store the interaction for chaining. |
| `Background(Bool)` | `Bool` | Run the interaction in background mode. |
| `PreviousInteractionId(String)` | `String` | Chain to a previous interaction. |
| `ServiceTierParam(ServiceTier)` | `ServiceTier` | Service tier: `.flex`, `.standard`, `.priority`. |
| `ResponseFormatParam(ResponseFormat)` | `ResponseFormat` | Output format (text, image, audio). |
| `ResponseModalitiesParam([ResponseModality])` | `[ResponseModality]` | Output modalities: `.text`, `.image`, `.audio`, `.video`, `.document`. |
| `EnvironmentParam(EnvironmentConfig)` | `EnvironmentConfig` | Sandbox environment configuration. |
| `WebhookConfigParam(WebhookConfig)` | `WebhookConfig` | Webhook notification configuration. |

```swift
SystemInstruction("You are a helpful assistant.").apply(to: &request)
Store(true).apply(to: &request)
Background(true).apply(to: &request)
PreviousInteractionId("interaction-123").apply(to: &request)
ServiceTierParam(.flex).apply(to: &request)
ResponseFormatParam(.text(mimeType: "application/json")).apply(to: &request)
ResponseModalitiesParam([.text, .image]).apply(to: &request)
```

**Note**: Out-of-range values are silently ignored by the API. Empty strings and arrays are also silently ignored.

**Important**: Do not set `PreviousInteractionId` manually when using `ToolSession` or `Agent` — both manage chaining automatically.

### No-Op Parameters

These parameters do not modify the request — they are read by orchestration layers (`ToolSession`, `Agent`):

| Parameter | Type | Description |
|-----------|------|-------------|
| `MaxToolCalls(Int)` | `Int` | Maximum tool call iterations. Read by orchestration. |
| `RequestTimeout(TimeInterval)` | `TimeInterval` | Request timeout in seconds. Read by orchestration. |

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    MaxToolCalls(5)           // Limits tool loop iterations
    RequestTimeout(60.0)      // 60 second timeout
}
```

These values are stored in the `Agent` or `ToolSession` instance but do not appear in the wire protocol.

## Structured Output

Use `ResponseFormat.text(schema:)` to constrain the model to return valid JSON matching a specific schema. The `JSONSchemaValue` enum describes the expected structure.

### JSON Schema Example

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("name",    .string(description: "Person's full name")),
        ("age",     .integer(description: "Age in years", minimum: 0, maximum: 150)),
        ("email",   .string(description: "Email address")),
        ("active",  .boolean(description: "Account is active"))
    ],
    required: ["name", "email"]
)

var request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Extract person info: John Doe, 32, john@example.com, active"))
}

ResponseFormatParam(.text(mimeType: "application/json", schema: schema)).apply(to: &request)

let interaction = try await client.send(request)
print(interaction.outputText)
// {"name":"John Doe","age":32,"email":"john@example.com","active":true}
```

### JSONSchemaValue Cases

| Case | Description |
|------|-------------|
| `.object(properties:required:)` | Object with named properties and optional required field list |
| `.array(items:)` | Array with a schema for each element |
| `.string(description:enumValues:)` | String type, optionally constrained to enum values |
| `.integer(description:minimum:maximum:)` | Integer with optional range constraints |
| `.number(description:minimum:maximum:)` | Floating-point number with optional range constraints |
| `.boolean(description:)` | Boolean value |
| `.null` | Null value |

All schema types support an optional `description` parameter for documentation.

## Response Modalities

Request multiple output modalities (text, image, audio, video, document) using `ResponseModalitiesParam`:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    ResponseModalitiesParam([.text, .image])
}

let response = try await agent.send("Show me a diagram of the solar system.")
```

### Image Response Format

Configure image output with aspect ratio, size, and delivery options:

```swift
var request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Generate a diagram of a binary search tree."))
}

ResponseModalitiesParam([.image]).apply(to: &request)
ResponseFormatParam(.image(
    mimeType: "image/png",
    aspectRatio: "16:9",
    imageSize: "1024x576",
    delivery: .uri   // Returns a URI instead of inline base64 data
)).apply(to: &request)

let interaction = try await client.send(request)
```

### Audio Response Format

Configure audio output with codec, sample rate, bit rate, and delivery:

```swift
var request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Read this text aloud: Hello, world!"))
}

ResponseModalitiesParam([.audio]).apply(to: &request)
ResponseFormatParam(.audio(
    mimeType: .mp3,
    sampleRate: 24000,
    bitRate: 128000,
    delivery: .inline   // Audio data embedded in response as base64
)).apply(to: &request)

let interaction = try await client.send(request)
```

### ResponseDelivery Options

| Case | Behavior |
|------|----------|
| `.inline` | Binary data is base64-encoded and embedded directly in the JSON response |
| `.uri` | The API stores the content and returns a URI for separate fetch |

Use `.inline` for small responses where you want everything in one request. Use `.uri` for large files to avoid bloated JSON payloads.

## Environment Config

Use `EnvironmentParam` to configure a sandboxed execution environment for code execution:

```swift
let envConfig = EnvironmentConfig(
    sources: [
        .inline(target: "/workspace/main.py", content: "print('Hello from sandbox')")
    ],
    network: .allowlist([
        NetworkAllowlistEntry(domain: "api.example.com", transform: nil)
    ])
)

var request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Run the Python script in /workspace/main.py"))
    Tools {
        InteractionTool.codeExecution
    }
}

EnvironmentParam(envConfig).apply(to: &request)

let interaction = try await client.send(request)
```

### EnvironmentSource Cases

| Case | Description |
|------|-------------|
| `.inline(target:content:)` | Inline file content injected into the sandbox |
| `.repository(source:target:)` | File from a Git repository |
| `.gcs(source:target:)` | File from Google Cloud Storage |

### EnvironmentNetwork Options

| Case | Description |
|------|-------------|
| `.disabled` | No network access |
| `.allowlist([NetworkAllowlistEntry])` | Allow specific domains with optional URL transforms |

```swift
// Disable network entirely
EnvironmentConfig(network: .disabled)

// Allow specific domains
EnvironmentConfig(network: .allowlist([
    NetworkAllowlistEntry(domain: "pypi.org"),
    NetworkAllowlistEntry(domain: "cdn.example.com")
]))
```

## What's Next

- [Error Handling](error-handling.md) — Learn about error wrapping and recovery strategies
- [Background and Polling](background-and-polling.md) — Execute long-running interactions asynchronously

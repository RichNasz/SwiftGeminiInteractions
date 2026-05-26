---
status: alpha
---

# Gemini Macros Design Spec

## Goal

Add two Swift macros local to SwiftGeminiInteractions that eliminate ~500 lines of mechanical boilerplate across discriminated union Codable implementations (8 enums) and config parameter types (17 structs). Both macros are exported to consumers.

## Architecture

### Package structure

Add two new targets to `Package.swift`:

```
GeminiMacrosPlugin  (.macro target — SwiftSyntax implementation)
GeminiMacros        (.target — macro declarations, supporting types)
```

`SwiftGeminiInteractions` gains a dependency on `GeminiMacros`. `Core.swift` adds `@_exported import GeminiMacros`.

The package gains a new top-level dependency on `swift-syntax >= 602.0.0`.

### File layout

```
Sources/
  GeminiMacros/
    Macros.swift               — macro declarations
    ParamTarget.swift          — ParamTarget enum
  GeminiMacrosPlugin/
    DiscriminatedCodableMacro.swift — @DiscriminatedCodable implementation
    DiscriminantMacro.swift         — @Discriminant marker
    CodingNameMacro.swift           — @CodingName marker
    CustomDecodeMacro.swift         — @CustomDecode marker
    InteractionParamMacro.swift     — @InteractionParam implementation
    Plugin.swift                    — CompilerPlugin entry point
```

---

## Macro 1: `@DiscriminatedCodable`

### Purpose

Generate `Codable` conformance for Swift enums that encode/decode using a discriminator key (e.g. `"type"`) to distinguish cases. Eliminates the repeated pattern of: read type string, switch, decode each case's associated values.

### Macro declarations

```swift
@attached(member, names: named(CodingKeys), named(init(from:)), named(encode(to:)))
@attached(extension, conformances: Codable)
public macro DiscriminatedCodable(key: String = "type") = #externalMacro(...)
```

`@Discriminant`, `@CodingName`, and `@CustomDecode` are **marker macros** — they generate no code themselves. `@DiscriminatedCodable` reads their attributes from enum cases and parameters during its own expansion. This follows the same proven pattern as `@LLMToolGuide` in SwiftLLMToolMacros, which exists solely for `@LLMToolArguments` to inspect.

Swift macros cannot independently expand on enum case elements or function parameters (no macro role targets those scopes). Marker macros are the idiomatic solution.

```swift
@attached(peer)
public macro Discriminant(_ wireValue: String) = #externalMacro(...)

@attached(peer)
public macro CodingName(_ jsonKey: String) = #externalMacro(...)

@attached(peer)
public macro CustomDecode(_ methodName: String) = #externalMacro(...)
```

`@CustomDecode` takes an explicit method name string rather than relying on a naming convention. This prevents silent failures from typos and makes the contract explicit — the generated `init(from:)` calls exactly the method named in the attribute.

### Usage

```swift
@DiscriminatedCodable
public enum Annotation: Sendable {
    @Discriminant("url_citation")
    case urlCitation(
        url: String,
        title: String?,
        @CodingName("start_index") startIndex: Int,
        @CodingName("end_index") endIndex: Int
    )

    @Discriminant("file_citation")
    case fileCitation(
        @CodingName("document_uri") documentUri: String,
        @CodingName("file_name") fileName: String,
        source: String,
        @CodingName("page_number") pageNumber: Int?,
        @CodingName("start_index") startIndex: Int,
        @CodingName("end_index") endIndex: Int
    )

    @Discriminant("place_citation")
    case placeCitation(
        name: String,
        @CodingName("start_index") startIndex: Int,
        @CodingName("end_index") endIndex: Int
    )
}
```

### Generated code

The macro generates:

1. **`CodingKeys` enum** — one case per unique associated value label across all cases, plus the discriminator key (`type`). Applies `@CodingName` overrides as raw values. Generated as `public` so `@CustomDecode` extension methods can reference them. This is an implementation detail of the macro — consumers should not depend on its structure.

2. **`init(from decoder:)`** — creates a keyed container, decodes the discriminator string, switches on it. For each case:
   - Non-optional associated values: `try container.decode(Type.self, forKey: .key)`
   - Optional associated values: `try container.decodeIfPresent(Type.self, forKey: .key)`
   - `@CustomDecode("method")` cases: calls `Self.method(from: container)` instead of inline decode
   - Default branch: if an `unknown` case (no associated values) exists, assigns `.unknown`. Otherwise throws `DecodingError.dataCorruptedError`.

3. **`encode(to encoder:)`** — switches on self. For each case:
   - Encodes the discriminant string for the `type` key
   - Non-optional values: `try container.encode(value, forKey: .key)`
   - Optional values: `try container.encodeIfPresent(value, forKey: .key)`
   - `unknown` case: `break` (no encoding)

4. **`Codable` extension conformance**

### `@CustomDecode` escape hatch

For cases where the standard decode pattern doesn't work (e.g. `Step.functionCall` where `arguments` can be a JSON string or a JSON object), the developer:

1. Marks the case with `@CustomDecode("methodName")`, providing the exact name of the static decode method
2. Writes that static method in an extension:

```swift
extension Step {
    static func decodeFunctionCall(from container: KeyedDecodingContainer<CodingKeys>) throws -> Step {
        let fcArgs: String
        if let s = try? container.decode(String.self, forKey: .arguments) {
            fcArgs = s
        } else {
            let raw = try container.decode(RawJSON.self, forKey: .arguments)
            fcArgs = String(data: try JSONSerialization.data(
                withJSONObject: raw.any), encoding: .utf8) ?? "{}"
        }
        return .functionCall(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            arguments: fcArgs
        )
    }
}
```

The generated `init(from:)` emits `self = try Self.decodeFunctionCall(from: container)` for that case instead of inline decode logic. Encoding for `@CustomDecode` cases is still generated normally (encode is always mechanical).

### Enums to convert

| Enum | Location | Cases | Custom decode cases | Notes |
|------|----------|-------|---------------------|-------|
| `Annotation` | Core.swift | 3 | 0 | Straightforward |
| `Content` | Core.swift | 4 | 0 | Straightforward |
| `Step` | Core.swift | 18 + `unknown` | 2 (`functionCall`, `mcpToolCall`) | Largest; RawJSON fallback |
| `InteractionTool` | Core.swift | 7 | 1 (`function` — JSONSchemaValueWrapper) | |
| `ResponseFormat` | Core.swift | 3 | 1 (`text` — schema is encode-only, decode sets nil) | |
| `InteractionStreamEvent` | Streaming.swift | 7 + `unknown` | 1 (`stepStart` — nested step container) | Different discriminator key: `event_type` |

`InteractionInput` (2 cases, uses `singleValueContainer` not keyed) and `EnvironmentSource`/`EnvironmentNetwork` are small enough to stay manual.

---

## Macro 2: `@InteractionParam`

### Purpose

Generate `InteractionConfigParameter` conformance for config wrapper structs. Each struct wraps a single typed value and applies it to an `InteractionRequest` field.

### Macro declarations

```swift
@attached(member, names: named(init), named(apply))
@attached(extension, conformances: InteractionConfigParameter)
public macro InteractionParam(
    field: String? = nil,
    on: ParamTarget = .request,
    range: /* overloaded — see below */
    noop: Bool = false
) = #externalMacro(...)
```

Since Swift macros can't have overloaded parameters with different types, provide multiple macro declarations:

```swift
public macro InteractionParam(field: String, on: ParamTarget = .request) = #externalMacro(...)
public macro InteractionParam(field: String, on: ParamTarget = .request, range: ClosedRange<Double>) = #externalMacro(...)
public macro InteractionParam(field: String, on: ParamTarget = .request, range: ClosedRange<Int>) = #externalMacro(...)
public macro InteractionParam(noop: Bool) = #externalMacro(...)
```

### Supporting type

```swift
public enum ParamTarget {
    case request
    case generationConfig
}
```

### Usage

```swift
@InteractionParam(field: "temperature", on: .generationConfig, range: 0.0...2.0)
public struct Temperature {
    var value: Double
}

@InteractionParam(field: "store")
public struct Store {
    var value: Bool
}

@InteractionParam(noop: true)
public struct MaxToolCalls {
    var value: Int
}
```

### Generated code

The macro reads the single stored `var value: <Type>` property from the struct body, then generates:

1. **`init(_ value: <Type>)`** — public initializer

2. **`apply(to request: inout InteractionRequest)`** — the method body depends on parameters:
   - `noop: true` → empty body, and the `value` property becomes `public` (for external consumption)
   - `on: .generationConfig` → emits `request.ensureGenerationConfig()` then `request.generationConfig!.<field> = value`
   - `on: .request` (default) → emits `request.<field> = value`
   - `range:` specified → emits `guard value >= <min>, value <= <max> else { return }` before assignment
   - String/Array value types without explicit range → emits emptiness guard (`guard !value.isEmpty else { return }`)

3. **`InteractionConfigParameter` extension conformance**

### Types to convert

All 17 config parameter structs in Core.swift (lines 1144-1274):
Temperature, TopP, MaxOutputTokens, Seed, SystemInstruction, PreviousInteractionId, Store, Background, ServiceTierParam, ThinkingLevelParam, ThinkingSummariesParam, ResponseFormatParam, ResponseModalitiesParam, MaxToolCalls, EnvironmentParam, RequestTimeout, WebhookConfigParam.

---

## Additional: `ToolSession.init(client:agentTools:maxIterations:)`

A non-macro convenience addition. Add an extension on `ToolSession` inside `Agent.swift` (under `#if Agent` where both `ToolSession` and `AgentTool` are in scope):

```swift
extension ToolSession {
    public init(
        client: InteractionsClient,
        agentTools: [AgentTool],
        maxIterations: Int = 10
    ) {
        var tools: [InteractionTool] = []
        var handlers: [String: ToolHandler] = [:]
        for agentTool in agentTools {
            tools.append(agentTool.tool)
            if case .function(let name, _, _) = agentTool.tool {
                handlers[name] = agentTool.handler
            }
        }
        self.init(client: client, tools: tools, handlers: handlers, maxIterations: maxIterations)
    }
}
```

This bridges macro-defined `LLMTool` types into `ToolSession` without requiring manual extraction.

---

## Testing strategy

### Macro expansion tests

For each macro, write `assertMacroExpansion` tests that verify the generated code matches expectations. These go in `SwiftGeminiInteractionsTests` (or a new `GeminiMacrosTests` target).

Key test cases:
- `@DiscriminatedCodable` with simple enum (no optionals, no custom decode)
- `@DiscriminatedCodable` with optional associated values → `decodeIfPresent`
- `@DiscriminatedCodable` with `@CodingName` overrides
- `@DiscriminatedCodable` with `@CustomDecode` case → generates method call
- `@DiscriminatedCodable` with `unknown` fallback case
- `@DiscriminatedCodable` with custom discriminator key (`event_type`)
- `@DiscriminatedCodable` on non-enum → diagnostic error
- `@InteractionParam` basic field assignment
- `@InteractionParam` with `on: .generationConfig` → `ensureGenerationConfig()` emitted
- `@InteractionParam` with `range:` → guard emitted
- `@InteractionParam` with `noop: true` → empty body, public value
- `@InteractionParam` on struct without `var value:` → diagnostic error

### Behavioral tests

After converting the enums and param types to use macros, all existing unit tests (106+) must continue to pass, verifying encode/decode behavior is preserved.

### Integration tests

The existing 6 live API tests cover the full pipeline. `testLiveFlexServiceTier` specifically exercises `ServiceTierParam` which will be macro-generated.

## Verification

```bash
swift test    # all existing tests pass + new macro expansion tests
```

Run the integration tests with `GEMINI_API_KEY` and `RUN_INTEGRATION_TESTS=1` to confirm the macro-generated Codable implementations work against the live API.

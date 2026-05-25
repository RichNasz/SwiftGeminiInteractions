# how-encoding.md — Encoding Strategy

## Discriminated union encoding
Every enum with associated values uses a custom `encode(to:)` that writes the `"type"` key **first** in a keyed container. Decoders read the `"type"` key first and switch on its value to determine which case to construct. This pattern applies to: `Annotation`, `Content`, `Step`, `InteractionTool`, `ResponseFormat`, `EnvironmentSource`, `InteractionStreamEvent`.

## CodingKeys: snake_case via raw values
No `JSONEncoder.keyEncodingStrategy` is used. Each type that has multi-word property names defines a private `enum CodingKeys: String, CodingKey` with explicit raw string values in snake_case. Examples: `callId = "call_id"`, `isError = "is_error"`, `mimeType = "mime_type"`, `maxOutputTokens = "max_output_tokens"`, `previousInteractionId = "previous_interaction_id"`, `topK = "top_k"`, `storeNames = "file_search_store_names"`. Single-word property names match their JSON key exactly and need no raw value.

## InteractionInput encoding
`InteractionInput` uses `singleValueContainer()` (not a keyed container). `.text(String)` encodes the string directly as a bare JSON string value. `.steps([Step])` encodes the array directly as a bare JSON array. There is no `"type"` discriminator field; the shape of the JSON value (string vs. array) determines which case to decode.

## EnvironmentNetwork encoding
`EnvironmentNetwork` uses `singleValueContainer()`. `.disabled` encodes as the literal string `"disabled"`. `.allowlist([NetworkAllowlistEntry])` encodes as a JSON object `{"allowlist": [...]}` by encoding a private `AllowlistWrapper` struct into the single-value container. Decoding checks whether the value is the string `"disabled"` first; otherwise it attempts to decode the wrapper struct.

## JSONSchemaValue: Encodable-only
`JSONSchemaValue` (from the `SwiftLLMToolMacros` module) conforms to `Encodable` but not `Decodable`. When `JSONSchemaValue` appears in decodable types (e.g., `InteractionTool.function`, `ResponseFormat.text`), a private `RawJSON` helper struct decodes the raw JSON into `Any` via a recursive approach, and `jsonSchemaValueFromAny(_:)` reconstructs the `JSONSchemaValue` from that `Any` tree. This requires private decode helpers (`RawJSON`, `RawJSONKey`, `JSONSchemaValueWrapper`, `jsonSchemaValueFromAny`) local to the file. `ResponseFormat.text.schema` is always decoded as `nil` because round-tripping `JSONSchemaValue` through JSON is only needed in tests.

## EnvironmentConfig encoding
`EnvironmentConfig.encode(to:)` always writes `"type": "remote"` in addition to the optional `sources` and `network` fields. This hardcoded type key is not reflected in decoding (the `init(from:)` ignores it using `decodeIfPresent`).

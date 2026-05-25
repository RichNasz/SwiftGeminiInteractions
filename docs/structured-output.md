# Structured Output

SwiftGeminiInteractions supports three mechanisms for controlling the shape and modality of model responses: JSON schemas via `ResponseFormat`, output modalities via `ResponseModalitiesParam`, and audio delivery options via `ResponseDelivery`.

## JSON output with a schema

Use `ResponseFormat.text(schema:)` to instruct the model to return a specific JSON structure. Provide a `JSONSchemaValue` describing the expected shape.

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("city",       .string(description: "Name of the city")),
        ("country",    .string(description: "Country the city is in")),
        ("population", .integer(description: "Approximate population"))
    ],
    required: ["city", "country", "population"]
)

var request = InteractionRequest(input: .text("Give me facts about Tokyo."))
request.model = "gemini-3-flash-preview"
request.responseFormat = .text(mimeType: "application/json", schema: schema)

let interaction = try await client.send(request)
if let json = interaction.outputText {
    print(json)
    // {"city":"Tokyo","country":"Japan","population":13960000}
}
```

When a schema is provided, the model is constrained to return valid JSON that conforms to it.

## Requesting multiple output modalities

`ResponseModalitiesParam` asks the model to produce output in one or more modalities. Pass the desired modalities as an array.

```swift
// Request both text and audio output
var request = InteractionRequest(input: .text("Read the following poem aloud."))
request.model = "gemini-3-flash-preview"
request.responseModalities = [.text, .audio]
```

Or use the `InteractionConfigParameter` style with the result builder:

```swift
let agent = try Agent(client: client, model: "gemini-3-flash-preview") {
    ResponseModalitiesParam([.text, .audio])
}
```

Available modalities: `.text`, `.image`, `.audio`, `.video`, `.document`.

## Audio output format

When requesting audio output, specify the format with `ResponseFormat.audio`:

```swift
var request = InteractionRequest(input: .text("Summarise this document in spoken form."))
request.model = "gemini-3-flash-preview"
request.responseModalities = [.audio]
request.responseFormat = .audio(
    mimeType: .mp3,
    sampleRate: 24000,
    bitRate: 128000,
    delivery: .inline   // audio data embedded in the response
)
```

## Response delivery variants

`ResponseDelivery` controls how binary content (images, audio) is returned:

| Case | Behaviour |
|------|-----------|
| `.inline` | Binary data is base64-encoded and embedded directly in the JSON response |
| `.uri` | The API stores the content and returns a URI you can fetch separately |

Use `.inline` for small responses where you want everything in one round trip. Use `.uri` for large files to avoid bloated JSON payloads.

```swift
request.responseFormat = .image(
    mimeType: "image/png",
    aspectRatio: "16:9",
    imageSize: "1024x576",
    delivery: .uri   // returns a URI instead of raw bytes
)
```

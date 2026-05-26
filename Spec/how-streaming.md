---
status: alpha
---

# how-streaming.md — SSE Parsing and Stream Mechanics

## SSE event format
Each SSE event is delimited by a blank line: two consecutive newline characters (`\n\n`). Within an event, each line that carries data starts with the prefix `data: ` followed by a JSON object. Lines not starting with `data: ` are ignored. Events may span multiple lines, but in practice each event from the Interactions API is a single `data:` line followed by `\n\n`.

## parseSSE(from:)
`func parseSSE(from byteStream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<InteractionStreamEvent, Error>`. Package-internal (no `public` modifier). Accumulates incoming `Data` chunks into a mutable `buffer: Data`. After each chunk is appended, `processCompleteEvents()` is called: it scans the buffer for the `\n\n` separator using `Data.range(of:)`, extracts the event block before it, removes the processed range from the buffer, splits the block into lines, and for each line that has the `data: ` prefix strips the prefix, converts to `Data`, decodes an `InteractionStreamEvent`, and yields it to the continuation — unless the decoded event is `.unknown`, which is silently dropped. After the byte stream ends, any remaining buffered content is processed the same way (handling streams that do not end with `\n\n`). Decoding errors propagate as thrown errors and finish the stream.

## Unknown event types
When `JSONDecoder` decodes an `InteractionStreamEvent` and the `event_type` string matches no known case, the event decodes to `.unknown`. `parseSSE` checks for `.unknown` after each decode and uses `continue` to skip it without yielding. This provides forward compatibility with new event types added to the API.

## lineStream / byte bridging
The implementation does not use a named `lineStream` function. Instead, both `stream()` and `resumeStream()` create an inline `AsyncThrowingStream<Data, Error>` (referred to as `byteStream`) that iterates over `URLSession.AsyncBytes` byte by byte, accumulating a line buffer. When a newline byte (`\n`, ASCII 0x0A) is encountered, the buffered line data is yielded and the buffer is reset. Any remaining non-newline-terminated bytes at the end of the byte stream are yielded as a final chunk. This `byteStream` is then passed to `parseSSE`.

## stream() — POST with ?stream=true
`public nonisolated func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error>`. Copies the request, sets `store = true` on the copy, encodes the body, appends `?stream=true` as a URL query item to the interactions collection URL, and issues a `POST`. Uses `session.bytes(for:)` to receive the response as a byte stream. HTTP status is checked on the response: non-2xx finishes the stream with an `httpError`. The byte stream is bridged to `parseSSE` as described above.

## resumeStream(id:lastEventId:) — GET with ?stream=true&last_event_id=
`public nonisolated func resumeStream(id: String, lastEventId: String) -> AsyncThrowingStream<InteractionStreamEvent, Error>`. Issues a `GET` to the single-interaction URL (`…/v1beta/interactions/{id}`) with query items `stream=true` and `last_event_id=<lastEventId>`. No request body; no `Content-Type` header. HTTP status is checked; non-2xx silently finishes the stream without an error. Otherwise bridges through `parseSSE` the same way as `stream()`.

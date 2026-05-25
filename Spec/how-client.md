# how-client.md — HTTP Construction, Headers, and Error Wrapping

## Base URL
`https://generativelanguage.googleapis.com`. All interaction endpoints are under the path `v1beta/interactions`. The collection URL is `https://generativelanguage.googleapis.com/v1beta/interactions`. A single-interaction URL appends the id: `…/v1beta/interactions/{id}`. The cancel sub-resource appends `/cancel`: `…/v1beta/interactions/{id}/cancel`.

## Required headers on every request
Every outgoing `URLRequest` always carries:
- `x-goog-api-key: <apiKey>` — the API key provided at init time.
- `Api-Revision: <apiRevision>` — defaults to `"2026-05-20"`. Configurable at `InteractionsClient` init time as the `apiRevision` parameter.

## Content-Type header
`Content-Type: application/json` is added **only** when the request has a body (i.e. when `body != nil` in `makeRequest`). GET and DELETE requests carry no body and therefore no `Content-Type` header.

## HTTP status handling
- **2xx (200–299)** — success; the response body `Data` is returned for further decoding.
- **429** — throws `GeminiInteractionsError.rateLimitExceeded` (no body inspected).
- **Any other non-2xx** — throws `GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: <UTF-8 body string or empty string>)`.
- **Non-HTTP response** — throws `GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response")`.

## URLError wrapping
The `execute(_:)` method catches `URLError` specifically and rethrows as `GeminiInteractionsError.networkError(urlError)`. All other errors propagate unmodified (they are expected to be `GeminiInteractionsError` already from encoding/decoding helpers).

## URLSession injection for testing
`InteractionsClient` has two initializers:
- `public init(apiKey: String, apiRevision: String = "2026-05-20")` — creates `URLSession.shared` internally. This is the only public init.
- `init(apiKey: String, apiRevision: String = "2026-05-20", session: URLSession)` — internal (no `public` modifier). Accepts a caller-provided `URLSession`, used in unit tests configured with `MockURLProtocol` as a protocol handler.

## RequestTimeout parameter
`RequestTimeout` is an `InteractionConfigParameter` whose `apply(to:)` is intentionally a no-op — it does not modify the `InteractionRequest`. Instead, `InteractionsClient` reads `RequestTimeout.value` from the config params array before building the `URLRequest` and sets `urlRequest.timeoutInterval`. This means timeout configuration happens at the client/transport level, not in the JSON body.

Note: looking at the actual implementation, `RequestTimeout` has a no-op `apply` and a public `value: TimeInterval`, but the current `InteractionsClient.send/get/delete/cancel` implementations do not explicitly extract and apply it to `URLRequest.timeoutInterval` — this is reserved behavior. The stream methods also do not extract it currently. This spec describes the intended contract: `RequestTimeout` is a client-level concern, not a request-body concern.

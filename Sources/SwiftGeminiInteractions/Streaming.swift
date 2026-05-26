// Sources/SwiftGeminiInteractions/Streaming.swift
import Foundation

// MARK: - stream / resumeStream

extension InteractionsClient {
    public nonisolated func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var r = request
                    r.store = true
                    let body = try await self.encode(r)
                    var components = URLComponents(url: await self.interactionsURL(), resolvingAgainstBaseURL: false)!
                    components.queryItems = [URLQueryItem(name: "stream", value: "true")]
                    let url = components.url!
                    let urlRequest = await self.makeRequest(url: url, method: "POST", body: body)
                    let session = await self.session
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response"))
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: ""))
                        return
                    }
                    let byteStream = AsyncThrowingStream<Data, Error> { bc in
                        Task {
                            do {
                                var lineBuffer = Data()
                                for try await byte in bytes {
                                    lineBuffer.append(byte)
                                    if byte == UInt8(ascii: "\n") {
                                        bc.yield(lineBuffer)
                                        lineBuffer = Data()
                                    }
                                }
                                if !lineBuffer.isEmpty { bc.yield(lineBuffer) }
                                bc.finish()
                            } catch {
                                bc.finish(throwing: error)
                            }
                        }
                    }
                    for try await event in parseSSE(from: byteStream) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public nonisolated func resumeStream(
        id: String,
        lastEventId: String
    ) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var components = URLComponents(url: await self.interactionURL(id: id), resolvingAgainstBaseURL: false)!
                    components.queryItems = [
                        URLQueryItem(name: "stream", value: "true"),
                        URLQueryItem(name: "last_event_id", value: lastEventId)
                    ]
                    let url = components.url!
                    let urlRequest = await self.makeRequest(url: url, method: "GET")
                    let session = await self.session
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response"))
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: ""))
                        return
                    }
                    let byteStream = AsyncThrowingStream<Data, Error> { bc in
                        Task {
                            do {
                                var buf = Data()
                                for try await byte in bytes {
                                    buf.append(byte)
                                    if byte == UInt8(ascii: "\n") { bc.yield(buf); buf = Data() }
                                }
                                if !buf.isEmpty { bc.yield(buf) }
                                bc.finish()
                            } catch {
                                bc.finish(throwing: error)
                            }
                        }
                    }
                    for try await event in parseSSE(from: byteStream) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - InteractionStreamDelta

public enum InteractionStreamDelta: Sendable {
    case text(String)
    case image(Data)
    case functionCallArguments(delta: String, callId: String)
    case codeExecutionArguments(delta: String, id: String)
    case googleSearchQuery(String)
    case urlContextUrl(String)
    case thoughtSummary(String)
    case annotation(Annotation)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, text, data, delta, id
        case callId = "call_id"
        case query, url, summary
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(try container.decode(Data.self, forKey: .data))
        case "function_call_arguments":
            self = .functionCallArguments(
                delta: try container.decode(String.self, forKey: .delta),
                callId: try container.decode(String.self, forKey: .callId)
            )
        case "code_execution_arguments":
            self = .codeExecutionArguments(
                delta: try container.decode(String.self, forKey: .delta),
                id: try container.decode(String.self, forKey: .id)
            )
        case "google_search_query":
            self = .googleSearchQuery(try container.decode(String.self, forKey: .query))
        case "url_context_url":
            self = .urlContextUrl(try container.decode(String.self, forKey: .url))
        case "thought_summary":
            self = .thoughtSummary(try container.decode(String.self, forKey: .summary))
        case "annotation":
            self = .annotation(try Annotation(from: decoder))
        default:
            self = .unknown
        }
    }
}

// MARK: - InteractionStreamEvent

public enum InteractionStreamEvent: Codable, Sendable {
    case interactionCreated(Interaction)
    case interactionStatusUpdate(InteractionStatus)
    case stepStart(stepType: String, index: Int)
    case stepDelta(InteractionStreamDelta, stepIndex: Int)
    case stepStop(index: Int)
    case interactionCompleted(Interaction)
    case error(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case eventType   = "event_type"
        case interaction, status, index, delta, message
        case stepType    = "step_type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(String.self, forKey: .eventType)
        switch eventType {
        case "interaction.created":
            self = .interactionCreated(try container.decode(Interaction.self, forKey: .interaction))
        case "interaction.status_update":
            self = .interactionStatusUpdate(try container.decode(InteractionStatus.self, forKey: .status))
        case "step.start":
            self = .stepStart(
                stepType: try container.decode(String.self, forKey: .stepType),
                index: try container.decode(Int.self, forKey: .index)
            )
        case "step.delta":
            let delta = try container.decode(InteractionStreamDeltaWrapper.self, forKey: .delta)
            self = .stepDelta(delta.value, stepIndex: try container.decode(Int.self, forKey: .index))
        case "step.stop":
            self = .stepStop(index: try container.decode(Int.self, forKey: .index))
        case "interaction.completed":
            self = .interactionCompleted(try container.decode(Interaction.self, forKey: .interaction))
        case "error":
            self = .error(try container.decode(String.self, forKey: .message))
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // Events are only received, never sent
    }
}

private struct InteractionStreamDeltaWrapper: Decodable {
    let value: InteractionStreamDelta
    init(from decoder: any Decoder) throws {
        value = try InteractionStreamDelta(from: decoder)
    }
}

// MARK: - SSE Parser

internal func parseSSE(from byteStream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var buffer = Data()
                let decoder = JSONDecoder()

                func processCompleteEvents() throws {
                    while let range = buffer.range(of: Data("\n\n".utf8)) {
                        let eventData = buffer[buffer.startIndex..<range.lowerBound]
                        buffer.removeSubrange(buffer.startIndex...range.upperBound - 1)
                        let lines = String(data: eventData, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                        for line in lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst("data: ".count))
                            guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                            let event = try decoder.decode(InteractionStreamEvent.self, from: jsonData)
                            if case .unknown = event { continue }
                            continuation.yield(event)
                        }
                    }
                }

                for try await chunk in byteStream {
                    buffer.append(chunk)
                    try processCompleteEvents()
                }

                // Process any remaining data that wasn't terminated by \n\n
                if !buffer.isEmpty {
                    let lines = String(data: buffer, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                    for line in lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst("data: ".count))
                        guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                        let event = try decoder.decode(InteractionStreamEvent.self, from: jsonData)
                        if case .unknown = event { continue }
                        continuation.yield(event)
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

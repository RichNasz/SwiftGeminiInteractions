import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import GeminiMacrosPlugin

final class MacroExpansionTests: XCTestCase {

    private let macros: [String: any Macro.Type] = [
        "DiscriminatedCodable": DiscriminatedCodableMacro.self,
        "Discriminant": DiscriminantMacro.self,
        "CustomDecode": CustomDecodeMacro.self,
        "InteractionParam": InteractionParamMacro.self,
    ]

    // MARK: - @DiscriminatedCodable

    func testDiscriminatedCodableSimpleEnum() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Shape {
                case circle(radius: Double)
                case square(side: Double)
            }
            """,
            expandedSource: """
            public enum Shape {
                case circle(radius: Double)
                case square(side: Double)

                public enum CodingKeys: String, CodingKey {
                    case type
                        case radius
                        case side
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "circle":
                            self = .circle(
                                radius: try container.decode(Double.self, forKey: .radius)
                            )
                        case "square":
                            self = .square(
                                side: try container.decode(Double.self, forKey: .side)
                            )
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .circle(let radius):
                            try container.encode("circle", forKey: .type)
                            try container.encode(radius, forKey: .radius)
                        case .square(let side):
                            try container.encode("square", forKey: .type)
                            try container.encode(side, forKey: .side)
                    }
                }
            }

            extension Shape: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableWithOptionals() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Event {
                case click(x: Int, label: String?)
            }
            """,
            expandedSource: """
            public enum Event {
                case click(x: Int, label: String?)

                public enum CodingKeys: String, CodingKey {
                    case type
                        case x
                        case label
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "click":
                            self = .click(
                                x: try container.decode(Int.self, forKey: .x),
                                    label: try container.decodeIfPresent(String.self, forKey: .label)
                            )
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .click(let x, let label):
                            try container.encode("click", forKey: .type)
                            try container.encode(x, forKey: .x)
                            try container.encodeIfPresent(label, forKey: .label)
                    }
                }
            }

            extension Event: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableWithDiscriminant() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Tool {
                case codeExecution
                @Discriminant("google_search")
                case search
            }
            """,
            expandedSource: """
            public enum Tool {
                case codeExecution
                case search

                public enum CodingKeys: String, CodingKey {
                    case type
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "code_execution":
                            self = .codeExecution
                        case "google_search":
                            self = .search
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .codeExecution:
                            try container.encode("code_execution", forKey: .type)
                        case .search:
                            try container.encode("google_search", forKey: .type)
                    }
                }
            }

            extension Tool: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableWithCustomDecode() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Msg {
                @CustomDecode("decodeSpecial")
                case special(data: String)
                case plain(text: String)
            }
            """,
            expandedSource: """
            public enum Msg {
                case special(data: String)
                case plain(text: String)

                public enum CodingKeys: String, CodingKey {
                    case type
                        case data
                        case text
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "special":
                            self = try Self.decodeSpecial(from: container)
                        case "plain":
                            self = .plain(
                                text: try container.decode(String.self, forKey: .text)
                            )
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .special(let data):
                            try container.encode("special", forKey: .type)
                            try container.encode(data, forKey: .data)
                        case .plain(let text):
                            try container.encode("plain", forKey: .type)
                            try container.encode(text, forKey: .text)
                    }
                }
            }

            extension Msg: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableWithUnknownCase() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Status {
                case active
                case unknown
            }
            """,
            expandedSource: """
            public enum Status {
                case active
                case unknown

                public enum CodingKeys: String, CodingKey {
                    case type
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "active":
                            self = .active
                            default:
                                self = .unknown
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .active:
                            try container.encode("active", forKey: .type)
                        case .unknown:
                            break
                    }
                }
            }

            extension Status: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableCustomKey() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable(key: "event_type")
            public enum Event {
                case click
            }
            """,
            expandedSource: """
            public enum Event {
                case click

                public enum CodingKeys: String, CodingKey {
                    case type = "event_type"
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "click":
                            self = .click
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .click:
                            try container.encode("click", forKey: .type)
                    }
                }
            }

            extension Event: Codable {
            }
            """,
            macros: macros
        )
    }

    func testDiscriminatedCodableNonEnumDiagnostic() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public struct Nope {}
            """,
            expandedSource: """
            public struct Nope {}

            extension Nope: Codable {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@DiscriminatedCodable can only be applied to enums", line: 1, column: 1)
            ],
            macros: macros
        )
    }

    func testDiscriminatedCodableSnakeCaseConversion() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Step {
                case userInput(callId: String)
            }
            """,
            expandedSource: """
            public enum Step {
                case userInput(callId: String)

                public enum CodingKeys: String, CodingKey {
                    case type
                        case callId = "call_id"
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "user_input":
                            self = .userInput(
                                callId: try container.decode(String.self, forKey: .callId)
                            )
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .userInput(let callId):
                            try container.encode("user_input", forKey: .type)
                            try container.encode(callId, forKey: .callId)
                    }
                }
            }

            extension Step: Codable {
            }
            """,
            macros: macros
        )
    }

    // MARK: - @InteractionParam

    func testInteractionParamBasicField() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "store")
            public struct Store: InteractionConfigParameter {
                private let value: Bool
            }
            """,
            expandedSource: """
            public struct Store: InteractionConfigParameter {
                private let value: Bool

                public init(_ value: Bool) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    request.store = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamGenerationConfig() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "seed", on: .generationConfig)
            public struct Seed: InteractionConfigParameter {
                private let value: Int
            }
            """,
            expandedSource: """
            public struct Seed: InteractionConfigParameter {
                private let value: Int

                public init(_ value: Int) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    request.ensureGenerationConfig()
                        request.generationConfig!.seed = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamWithDoubleRange() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "temperature", on: .generationConfig, range: 0.0...2.0)
            public struct Temperature: InteractionConfigParameter {
                private let value: Double
            }
            """,
            expandedSource: """
            public struct Temperature: InteractionConfigParameter {
                private let value: Double

                public init(_ value: Double) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    guard value >= 0.0, value <= 2.0 else {
                        return
                    }
                        request.ensureGenerationConfig()
                        request.generationConfig!.temperature = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamNoop() {
        assertMacroExpansion(
            """
            @InteractionParam(noop: true)
            public struct MaxToolCalls: InteractionConfigParameter {
                public let value: Int
            }
            """,
            expandedSource: """
            public struct MaxToolCalls: InteractionConfigParameter {
                public let value: Int

                public init(_ value: Int) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamStringEmptinessGuard() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "systemInstruction")
            public struct SystemInstruction: InteractionConfigParameter {
                private let value: String
            }
            """,
            expandedSource: """
            public struct SystemInstruction: InteractionConfigParameter {
                private let value: String

                public init(_ value: String) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    guard !value.isEmpty else {
                        return
                    }
                        request.systemInstruction = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamArrayEmptinessGuard() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "items")
            public struct Items: InteractionConfigParameter {
                private let value: [String]
            }
            """,
            expandedSource: """
            public struct Items: InteractionConfigParameter {
                private let value: [String]

                public init(_ value: [String]) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    guard !value.isEmpty else {
                        return
                    }
                        request.items = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamNonStructDiagnostic() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "x")
            public enum Nope {}
            """,
            expandedSource: """
            public enum Nope {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@InteractionParam can only be applied to structs", line: 1, column: 1)
            ],
            macros: macros
        )
    }

    func testInteractionParamWithIntRange() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "maxOutputTokens", on: .generationConfig, range: 1...1000)
            public struct MaxOutputTokens: InteractionConfigParameter {
                private let value: Int
            }
            """,
            expandedSource: """
            public struct MaxOutputTokens: InteractionConfigParameter {
                private let value: Int

                public init(_ value: Int) {
                    self.value = value
                }

                public func apply(to request: inout InteractionRequest) {
                    guard value >= 1, value <= 1000 else {
                        return
                    }
                        request.ensureGenerationConfig()
                        request.generationConfig!.maxOutputTokens = value
                }
            }
            """,
            macros: macros
        )
    }

    func testInteractionParamMissingValueDiagnostic() {
        assertMacroExpansion(
            """
            @InteractionParam(field: "x")
            public struct Broken: InteractionConfigParameter {
                private let data: Int
            }
            """,
            expandedSource: """
            public struct Broken: InteractionConfigParameter {
                private let data: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@InteractionParam requires a stored 'var value: <Type>' property", line: 1, column: 1)
            ],
            macros: macros
        )
    }

    // MARK: - Marker macros (standalone)

    func testDiscriminantProducesNoCode() {
        assertMacroExpansion(
            """
            enum Foo {
                @Discriminant("custom_wire")
                case bar
            }
            """,
            expandedSource: """
            enum Foo {
                case bar
            }
            """,
            macros: macros
        )
    }

    func testCustomDecodeProducesNoCode() {
        assertMacroExpansion(
            """
            enum Foo {
                @CustomDecode("decodeBar")
                case bar(x: Int)
            }
            """,
            expandedSource: """
            enum Foo {
                case bar(x: Int)
            }
            """,
            macros: macros
        )
    }

    // MARK: - Combined marker macros

    func testDiscriminatedCodableWithDiscriminantAndCustomDecode() {
        assertMacroExpansion(
            """
            @DiscriminatedCodable
            public enum Action {
                case simple
                @Discriminant("special_action")
                @CustomDecode("decodeSpecial")
                case special(data: String)
            }
            """,
            expandedSource: """
            public enum Action {
                case simple
                case special(data: String)

                public enum CodingKeys: String, CodingKey {
                    case type
                        case data
                }

                public init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let typeValue = try container.decode(String.self, forKey: .type)
                    switch typeValue {
                        case "simple":
                            self = .simple
                        case "special_action":
                            self = try Self.decodeSpecial(from: container)
                            default:
                                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
                    }
                }

                public func encode(to encoder: any Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                        case .simple:
                            try container.encode("simple", forKey: .type)
                        case .special(let data):
                            try container.encode("special_action", forKey: .type)
                            try container.encode(data, forKey: .data)
                    }
                }
            }

            extension Action: Codable {
            }
            """,
            macros: macros
        )
    }
}

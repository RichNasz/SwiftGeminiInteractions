import SwiftSyntax
import SwiftSyntaxMacros

public struct DiscriminatedCodableMacro: MemberMacro, ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.addDiagnostics(
                from: MacroError("@DiscriminatedCodable can only be applied to enums"),
                node: node
            )
            return []
        }

        let discriminatorKey = extractStringArg(from: node, label: "key") ?? "type"
        let cases = extractCases(from: enumDecl)

        let codingKeys = generateCodingKeys(discriminatorKey: discriminatorKey, cases: cases)
        let initDecl = generateInitFromDecoder(discriminatorKey: discriminatorKey, cases: cases)
        let encodeDecl = generateEncodeToEncoder(cases: cases)

        return [codingKeys, initDecl, encodeDecl]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let ext: DeclSyntax = "extension \(type.trimmed): Codable {}"
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    // MARK: - Case extraction

    private struct CaseInfo {
        let swiftName: String
        let wireName: String
        let params: [ParamInfo]
        let isUnknown: Bool
        let customDecodeMethod: String?
    }

    private struct ParamInfo {
        let label: String
        let codingName: String
        let typeString: String
        let isOptional: Bool
    }

    private static func extractCases(from enumDecl: EnumDeclSyntax) -> [CaseInfo] {
        var result: [CaseInfo] = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let name = element.name.text
                let wireName = extractDiscriminant(from: caseDecl, element: element) ?? camelToSnake(name)
                let customDecode = extractCustomDecode(from: caseDecl, element: element)
                let params = extractParams(from: element)
                let isUnknown = name == "unknown" && params.isEmpty
                result.append(CaseInfo(
                    swiftName: name,
                    wireName: wireName,
                    params: params,
                    isUnknown: isUnknown,
                    customDecodeMethod: customDecode
                ))
            }
        }
        return result
    }

    private static func extractParams(from element: EnumCaseElementSyntax) -> [ParamInfo] {
        guard let paramClause = element.parameterClause else { return [] }
        return paramClause.parameters.map { param in
            let label = (param.firstName ?? param.secondName)?.text ?? "_"
            let codingName = camelToSnake(label)
            let (typeStr, isOpt) = unwrapOptional(param.type)
            return ParamInfo(label: label, codingName: codingName, typeString: typeStr, isOptional: isOpt)
        }
    }

    // MARK: - Attribute reading

    private static func extractDiscriminant(from caseDecl: EnumCaseDeclSyntax, element: EnumCaseElementSyntax) -> String? {
        for attr in allAttributes(caseDecl: caseDecl, element: element) {
            if attrName(attr) == "Discriminant" {
                return extractStringArg(from: attr)
            }
        }
        return nil
    }

    private static func extractCustomDecode(from caseDecl: EnumCaseDeclSyntax, element: EnumCaseElementSyntax) -> String? {
        for attr in allAttributes(caseDecl: caseDecl, element: element) {
            if attrName(attr) == "CustomDecode" {
                return extractStringArg(from: attr)
            }
        }
        return nil
    }

    private static func allAttributes(caseDecl: EnumCaseDeclSyntax, element: EnumCaseElementSyntax) -> [AttributeSyntax] {
        var attrs: [AttributeSyntax] = []
        for attrItem in caseDecl.attributes {
            if let attr = attrItem.as(AttributeSyntax.self) { attrs.append(attr) }
        }
        return attrs
    }

    private static func attrName(_ attr: AttributeSyntax) -> String? {
        attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text
    }

    private static func extractStringArg(from attr: AttributeSyntax, label: String? = nil) -> String? {
        guard let args = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
        for arg in args {
            if let label = label {
                guard arg.label?.text == label else { continue }
            }
            if let str = arg.expression.as(StringLiteralExprSyntax.self)?
                .segments.first?.as(StringSegmentSyntax.self)?.content.text {
                return str
            }
        }
        return nil
    }

    // MARK: - Type helpers

    private static func unwrapOptional(_ type: TypeSyntax) -> (String, Bool) {
        if let opt = type.as(OptionalTypeSyntax.self) {
            return (opt.wrappedType.trimmedDescription, true)
        }
        if let ident = type.as(IdentifierTypeSyntax.self), ident.name.text == "Optional",
           let generic = ident.genericArgumentClause?.arguments.first {
            return (generic.argument.trimmedDescription, true)
        }
        return (type.trimmedDescription, false)
    }

    // MARK: - Code generation

    private static func generateCodingKeys(discriminatorKey: String, cases: [CaseInfo]) -> DeclSyntax {
        var seen = Set<String>()
        var entries: [String] = []

        entries.append(codingKeyEntry("type", jsonName: discriminatorKey))
        seen.insert("type")

        for c in cases {
            for p in c.params {
                guard !seen.contains(p.label) else { continue }
                seen.insert(p.label)
                entries.append(codingKeyEntry(p.label, jsonName: p.codingName))
            }
        }

        let body = entries.joined(separator: "\n        ")
        return """
        public enum CodingKeys: String, CodingKey {
            \(raw: body)
        }
        """
    }

    private static func codingKeyEntry(_ swiftName: String, jsonName: String) -> String {
        if swiftName == jsonName {
            return "case \(swiftName)"
        } else {
            return "case \(swiftName) = \"\(jsonName)\""
        }
    }

    private static func generateInitFromDecoder(discriminatorKey: String, cases: [CaseInfo]) -> DeclSyntax {
        var switchCases: [String] = []
        let hasUnknown = cases.contains { $0.isUnknown }

        for c in cases where !c.isUnknown {
            if let method = c.customDecodeMethod {
                switchCases.append("""
                        case "\(c.wireName)":
                            self = try Self.\(method)(from: container)
                """)
            } else if c.params.isEmpty {
                switchCases.append("""
                        case "\(c.wireName)":
                            self = .\(c.swiftName)
                """)
            } else {
                let decodes = c.params.map { p in
                    let decodeCall = p.isOptional
                        ? "try container.decodeIfPresent(\(p.typeString).self, forKey: .\(p.label))"
                        : "try container.decode(\(p.typeString).self, forKey: .\(p.label))"
                    return "\(p.label): \(decodeCall)"
                }.joined(separator: ",\n                    ")
                switchCases.append("""
                        case "\(c.wireName)":
                            self = .\(c.swiftName)(
                                \(decodes)
                            )
                """)
            }
        }

        let defaultCase: String
        if hasUnknown {
            defaultCase = """
                        default:
                            self = .unknown
            """
        } else {
            defaultCase = """
                        default:
                            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \\(typeValue)")
            """
        }

        let body = switchCases.joined(separator: "\n") + "\n" + defaultCase

        return """
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let typeValue = try container.decode(String.self, forKey: .type)
            switch typeValue {
        \(raw: body)
            }
        }
        """
    }

    private static func generateEncodeToEncoder(cases: [CaseInfo]) -> DeclSyntax {
        var switchCases: [String] = []

        for c in cases {
            if c.isUnknown {
                switchCases.append("""
                        case .unknown:
                            break
                """)
                continue
            }
            if c.params.isEmpty {
                switchCases.append("""
                        case .\(c.swiftName):
                            try container.encode("\(c.wireName)", forKey: .type)
                """)
            } else {
                let bindings = c.params.map { "let \($0.label)" }.joined(separator: ", ")
                var encodeLines = [
                    "try container.encode(\"\(c.wireName)\", forKey: .type)"
                ]
                for p in c.params {
                    if p.isOptional {
                        encodeLines.append("try container.encodeIfPresent(\(p.label), forKey: .\(p.label))")
                    } else {
                        encodeLines.append("try container.encode(\(p.label), forKey: .\(p.label))")
                    }
                }
                let encodeLinesStr = encodeLines.map { "            \($0)" }.joined(separator: "\n")
                switchCases.append("""
                        case .\(c.swiftName)(\(bindings)):
                \(encodeLinesStr)
                """)
            }
        }

        let body = switchCases.joined(separator: "\n")

        return """
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
        \(raw: body)
            }
        }
        """
    }

    // MARK: - Utilities

    private static func camelToSnake(_ input: String) -> String {
        var result = ""
        for (i, char) in input.enumerated() {
            if char.isUppercase && i > 0 {
                result += "_"
            }
            result += String(char).lowercased()
        }
        return result
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

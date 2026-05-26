import SwiftSyntax
import SwiftSyntaxMacros

public struct InteractionParamMacro: MemberMacro, ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.addDiagnostics(
                from: MacroError("@InteractionParam can only be applied to structs"),
                node: node
            )
            return []
        }

        guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
            return []
        }

        let isNoop = extractBool(from: args, label: "noop") ?? false

        guard let valueProperty = findValueProperty(in: declaration) else {
            context.addDiagnostics(
                from: MacroError("@InteractionParam requires a stored 'var value: <Type>' property"),
                node: node
            )
            return []
        }

        let typeString = valueProperty.type.trimmedDescription
        let visibility = isNoop ? "public" : "private"

        var result: [DeclSyntax] = []

        let visibilityModifier: DeclSyntax = """
        \(raw: visibility) var _macroValueAccess: Never { fatalError() }
        """
        _ = visibilityModifier

        let initDecl: DeclSyntax = """
        public init(_ value: \(raw: typeString)) { self.value = value }
        """
        result.append(initDecl)

        if isNoop {
            let applyDecl: DeclSyntax = """
            public func apply(to request: inout InteractionRequest) {}
            """
            result.append(applyDecl)
        } else {
            let field = extractString(from: args, label: "field")!
            let isGenConfig = extractParamTarget(from: args) == .generationConfig
            let rangeGuard = extractRangeGuard(from: args)
            let isStringOrArray = typeString == "String" || typeString.hasPrefix("[")

            var bodyLines: [String] = []

            if let rangeGuard = rangeGuard {
                bodyLines.append(rangeGuard)
            } else if isStringOrArray {
                bodyLines.append("guard !value.isEmpty else { return }")
            }

            if isGenConfig {
                bodyLines.append("request.ensureGenerationConfig()")
                bodyLines.append("request.generationConfig!.\(field) = value")
            } else {
                bodyLines.append("request.\(field) = value")
            }

            let body = bodyLines.joined(separator: "\n        ")
            let applyDecl: DeclSyntax = """
            public func apply(to request: inout InteractionRequest) {
                \(raw: body)
            }
            """
            result.append(applyDecl)
        }

        return result
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        return []
    }

    // MARK: - Helpers

    private enum Target {
        case request, generationConfig
    }

    private static func findValueProperty(in decl: some DeclGroupSyntax) -> (name: String, type: TypeSyntax)? {
        for member in decl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil else { continue }
                if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                   pattern.identifier.text == "value",
                   let typeAnnotation = binding.typeAnnotation {
                    return (name: "value", type: typeAnnotation.type)
                }
            }
        }
        return nil
    }

    private static func extractString(from args: LabeledExprListSyntax, label: String) -> String? {
        for arg in args {
            guard arg.label?.text == label else { continue }
            if let str = arg.expression.as(StringLiteralExprSyntax.self)?
                .segments.first?.as(StringSegmentSyntax.self)?.content.text {
                return str
            }
        }
        return nil
    }

    private static func extractBool(from args: LabeledExprListSyntax, label: String) -> Bool? {
        for arg in args {
            guard arg.label?.text == label else { continue }
            if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                return boolExpr.literal.text == "true"
            }
        }
        return nil
    }

    private static func extractParamTarget(from args: LabeledExprListSyntax) -> Target {
        for arg in args {
            guard arg.label?.text == "on" else { continue }
            if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                if memberAccess.declName.baseName.text == "generationConfig" {
                    return .generationConfig
                }
            }
        }
        return .request
    }

    private static func extractRangeGuard(from args: LabeledExprListSyntax) -> String? {
        for arg in args {
            guard arg.label?.text == "range" else { continue }
            if let seqExpr = arg.expression.as(SequenceExprSyntax.self) {
                let elements = Array(seqExpr.elements)
                if elements.count == 3 {
                    let lo = elements[0].trimmedDescription
                    let hi = elements[2].trimmedDescription
                    return "guard value >= \(lo), value <= \(hi) else { return }"
                }
            }
            if let infixExpr = arg.expression.as(InfixOperatorExprSyntax.self) {
                let lo = infixExpr.leftOperand.trimmedDescription
                let hi = infixExpr.rightOperand.trimmedDescription
                return "guard value >= \(lo), value <= \(hi) else { return }"
            }
        }
        return nil
    }
}

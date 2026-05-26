import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct GeminiMacrosPluginMain: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DiscriminatedCodableMacro.self,
        DiscriminantMacro.self,
        CustomDecodeMacro.self,
        InteractionParamMacro.self,
    ]
}

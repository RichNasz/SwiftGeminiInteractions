@attached(member, names: named(CodingKeys), named(init(from:)), named(encode(to:)))
@attached(extension, conformances: Codable)
public macro DiscriminatedCodable(key: String = "type") = #externalMacro(
    module: "GeminiMacrosPlugin", type: "DiscriminatedCodableMacro"
)

@attached(peer)
public macro Discriminant(_ wireValue: String) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "DiscriminantMacro"
)

@attached(peer)
public macro CustomDecode(_ methodName: String) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "CustomDecodeMacro"
)

@attached(member, names: named(init(_:)), named(apply(to:)))
@attached(extension)
public macro InteractionParam(field: String, on: ParamTarget = .request) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "InteractionParamMacro"
)

@attached(member, names: named(init(_:)), named(apply(to:)))
@attached(extension)
public macro InteractionParam(field: String, on: ParamTarget = .request, range: ClosedRange<Double>) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "InteractionParamMacro"
)

@attached(member, names: named(init(_:)), named(apply(to:)))
@attached(extension)
public macro InteractionParam(field: String, on: ParamTarget = .request, range: ClosedRange<Int>) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "InteractionParamMacro"
)

@attached(member, names: named(init(_:)), named(apply(to:)))
@attached(extension)
public macro InteractionParam(noop: Bool) = #externalMacro(
    module: "GeminiMacrosPlugin", type: "InteractionParamMacro"
)

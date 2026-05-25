// Tests/SwiftGeminiInteractionsTests/ConfigTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class ConfigTests: XCTestCase {

    func testTemperatureAppliesAndValidates() throws {
        var request = InteractionRequest(input: .text("hi"))
        Temperature(0.7).apply(to: &request)
        let temp = try XCTUnwrap(request.generationConfig?.temperature)
        XCTAssertEqual(temp, 0.7, accuracy: 0.001)
        // Out of range — should clamp or be caught at init
        let invalid = Temperature(-0.1)
        var r2 = InteractionRequest(input: .text("hi"))
        invalid.apply(to: &r2)
        // Temperature below 0 should not apply (or clamps to 0)
        XCTAssertNil(r2.generationConfig?.temperature)
    }

    func testMaxOutputTokensApplies() {
        var request = InteractionRequest(input: .text("hi"))
        MaxOutputTokens(512).apply(to: &request)
        XCTAssertEqual(request.generationConfig?.maxOutputTokens, 512)
    }

    func testSystemInstructionApplies() {
        var request = InteractionRequest(input: .text("hi"))
        SystemInstruction("Be helpful.").apply(to: &request)
        XCTAssertEqual(request.systemInstruction, "Be helpful.")
    }

    func testEmptySystemInstructionDoesNotApply() {
        var request = InteractionRequest(input: .text("hi"))
        SystemInstruction("").apply(to: &request)
        XCTAssertNil(request.systemInstruction)
    }

    func testStoreApplies() {
        var request = InteractionRequest(input: .text("hi"))
        Store(true).apply(to: &request)
        XCTAssertEqual(request.store, true)
    }

    func testPreviousInteractionIdApplies() {
        var request = InteractionRequest(input: .text("hi"))
        PreviousInteractionId("v1_abc").apply(to: &request)
        XCTAssertEqual(request.previousInteractionId, "v1_abc")
    }

    func testEmptyPreviousInteractionIdDoesNotApply() {
        var request = InteractionRequest(input: .text("hi"))
        PreviousInteractionId("").apply(to: &request)
        XCTAssertNil(request.previousInteractionId)
    }

    func testMultipleParamsApplyInOrder() throws {
        var request = InteractionRequest(input: .text("hi"))
        let params: [any InteractionConfigParameter] = [
            Temperature(0.5),
            MaxOutputTokens(1024),
            Store(true)
        ]
        for p in params { p.apply(to: &request) }
        let temp = try XCTUnwrap(request.generationConfig?.temperature)
        XCTAssertEqual(temp, 0.5, accuracy: 0.001)
        XCTAssertEqual(request.generationConfig?.maxOutputTokens, 1024)
        XCTAssertEqual(request.store, true)
    }
}

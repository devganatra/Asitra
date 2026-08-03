import XCTest
@testable import SakhyaContracts

final class IntegrationContractsTests: XCTestCase {
    func testInterpretationRoundTrip() throws {
        let value = AIInterpretationResult(title: "Walk", category: "Health", note: nil, confidence: 0.9)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AIInterpretationResult.self, from: data).title, "Walk")
    }

    func testSharedAssistantContractDecodesServerPayloads() throws {
        let config = #"{"version":1,"profile":"Everyday","label":"Terra","model":"gpt-5.6-terra","provider":"openai"}"#
        let response = #"{"answer":"A grounded answer","model":"gpt-5.6-terra","label":"Terra","profile":"Everyday","contractVersion":1}"#

        let contract = try JSONDecoder().decode(SakhyaAIContract.self, from: Data(config.utf8))
        let answer = try JSONDecoder().decode(SakhyaAssistantResponse.self, from: Data(response.utf8))

        XCTAssertEqual(contract.model, answer.model)
        XCTAssertEqual(contract.label, answer.label)
        XCTAssertEqual(contract.profile, answer.profile)
        XCTAssertEqual(contract.version, answer.contractVersion)
    }
}

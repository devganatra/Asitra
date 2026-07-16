import XCTest
@testable import SakhyaContracts

final class IntegrationContractsTests: XCTestCase {
    func testInterpretationRoundTrip() throws {
        let value = AIInterpretationResult(title: "Walk", category: "Health", note: nil, confidence: 0.9)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(AIInterpretationResult.self, from: data).title, "Walk")
    }
}

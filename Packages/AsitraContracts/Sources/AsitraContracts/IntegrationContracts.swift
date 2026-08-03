import Foundation

public struct AIInterpretationRequest: Codable, Sendable {
    public var text: String
    public var imageData: Data?
    public var localeIdentifier: String

    public init(text: String, imageData: Data? = nil, localeIdentifier: String) {
        self.text = text
        self.imageData = imageData
        self.localeIdentifier = localeIdentifier
    }
}

public struct AIInterpretationResult: Codable, Sendable {
    public var title: String
    public var category: String
    public var note: String?
    public var confidence: Double

    public init(title: String, category: String, note: String?, confidence: Double) {
        self.title = title
        self.category = category
        self.note = note
        self.confidence = confidence
    }
}

public protocol AIProvider: Sendable {
    func interpret(_ request: AIInterpretationRequest) async throws -> AIInterpretationResult
}

public struct AsitraAIContract: Codable, Sendable, Equatable {
    public let version: Int
    public let profile: String
    public let label: String
    public let model: String

    public init(version: Int, profile: String, label: String, model: String) {
        self.version = version
        self.profile = profile
        self.label = label
        self.model = model
    }
}

public struct AsitraAssistantResponse: Codable, Sendable, Equatable {
    public let answer: String
    public let model: String
    public let label: String
    public let profile: String
    public let contractVersion: Int

    public init(answer: String, model: String, label: String, profile: String, contractVersion: Int) {
        self.answer = answer
        self.model = model
        self.label = label
        self.profile = profile
        self.contractVersion = contractVersion
    }
}

public struct WearableSample: Codable, Sendable, Hashable {
    public var externalIdentifier: String
    public var timestamp: Date
    public var type: String
    public var value: Double
    public var unit: String
    public var source: String

    public init(externalIdentifier: String, timestamp: Date, type: String, value: Double, unit: String, source: String) {
        self.externalIdentifier = externalIdentifier
        self.timestamp = timestamp
        self.type = type
        self.value = value
        self.unit = unit
        self.source = source
    }
}

public protocol WearableProvider: Sendable {
    var name: String { get }
    func samples(since date: Date?) async throws -> [WearableSample]
}

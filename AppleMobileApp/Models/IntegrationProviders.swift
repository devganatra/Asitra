import CloudKit
import Foundation
import SakhyaContracts

@MainActor
protocol SharedListRepository {
    func prepareShare(for list: SakhyaList) async throws -> String
}

@MainActor
struct CloudKitSharedListRepository: SharedListRepository {
    private let containerIdentifier = "iCloud.com.devganatra.sakhya"

    func prepareShare(for list: SakhyaList) async throws -> String {
        // Construct CloudKit only when sharing is requested. Eager construction can
        // trap at app startup when the current build is unsigned or lacks iCloud.
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: "list-\(list.id.uuidString)")
        let root: CKRecord
        do {
            root = try await database.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            root = CKRecord(recordType: "SakhyaSharedList", recordID: rootID)
        }
        root["listID"] = list.id.uuidString as CKRecordValue
        root["name"] = list.name as CKRecordValue
        root["kind"] = list.kind.rawValue as CKRecordValue
        root["payload"] = try JSONEncoder().encode(list) as CKRecordValue
        root["updatedAt"] = Date.now as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = list.name as CKRecordValue
        share.publicPermission = .none

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [root, share])
            operation.savePolicy = .changedKeys
            operation.isAtomic = true
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: share.recordID.recordName)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}

struct OnDeviceCaptureAIProvider: AIProvider {
    func interpret(_ request: AIInterpretationRequest) async throws -> AIInterpretationResult {
        let suggestion = SmartCapture(text: request.text)
        return AIInterpretationResult(
            title: request.text.trimmingCharacters(in: .whitespacesAndNewlines),
            category: suggestion.category.rawValue,
            note: nil,
            confidence: 0.75
        )
    }
}

struct RemoteAIProvider: AIProvider {
    let endpoint: URL
    let authorization: @Sendable () async throws -> String

    func interpret(_ request: AIInterpretationRequest) async throws -> AIInterpretationResult {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(try await authorization())", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw IntegrationProviderError.invalidResponse
        }
        return try JSONDecoder().decode(AIInterpretationResult.self, from: data)
    }
}

struct HTTPWearableProvider: WearableProvider {
    let name: String
    let samplesEndpoint: URL
    let authorization: @Sendable () async throws -> String

    func samples(since date: Date?) async throws -> [WearableSample] {
        var components = URLComponents(url: samplesEndpoint, resolvingAgainstBaseURL: false)
        if let date {
            var queryItems = components?.queryItems ?? []
            queryItems.append(
                URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: date))
            )
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw IntegrationProviderError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await authorization())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw IntegrationProviderError.invalidResponse
        }
        return try JSONDecoder().decode([WearableSample].self, from: data)
    }
}

enum IntegrationProviderError: LocalizedError {
    case invalidEndpoint
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The integration endpoint is invalid."
        case .invalidResponse: "The integration returned an invalid response."
        }
    }
}

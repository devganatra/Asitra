import CloudKit
import Foundation
import AsitraContracts

#if canImport(FinanceKit) && os(iOS)
import FinanceKit
#endif

struct FinancialAccountReference: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var displayName: String
    var institutionName: String
    var currencyCode: String
    var isCreditCard: Bool
}

struct FinancialTransactionImport: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var account: FinancialAccountReference
    var merchantName: String
    var transactionDescription: String
    var amount: Double
    var currencyCode: String
    var date: Date
    var merchantCategoryCode: Int?
    var status: String
}

struct FinancialImportBatch: Sendable {
    var accounts: [FinancialAccountReference]
    var transactions: [FinancialTransactionImport]
}

protocol FinancialDataProvider: Sendable {
    var isAvailable: Bool { get }
    func requestAndFetchTransactions(since date: Date) async throws -> FinancialImportBatch
}

struct UnavailableFinancialDataProvider: FinancialDataProvider {
    let isAvailable = false

    func requestAndFetchTransactions(since date: Date) async throws -> FinancialImportBatch {
        throw FinancialDataError.unavailable
    }
}

#if canImport(FinanceKit) && os(iOS)
@available(iOS 17.4, *)
struct AppleFinanceKitProvider: FinancialDataProvider {
    var isAvailable: Bool {
        FinanceStore.isDataAvailable(.financialData)
    }

    func requestAndFetchTransactions(since date: Date) async throws -> FinancialImportBatch {
        guard isAvailable else { throw FinancialDataError.unavailable }

        let store = FinanceStore.shared
        let authorization = try await store.requestAuthorization()
        guard authorization == .authorized else { throw FinancialDataError.authorizationDenied }

        let financeAccounts = try await store.accounts(query: AccountQuery())
        let accounts = financeAccounts.map { account in
            FinancialAccountReference(
                id: account.id,
                displayName: account.displayName,
                institutionName: account.institutionName,
                currencyCode: account.currencyCode,
                isCreditCard: account.liabilityAccount != nil
            )
        }
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let transactions = try await store.transactions(query: TransactionQuery(limit: 1_000))
        let spending = transactions.compactMap { transaction -> FinancialTransactionImport? in
            guard transaction.creditDebitIndicator == .debit,
                  transaction.transactionDate >= date,
                  let account = accountsByID[transaction.accountID] else { return nil }
            let merchant = transaction.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = transaction.transactionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return FinancialTransactionImport(
                id: transaction.id,
                account: account,
                merchantName: merchant?.isEmpty == false ? merchant! : description,
                transactionDescription: description,
                amount: abs(NSDecimalNumber(decimal: transaction.transactionAmount.amount).doubleValue),
                currencyCode: transaction.transactionAmount.currencyCode,
                date: transaction.transactionDate,
                merchantCategoryCode: transaction.merchantCategoryCode.map { Int($0.rawValue) },
                status: String(describing: transaction.status)
            )
        }
        return FinancialImportBatch(accounts: accounts, transactions: spending)
    }
}
#endif

enum FinancialDataProviderFactory {
    static var live: any FinancialDataProvider {
        #if canImport(FinanceKit) && os(iOS)
        if #available(iOS 17.4, *) {
            return AppleFinanceKitProvider()
        }
        #endif
        return UnavailableFinancialDataProvider()
    }
}

enum FinancialDataError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Wallet financial data is unavailable on this device or in this region."
        case .authorizationDenied:
            "Access was not granted. You can choose the accounts and date range to share in Apple Wallet."
        }
    }
}

@MainActor
protocol SharedListRepository {
    func prepareShare(for list: AsitraList) async throws -> String
}

@MainActor
struct CloudKitSharedListRepository: SharedListRepository {
    private let containerIdentifier = "iCloud.com.devganatra.sakhya"

    func prepareShare(for list: AsitraList) async throws -> String {
        // Construct CloudKit only when sharing is requested. Eager construction can
        // trap at app startup when the current build is unsigned or lacks iCloud.
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: "list-\(list.id.uuidString)")
        let root: CKRecord
        do {
            root = try await database.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            // Retain the original record type so existing shared lists continue to resolve.
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
        guard endpoint.scheme?.lowercased() == "https",
              endpoint.user == nil,
              endpoint.password == nil else {
            throw IntegrationProviderError.insecureTransport
        }
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
        guard samplesEndpoint.scheme?.lowercased() == "https",
              samplesEndpoint.user == nil,
              samplesEndpoint.password == nil else {
            throw IntegrationProviderError.insecureTransport
        }
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
    case insecureTransport

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The integration endpoint is invalid."
        case .invalidResponse: "The integration returned an invalid response."
        case .insecureTransport: "The integration must use HTTPS without credentials embedded in its URL."
        }
    }
}

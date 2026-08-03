import AuthenticationServices
import Foundation
import Observation
import Security
import AsitraContracts

@MainActor
@Observable
final class AsitraAIAccount {
    static let shared = AsitraAIAccount()

    private(set) var isConnected: Bool
    private(set) var isConnecting = false
    private(set) var errorMessage: String?
    private(set) var modelLabel = "Shared model"
    private(set) var modelIdentifier: String?
    private(set) var modelProfile = "Everyday"
    private(set) var modelContractVersion: Int?

    private let sessionStore = SecureSessionStore()
    private let serviceURL = URL(string: "https://sakhya-everyday.deepanddev.chatgpt.site")!

    private init() {
        isConnected = sessionStore.read()?.isValid == true
    }

    var sessionToken: String? {
        guard let session = sessionStore.read(), session.isValid else { return nil }
        return session.sessionToken
    }

    func refreshModelContract() async {
        do {
            let url = serviceURL.appending(path: "api/assistant/config")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            let contract = try JSONDecoder().decode(AsitraAIContract.self, from: data)
            modelLabel = contract.label
            modelIdentifier = contract.model
            modelProfile = contract.profile
            modelContractVersion = contract.version
        } catch {
            // Offline insights remain available; retry when the screen appears again.
        }
    }

    func apply(_ response: AsitraAssistantResponse) {
        modelLabel = response.label
        modelIdentifier = response.model
        modelProfile = response.profile
        modelContractVersion = response.contractVersion
    }

    func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                throw AsitraAIAccountError.missingIdentityToken
            }
            var request = URLRequest(url: serviceURL.appending(path: "api/native/session"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(SessionRequest(identityToken: identityToken))
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw AsitraAIAccountError.signInRejected
            }
            let session = try JSONDecoder().decode(SessionResponse.self, from: data)
            try sessionStore.save(session)
            isConnected = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        if let token = sessionStore.read()?.sessionToken {
            var request = URLRequest(url: serviceURL.appending(path: "api/native/session"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            _ = try? await URLSession.shared.data(for: request)
        }
        sessionStore.delete()
        isConnected = false
        errorMessage = nil
    }
}

private struct SessionRequest: Encodable {
    let identityToken: String
}

private struct SessionResponse: Codable {
    let sessionToken: String
    let expiresAt: String

    var isValid: Bool {
        guard let date = ISO8601DateFormatter().date(from: expiresAt) else { return false }
        return date > .now
    }
}

private struct SecureSessionStore {
    private let service = "com.devganatra.sakhya.ai"
    private let account = "native-session"

    func read() -> SessionResponse? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SessionResponse.self, from: data)
    }

    func save(_ session: SessionResponse) throws {
        delete()
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw AsitraAIAccountError.secureStorageFailed
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum AsitraAIAccountError: LocalizedError {
    case missingIdentityToken
    case signInRejected
    case secureStorageFailed

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            "Apple did not provide a usable identity token."
        case .signInRejected:
            "Asitra could not verify this Apple sign-in."
        case .secureStorageFailed:
            "The secure AI session could not be saved in Keychain."
        }
    }
}

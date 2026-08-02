import AppKit
import CryptoKit
import Foundation
import Network
import Security

enum OpenAICodexLoginMethod: String, Codable, CaseIterable, Sendable {
    case browser
    case device
}

enum CodexLoginState: Equatable, Sendable {
    case disconnected
    case starting
    case waitingForBrowser
    case waitingForDeviceApproval
    case exchangingCode
    case connected
    case refreshing
    case failed(String)
    case cancelled
}

struct OpenAIDeviceAuthorization: Equatable, Sendable {
    let verificationURL: String
    let userCode: String
    let deviceAuthID: String
    let interval: TimeInterval
}

struct CodexOAuthCallback: Equatable, Sendable {
    let path: String
    let code: String?
    let state: String?
    let error: String?
    let errorDescription: String?
}

enum OpenAICodexOAuthError: Error, LocalizedError, Equatable, Sendable {
    case callbackServerUnavailable
    case callbackTimeout
    case callbackMalformed
    case stateMismatch
    case accessDenied(String)
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case deviceAuthorizationFailed(String)
    case deviceAuthorizationTimeout
    case missingAccountID
    case missingCredential
    case cancelled
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .callbackServerUnavailable: return "Could not start the local OAuth callback server."
        case .callbackTimeout: return "OAuth login timed out before the browser completed authorization."
        case .callbackMalformed: return "The OAuth callback was malformed."
        case .stateMismatch: return "The OAuth callback state did not match the login attempt."
        case let .accessDenied(message): return message
        case let .tokenExchangeFailed(message): return "Token exchange failed: \(message)"
        case let .refreshFailed(message): return "Token refresh failed: \(message)"
        case let .deviceAuthorizationFailed(message): return "Device authorization failed: \(message)"
        case .deviceAuthorizationTimeout: return "Device authorization timed out."
        case .missingAccountID: return "OpenAI did not return a ChatGPT account identifier."
        case .missingCredential: return "No usable ChatGPT subscription credential is stored."
        case .cancelled: return "ChatGPT login was cancelled."
        case let .unsupported(message): return message
        }
    }
}

struct CodexPKCE: Equatable, Sendable {
    let verifier: String
    let challenge: String

    static func generate() -> CodexPKCE {
        let verifier = CodexOAuthSecurity.randomString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return CodexPKCE(verifier: verifier, challenge: CodexOAuthSecurity.base64URL(Data(digest)))
    }
}

enum CodexOAuthSecurity {
    static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: max(length, 1))
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

enum OpenAIJWT {
    static func claims(from token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".")
        guard pieces.count == 3 else { return nil }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func accountID(from token: String) -> String? {
        guard let claims = claims(from: token) else { return nil }
        if let value = claims["chatgpt_account_id"] as? String, value.isEmpty == false { return value }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any], let value = auth["chatgpt_account_id"] as? String, value.isEmpty == false { return value }
        if let organizations = claims["organizations"] as? [[String: Any]], let value = organizations.first?["id"] as? String, value.isEmpty == false { return value }
        return nil
    }

    static func accountID(idToken: String?, accessToken: String?) -> String? {
        if let idToken, let value = accountID(from: idToken) { return value }
        if let accessToken, let value = accountID(from: accessToken) { return value }
        return nil
    }
}

struct CodexOAuthTokenResponse: Decodable, Sendable {
    let idToken: String?
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        if let number = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresIn) {
            expiresIn = number
        } else if let string = try container.decodeIfPresent(String.self, forKey: .expiresIn) {
            expiresIn = TimeInterval(string)
        } else { expiresIn = nil }
    }
}

private struct CodexDeviceCodeResponse: Decodable, Sendable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        if let value = try container.decodeIfPresent(String.self, forKey: .userCode) {
            userCode = value
        } else {
            userCode = try container.decode(String.self, forKey: .userCode)
        }
        if let number = try container.decodeIfPresent(TimeInterval.self, forKey: .interval) {
            interval = max(number, 1)
        } else if let string = try container.decodeIfPresent(String.self, forKey: .interval) {
            interval = max(TimeInterval(string) ?? 5, 1)
        } else { interval = 5 }
    }
}

private struct CodexDeviceTokenResponse: Decodable, Sendable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private final class CodexOAuthCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hridya.foundry.codex-oauth")
    private let lock = NSLock()
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<CodexOAuthCallback, Error>?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var isStopped = false
    private(set) var port: UInt16 = 0

    func start() async throws -> UInt16 {
        for port in [UInt16(1455), UInt16(1457)] {
            do {
                try await start(on: port)
                return port
            } catch {
                stop()
            }
        }
        throw OpenAICodexOAuthError.callbackServerUnavailable
    }

    private func start(on port: UInt16) async throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw OpenAICodexOAuthError.callbackServerUnavailable }
        let listener = try NWListener(using: .tcp, on: endpointPort)
        setListener(listener, port: port)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumeStart(with: nil)
                case let .failed(error):
                    self.resumeStart(with: error)
                case .cancelled:
                    self.resumeStart(with: OpenAICodexOAuthError.callbackServerUnavailable)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection: connection, data: Data())
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> CodexOAuthCallback {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CodexOAuthCallback, Error>) in
            lock.lock()
            if isStopped {
                lock.unlock()
                continuation.resume(throwing: OpenAICodexOAuthError.cancelled)
            } else {
                callbackContinuation = continuation
                lock.unlock()
            }
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        let listener = self.listener
        self.listener = nil
        let callback = callbackContinuation
        callbackContinuation = nil
        let start = startContinuation
        startContinuation = nil
        lock.unlock()
        listener?.cancel()
        callback?.resume(throwing: OpenAICodexOAuthError.cancelled)
        start?.resume(throwing: OpenAICodexOAuthError.callbackServerUnavailable)
    }

    private func resumeStart(with error: Error?) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    private func setListener(_ listener: NWListener, port: UInt16) {
        lock.lock()
        self.listener = listener
        self.port = port
        self.isStopped = false
        lock.unlock()
    }

    private func receive(connection: NWConnection, data: Data) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var combined = data
            if let chunk { combined.append(chunk) }
            if let text = String(data: combined, encoding: .utf8), let headerEnd = text.range(of: "\r\n\r\n") {
                let header = String(text[..<headerEnd.lowerBound])
                self.handleRequest(header, connection: connection)
            } else if isComplete || error != nil || combined.count >= 65536 {
                connection.cancel()
            } else {
                self.receive(connection: connection, data: combined)
            }
        }
    }

    private func handleRequest(_ header: String, connection: NWConnection) {
        let requestLine = header.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let host = header.components(separatedBy: "\r\n").dropFirst().first { $0.lowercased().hasPrefix("host:") }?.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let expectedHosts = ["localhost", "localhost:\(port)", "127.0.0.1", "127.0.0.1:\(port)"]
        guard parts.count >= 2, parts[0] == "GET", host.map({ expectedHosts.contains($0) }) == true, let components = URLComponents(string: "http://localhost\(parts[1])") else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request")
            return
        }
        var callback = CodexOAuthCallback(path: components.path, code: nil, state: nil, error: nil, errorDescription: nil)
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            if let value = item.value { query[item.name] = value }
        }
        callback = CodexOAuthCallback(path: components.path, code: query["code"], state: query["state"], error: query["error"], errorDescription: query["error_description"])
        sendResponse(connection: connection, status: "200 OK", body: "Foundry received the authorization response. You can return to Foundry.")
        lock.lock()
        let continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()
        continuation?.resume(returning: callback)
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let data = Data(body.utf8)
        let response = Data("HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8) + data
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

enum CodexOAuthHTTP {
    static let issuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let codexEndpoint = "https://chatgpt.com/backend-api/codex/responses"
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: CodexOAuthRedirectDelegate(), delegateQueue: nil)
    }()

    static func authorizeURL(redirectURI: String, pkce: CodexPKCE, state: String, originator: String = "foundry") -> URL? {
        var components = URLComponents(string: "\(issuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access api.connectors.read api.connectors.invoke"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator)
        ]
        return components?.url
    }

    static func exchange(code: String, redirectURI: String, verifier: String) async throws -> CodexOAuthTokenResponse {
        try await postForm(path: "/oauth/token", values: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ], failure: { .tokenExchangeFailed($0) })
    }

    static func refresh(_ credential: AIOAuthCredential) async throws -> CodexOAuthTokenResponse {
        try await postForm(path: "/oauth/token", values: [
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken,
            "client_id": clientID
        ], failure: { .refreshFailed($0) })
    }

    static func requestDeviceCode() async throws -> OpenAIDeviceAuthorization {
        guard let url = URL(string: "\(issuer)/api/accounts/deviceauth/usercode") else { throw OpenAICodexOAuthError.deviceAuthorizationFailed("Invalid authorization URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw OpenAICodexOAuthError.deviceAuthorizationFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).") }
        do {
            let value = try JSONDecoder().decode(CodexDeviceCodeResponse.self, from: data)
            return OpenAIDeviceAuthorization(verificationURL: "\(issuer)/codex/device", userCode: value.userCode, deviceAuthID: value.deviceAuthID, interval: value.interval)
        } catch {
            throw OpenAICodexOAuthError.deviceAuthorizationFailed("Invalid device authorization response.")
        }
    }

    static func pollDeviceCode(_ authorization: OpenAIDeviceAuthorization) async throws -> CodexOAuthTokenResponse {
        let deadline = Date().addingTimeInterval(15 * 60)
        guard let url = URL(string: "\(issuer)/api/accounts/deviceauth/token") else { throw OpenAICodexOAuthError.deviceAuthorizationFailed("Invalid authorization URL.") }
        while Date() < deadline {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["device_auth_id": authorization.deviceAuthID, "user_code": authorization.userCode])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenAICodexOAuthError.deviceAuthorizationFailed("Invalid device authorization response.") }
            if 200..<300 ~= http.statusCode {
                do {
                    let value = try JSONDecoder().decode(CodexDeviceTokenResponse.self, from: data)
                    return try await exchange(code: value.authorizationCode, redirectURI: "\(issuer)/deviceauth/callback", verifier: value.codeVerifier)
                } catch let error as OpenAICodexOAuthError {
                    throw error
                } catch {
                    throw OpenAICodexOAuthError.deviceAuthorizationFailed("Invalid device authorization response.")
                }
            }
            if http.statusCode != 403 && http.statusCode != 404 { throw OpenAICodexOAuthError.deviceAuthorizationFailed("HTTP \(http.statusCode).") }
            try await Task.sleep(for: .milliseconds(Int(max(authorization.interval, 1) * 1000) + 3000))
        }
        throw OpenAICodexOAuthError.deviceAuthorizationTimeout
    }

    static func credential(from tokens: CodexOAuthTokenResponse, fallback: AIOAuthCredential? = nil) throws -> AIOAuthCredential {
        let accountID = OpenAIJWT.accountID(idToken: tokens.idToken, accessToken: tokens.accessToken) ?? fallback?.accountID
        guard let accountID, accountID.isEmpty == false else { throw OpenAICodexOAuthError.missingAccountID }
        let refreshToken = tokens.refreshToken ?? fallback?.refreshToken ?? ""
        guard refreshToken.isEmpty == false else { throw OpenAICodexOAuthError.missingCredential }
        return AIOAuthCredential(accessToken: tokens.accessToken, refreshToken: refreshToken, idToken: tokens.idToken ?? fallback?.idToken, accountID: accountID, expiresAt: Date().addingTimeInterval(max(tokens.expiresIn ?? 3600, 60)))
    }

    private static func postForm(path: String, values: [String: String], failure: (String) -> OpenAICodexOAuthError) async throws -> CodexOAuthTokenResponse {
        guard let url = URL(string: "\(issuer)\(path)") else { throw failure("Invalid authorization URL.") }
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw failure("Invalid token response.") }
        guard 200..<300 ~= http.statusCode else { throw failure("HTTP \(http.statusCode).") }
        do { return try JSONDecoder().decode(CodexOAuthTokenResponse.self, from: data) } catch { throw failure("Invalid token response.") }
    }
}

private final class CodexOAuthRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        guard task.currentRequest?.url?.host?.lowercased() == request.url?.host?.lowercased() else { completionHandler(nil); return }
        completionHandler(request)
    }
}

actor OpenAICodexOAuthService {
    static let shared = OpenAICodexOAuthService(store: KeychainAICredentialStore())

    private let store: AICredentialStore
    private var callbackServer: CodexOAuthCallbackServer?

    init(store: AICredentialStore) {
        self.store = store
    }

    func browserLogin(profileID: UUID) async throws -> AIOAuthCredential {
        let server = CodexOAuthCallbackServer()
        callbackServer = server
        defer {
            server.stop()
            callbackServer = nil
        }
        let port = try await server.start()
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let pkce = CodexPKCE.generate()
        let state = CodexOAuthSecurity.randomString(length: 32)
        guard let url = CodexOAuthHTTP.authorizeURL(redirectURI: redirectURI, pkce: pkce, state: state) else { throw OpenAICodexOAuthError.callbackMalformed }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw OpenAICodexOAuthError.unsupported("Foundry could not open the authorization page.") }
        let callback = try await withTaskCancellationHandler(operation: {
            try await withThrowingTaskGroup(of: CodexOAuthCallback.self) { group in
                group.addTask { try await server.waitForCallback() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    throw OpenAICodexOAuthError.callbackTimeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        }, onCancel: {
            server.stop()
        })
        guard callback.path == "/auth/callback" else { throw OpenAICodexOAuthError.callbackMalformed }
        guard let callbackState = callback.state, CodexOAuthSecurity.constantTimeEqual(callbackState, state) else { throw OpenAICodexOAuthError.stateMismatch }
        if let error = callback.error { throw OpenAICodexOAuthError.accessDenied(callback.errorDescription ?? error) }
        guard let code = callback.code, code.isEmpty == false else { throw OpenAICodexOAuthError.callbackMalformed }
        let tokens = try await CodexOAuthHTTP.exchange(code: code, redirectURI: redirectURI, verifier: pkce.verifier)
        let credential = try CodexOAuthHTTP.credential(from: tokens)
        try store.save(.oauth(credential), for: profileID)
        return credential
    }

    func requestDeviceAuthorization() async throws -> OpenAIDeviceAuthorization {
        try await CodexOAuthHTTP.requestDeviceCode()
    }

    func completeDeviceLogin(_ authorization: OpenAIDeviceAuthorization, profileID: UUID) async throws -> AIOAuthCredential {
        let tokens = try await CodexOAuthHTTP.pollDeviceCode(authorization)
        let credential = try CodexOAuthHTTP.credential(from: tokens)
        try store.save(.oauth(credential), for: profileID)
        return credential
    }

    func signOut(profileID: UUID) throws {
        try store.delete(for: profileID)
    }

    func cancelCurrentLogin() {
        callbackServer?.stop()
        callbackServer = nil
    }

    func hasCredential(profileID: UUID) -> Bool {
        do {
            guard let credential = try store.credential(for: profileID), case let .oauth(value) = credential else { return false }
            return value.isUsable
        } catch { return false }
    }

}

actor OpenAICodexTokenManager {
    static let shared = OpenAICodexTokenManager(store: KeychainAICredentialStore())

    private let store: AICredentialStore
    private var refreshTasks: [UUID: Task<AIOAuthCredential, Error>] = [:]

    init(store: AICredentialStore) {
        self.store = store
    }

    func validCredential(profileID: UUID, minimumValidity: TimeInterval = 60) async throws -> AIOAuthCredential {
        guard let credential = try store.credential(for: profileID), case let .oauth(value) = credential, value.isUsable else { throw OpenAICodexOAuthError.missingCredential }
        guard value.expiresAt.timeIntervalSinceNow <= minimumValidity else { return value }
        return try await refreshCredential(value, profileID: profileID)
    }

    func forceRefresh(profileID: UUID) async throws -> AIOAuthCredential {
        guard let credential = try store.credential(for: profileID), case let .oauth(value) = credential, value.isUsable else { throw OpenAICodexOAuthError.missingCredential }
        return try await refreshCredential(value, profileID: profileID)
    }

    private func refreshCredential(_ value: AIOAuthCredential, profileID: UUID) async throws -> AIOAuthCredential {
        if let task = refreshTasks[profileID] { return try await task.value }
        let task = Task { try await Self.refresh(value, store: store, profileID: profileID) }
        refreshTasks[profileID] = task
        defer { refreshTasks[profileID] = nil }
        return try await task.value
    }

    private static func refresh(_ credential: AIOAuthCredential, store: AICredentialStore, profileID: UUID) async throws -> AIOAuthCredential {
        do {
            let tokens = try await CodexOAuthHTTP.refresh(credential)
            let refreshed = try CodexOAuthHTTP.credential(from: tokens, fallback: credential)
            try store.save(.oauth(refreshed), for: profileID)
            return refreshed
        } catch let error as OpenAICodexOAuthError {
            throw error
        } catch {
            throw OpenAICodexOAuthError.refreshFailed("Unexpected refresh failure.")
        }
    }
}

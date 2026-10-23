import AuthenticationServices
import CryptoKit
import Security
import UIKit
import DoThisNowKit

/// Google Tasks over its web API. Sign-in is OAuth for an iOS app: no
/// secret, a PKCE code, and a refresh token kept in the Keychain.
@MainActor
final class GoogleTasks: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleTasks()

    /// The iOS OAuth client ID from the Google Cloud project. It isn't a
    /// secret: every app that signs in with Google ships its own.
    static let clientID = ""

    static var isConfigured: Bool {
        !clientID.isEmpty
    }

    enum Failure: LocalizedError {
        case notSetUp, cancelled, noCode, signedOut, server(Int)

        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Google sign-in isn’t set up in this version yet."
            case .cancelled: return "Sign-in was closed."
            case .noCode: return "Google didn’t send back a sign-in code."
            case .signedOut: return "You’re signed out of Google."
            case .server(let status): return "Google answered with error \(status)."
            }
        }
    }

    private static let scope = "https://www.googleapis.com/auth/tasks"
    private static let keychainAccount = "google-refresh-token"

    /// "com.googleusercontent.apps.123-abc", the client ID backwards.
    private static var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    private static var redirectURI: String {
        redirectScheme + ":/oauthredirect"
    }

    private var session: ASWebAuthenticationSession?
    private var accessToken: String?
    private var accessExpiry = Date.distantPast

    var isSignedIn: Bool {
        Keychain.read(Self.keychainAccount) != nil
    }

    // MARK: Signing in

    func signIn() async throws {
        guard Self.isConfigured else { throw Failure.notSetUp }
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw Failure.notSetUp }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: error ?? Failure.noCode)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        session = nil
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw Failure.noCode }

        let token = try await tokenRequest([
            "code": code,
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        if let refresh = token.refresh_token {
            Keychain.save(refresh, account: Self.keychainAccount)
        }
        remember(token)
    }

    func signOut() {
        Keychain.delete(Self.keychainAccount)
        accessToken = nil
        accessExpiry = .distantPast
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { () -> ASPresentationAnchor in
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first.map { UIWindow(windowScene: $0) } ?? UIWindow()
        }
    }

    // MARK: Tasks

    func lists() async throws -> [AppModel.SourceList] {
        struct Lists: Decodable {
            struct List: Decodable { let id: String; let title: String? }
            let items: [List]?
        }
        let lists: Lists = try await get("https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100")
        return (lists.items ?? []).map { AppModel.SourceList(id: $0.id, name: $0.title ?? "Untitled") }
    }

    /// Open tasks in every list. A task's ID is "<list>|<task>".
    func tasks(in lists: [AppModel.SourceList]) async throws -> [SourceTask] {
        struct Tasks: Decodable {
            struct Item: Decodable { let id: String; let title: String?; let notes: String?; let due: String? }
            let items: [Item]?
        }
        var out: [SourceTask] = []
        for list in lists {
            let encoded = list.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? list.id
            let page: Tasks = try await get("https://tasks.googleapis.com/tasks/v1/lists/\(encoded)/tasks?showCompleted=false&maxResults=100")
            for item in page.items ?? [] {
                let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                // Google keeps only the date of a due date.
                let due = item.due.flatMap { CalendarDay(key: String($0.prefix(10))) }?.startDate(calendar: .current)
                out.append(SourceTask(ref: SourceRef(.google, list.id + "|" + item.id), title: title, notes: item.notes ?? "",
                                      listID: list.id, listName: list.name, due: due))
            }
        }
        return out
    }

    func complete(_ id: String) async throws {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let list = parts[0].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? parts[0]
        let task = parts[1].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? parts[1]
        var request = URLRequest(url: URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(list)/tasks/\(task)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"status":"completed"}"#.utf8)
        _ = try await send(request)
    }

    // MARK: Plumbing

    private struct Token: Decodable {
        let access_token: String
        let expires_in: Double?
        let refresh_token: String?
    }

    private func remember(_ token: Token) {
        accessToken = token.access_token
        accessExpiry = Date().addingTimeInterval((token.expires_in ?? 3600) - 60)
    }

    private func tokenRequest(_ form: [String: String]) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401, form["grant_type"] == "refresh_token" {
            // The refresh token was revoked or expired: sign in again.
            signOut()
            throw Failure.signedOut
        }
        guard status == 200 else { throw Failure.server(status) }
        return try JSONDecoder().decode(Token.self, from: data)
    }

    private func validToken() async throws -> String {
        if let accessToken, accessExpiry > Date() { return accessToken }
        guard let refresh = Keychain.read(Self.keychainAccount) else { throw Failure.signedOut }
        let token = try await tokenRequest(["client_id": Self.clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        remember(token)
        return token.access_token
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.server(status) }
        return data
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        guard let url = URL(string: url) else { throw Failure.server(0) }
        return try JSONDecoder().decode(T.self, from: try await send(URLRequest(url: url)))
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A tiny wrapper over the Keychain for one string per account name.
enum Keychain {
    private static let service = "com.steveburlison.dothisnow"

    static func save(_ value: String, account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

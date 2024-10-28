import Foundation
import Alamofire

public struct ClientResponse<Data: Codable, Meta: Codable>: Codable {
    public var data: Data
    public var meta: Meta

    public init(data: Data, meta: Meta) {
        self.data = data
        self.meta = meta
    }
}

enum ApiResponse<Data: Codable, Meta: Codable>: Codable {
    case success(data: Data, meta: Meta)
    case failure(message: String, expired: Bool)

    private enum CodingKeys: String, CodingKey {
        case data
        case meta

        case success
        case error
        case expired
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let data = try container.decodeIfPresent(Data.self, forKey: .data),
           let meta = try container.decodeIfPresent(Meta.self, forKey: .meta) {
            self = .success(data: data, meta: meta)
            return
        }

        if let code = try container.decodeIfPresent(Int8.self, forKey: .success),
           code == 0,
           let message = try container.decodeIfPresent(String.self, forKey: .error)
        {
            let expired = try? container.decodeIfPresent(Int8.self, forKey: .expired) ?? 0
            self = .failure(message: message, expired: expired == 1)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .error, in: container,
            debugDescription: "Could not find `error` or `data` in response")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .failure(message, expired):
            try container.encode(0, forKey: .success)
            try container.encode(message, forKey: .error)
            try container.encode(expired ? 1 : 0, forKey: .expired)

        case let .success(data, meta):
            try container.encode(1, forKey: .success)
            try container.encode(data, forKey: .data)
            try container.encode(meta, forKey: .meta)
        }
    }
}

enum CCAPIError: LocalizedError {
    case classChartsError(message: String, expired: Bool)

    var errorDescription: String? {
        switch self {
        case let .classChartsError(message, expired):
            return "Something went wrong at the classcharts factory \(message), did we expire? \(expired ? "yes" : "no")"
        }
    }
}

struct LoginResponseMeta: Codable {
    var sessionId: String
}

typealias LoginResponse = ClientResponse<AnyCodableValue, LoginResponseMeta>

class CCAPI : APIProvider {
    var session: Session
    var authenticationInterceptor: AuthenticationInterceptor<ClientAuthenticator>
    var clientCredentialProvider: ClientCredentialProvider?

    var baseURL: URL
    var studentAPIPath: String

    public static let defaultClassChartsBaseURL = URL(string: "https://www.classcharts.com")!
    public static let defaultStudentAPIPath = "/apiv2student"

    init(
        baseURL: URL = defaultClassChartsBaseURL,
        studentAPIPath: String = defaultStudentAPIPath,
        clientCredentialProvider: ClientCredentialProvider? = nil
    ) {
        self.baseURL = baseURL
        self.studentAPIPath = studentAPIPath
        self.clientCredentialProvider = clientCredentialProvider

        let authenticator = ClientAuthenticator(
            url: baseURL.appending(path: studentAPIPath),
            provider: self.clientCredentialProvider
        )

        self.authenticationInterceptor = AuthenticationInterceptor(
            authenticator: authenticator,
            credential: self.clientCredentialProvider?.getCredential()
        )

        let interceptor = ConditionalAuthenticationInterceptor(
            authInterceptor: self.authenticationInterceptor,
            bypassPaths: ["\(studentAPIPath)/login"]
        )

        let session = Session(interceptor: interceptor)
        self.session = session
    }

    func handleRequest<Data: Decodable, Meta: Decodable>(
        _ request: DataRequest,
        for: ClientResponse<Data, Meta>.Type = ClientResponse<Data, Meta>.self
    ) async throws -> ClientResponse<Data, Meta> {
        let response = try await request
            .serializingDecodable(ApiResponse<Data, Meta>.self)
            .value

        switch response {
        case let .failure(message, expired):
            throw CCAPIError.classChartsError(message: message, expired: expired)
        case let .success(data, meta):
            return ClientResponse(data: data, meta: meta)
        }
    }

    func url(for path: URLConvertible) -> String {
        "\(baseURL)\(studentAPIPath)\(path)"
    }

    func login(code: String, dob: String) async throws {
        let parameters: Parameters = [
            "code": code.lowercased(),
            "dob": dob,
            "recaptcha-token": "no-token-available",
            "remember": true
        ]

        let response = try await handleRequest(session.request(
            url(for: "/login"),
            method: .post,
            parameters: parameters
        ), for: LoginResponse.self)

        let credential = ClientCredential(sessionId: response.meta.sessionId, grantedAt: .now)

        self.authenticationInterceptor.credential = credential
        try self.clientCredentialProvider?.updateCredential(with: credential)
    }

    func getAnnouncements() async throws -> AnnouncementResponse {
        try await handleRequest(session.request(url(for: "/announcements")))
    }
}

public struct ClientCredential: AuthenticationCredential, Equatable {
    public let sessionId: String
    public let grantedAt: Date

    public var requiresRefresh: Bool { (grantedAt.timeIntervalSinceNow * -1) >= 170.0 }

    public init(sessionId: String, grantedAt: Date) {
        self.sessionId = sessionId
        self.grantedAt = grantedAt
    }
}

enum ClientAuthenticatorError: Error {
    case emptyData
}

final class ConditionalAuthenticationInterceptor<Authenticator: Alamofire.Authenticator>: RequestInterceptor {
    private let authInterceptor: AuthenticationInterceptor<Authenticator>
    private let bypassPaths: [String]

    init(authInterceptor: AuthenticationInterceptor<Authenticator>, bypassPaths: [String]) {
        self.authInterceptor = authInterceptor
        self.bypassPaths = bypassPaths
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        guard let url = urlRequest.url, !shouldBypassAuthentication(for: url, with: urlRequest.headers) else {
            completion(.success(urlRequest))
            return
        }

        var request = urlRequest
        request.headers.remove(name: "Bypass-Auth")

        authInterceptor.adapt(request, for: session, completion: completion)
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        authInterceptor.retry(request, for: session, dueTo: error, completion: completion)
    }

    private func shouldBypassAuthentication(for url: URL, with headers: HTTPHeaders) -> Bool {
        if let authHeader = headers.value(for: "Bypass-Auth"), authHeader == "true" { return true }
        return bypassPaths.contains { url.path.hasPrefix($0) }
    }
}

public protocol ClientCredentialProvider: Sendable {
    func getCredential() -> ClientCredential?
    func updateCredential(with credential: ClientCredential) throws
}

public final class InMemoryClientCredentialProvider: ClientCredentialProvider, @unchecked Sendable {
    var clientCredential: ClientCredential?

    init(clientCredential: ClientCredential? = nil) {
        self.clientCredential = clientCredential
    }

    public func getCredential() -> ClientCredential? {
        self.clientCredential
    }

    public func updateCredential(with credential: ClientCredential) throws {
        self.clientCredential = credential
    }
}

struct GetSessionInfoMeta: Codable {
    var version: String
    var sessionId: String
}

typealias GetSessionInfo = ApiResponse<GetStudentInfoData, GetSessionInfoMeta>

final class ClientAuthenticator: Authenticator {
    let url: URL
    let provider: ClientCredentialProvider?

    init(
        url: URL,
        provider: ClientCredentialProvider? = nil
    ) {
        self.url = url
        self.provider = provider
    }

    func apply(_ credential: ClientCredential, to urlRequest: inout URLRequest) {
        urlRequest.headers.add(.authorization("Basic \(credential.sessionId)"))
    }

    func refresh(_ credential: ClientCredential,
                 for session: Session,
                 completion: @escaping (Result<ClientCredential, Error>) -> Void) {
        Task {
            let latestCredential = provider?.getCredential() ?? credential

            if !latestCredential.requiresRefresh && latestCredential != credential {
                completion(.success(latestCredential))
                return
            }

            let url = url.appending(path: "/ping")
            let headers: HTTPHeaders = [
                .authorization("Basic \(latestCredential.sessionId)"),
                HTTPHeader(name: "Bypass-Auth", value: "true")
            ]

            let parameters = ["include_data": "true"]

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let response = await session.request(url, method: .post, parameters: parameters, headers: headers).serializingDecodable(
                GetSessionInfo.self,
                decoder: decoder
            ).response

            guard let value = response.value else {
                return completion(.failure(response.error ?? ClientAuthenticatorError.emptyData))
            }

            switch value {
            case let .failure(message, expired):
                return completion(
                    .failure(
                        CCAPIError.classChartsError(message: message, expired: expired)
                    )
                )
            case .success(_, let meta):
                let credential = ClientCredential(sessionId: meta.sessionId, grantedAt: .now)

                try? self.provider?.updateCredential(with: credential)
                completion(.success(credential))
            }
        }
    }

    func didRequest(_ urlRequest: URLRequest,
                    with response: HTTPURLResponse,
                    failDueToAuthenticationError error: Error) -> Bool {
        return false
    }

    func isRequest(_ urlRequest: URLRequest, authenticatedWith credential: ClientCredential) -> Bool {
        return true
    }
}

func test() async throws {
    let api = CCAPI()
    let response = try await api.handleRequest(api.session.request("/homeworks"), for: ClientResponse<String, String>.self)
    print(response.data)
}

enum AnyCodableValue: Codable, Equatable, Hashable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let values = try? container.decode([AnyCodableValue].self) {
            self = .array(values)
        } else if let values = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(values)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The container contains an unsupported type.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let intValue):
            try container.encode(intValue)
        case .double(let doubleValue):
            try container.encode(doubleValue)
        case .string(let stringValue):
            try container.encode(stringValue)
        case .bool(let boolValue):
            try container.encode(boolValue)
        case .dictionary(let dictValue):
            try container.encode(dictValue)
        case .array(let arrayValue):
            try container.encode(arrayValue)
        case .null:
            try container.encodeNil()
        }
    }
}

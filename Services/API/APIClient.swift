import Foundation

protocol APIClient: Sendable {
    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response
}

protocol APITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: APITransport {}

protocol APIErrorHandling: Sendable {
    func map(_ error: Error) -> APIClientError
}

struct URLSessionAPIClient: APIClient {
    struct Configuration: Sendable {
        let requestInterceptors: [any APIRequestInterceptor]
        let responseInterceptors: [any APIResponseInterceptor]
        let errorHandler: any APIErrorHandling

        init(
            requestInterceptors: [any APIRequestInterceptor] = [
                DefaultHeadersInterceptor()
            ],
            responseInterceptors: [any APIResponseInterceptor] = [
                HTTPStatusValidationInterceptor()
            ],
            errorHandler: any APIErrorHandling = DefaultAPIErrorHandler()
        ) {
            self.requestInterceptors = requestInterceptors
            self.responseInterceptors = responseInterceptors
            self.errorHandler = errorHandler
        }
    }

    private let transport: any APITransport
    private let configuration: Configuration

    init(
        transport: any APITransport = URLSession(configuration: .vicuAPI),
        configuration: Configuration = Configuration()
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        var retryAttempt = 0

        do {
            while true {
                do {
                    return try await perform(request)
                } catch {
                    let apiError = configuration.errorHandler.map(error)
                    retryAttempt += 1

                    guard request.retryPolicy.shouldRetry(
                        apiError,
                        method: request.method,
                        retryAttempt: retryAttempt
                    ) else {
                        throw apiError
                    }

                    try await request.retryPolicy.sleepBeforeRetry(retryAttempt)
                }
            }
        } catch is CancellationError {
            throw APIClientError.cancelled
        }
    }

    private func perform<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        var urlRequest = try makeURLRequest(from: request)

        for interceptor in configuration.requestInterceptors + request.requestInterceptors {
            urlRequest = try await interceptor.adapt(urlRequest)
        }

        let (data, response) = try await transport.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        var context = APIResponseContext(request: urlRequest, response: httpResponse, data: data)
        for interceptor in request.responseInterceptors + configuration.responseInterceptors {
            context = try await interceptor.intercept(context)
        }

        guard !context.data.isEmpty || Response.self == EmptyAPIResponse.self else {
            throw APIClientError.emptyResponse
        }

        if Response.self == EmptyAPIResponse.self {
            return EmptyAPIResponse() as! Response
        }

        do {
            return try JSONDecoder().decode(Response.self, from: context.data)
        } catch {
            throw APIClientError.decodingFailed(type: String(describing: Response.self), message: error.localizedDescription)
        }
    }

    private func makeURLRequest<Response: Decodable & Sendable>(from request: APIRequest<Response>) throws -> URLRequest {
        var components = URLComponents(
            url: request.baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        )

        if !request.queryItems.isEmpty {
            components?.queryItems = request.queryItems
        }

        guard let url = components?.url else {
            throw APIClientError.invalidURL
        }

        var urlRequest = URLRequest(
            url: url,
            cachePolicy: request.cachePolicy,
            timeoutInterval: request.timeoutInterval ?? URLSessionConfiguration.vicuAPI.timeoutIntervalForRequest
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        request.headers.forEach { field, value in
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        return urlRequest
    }
}

struct DefaultAPIErrorHandler: APIErrorHandling {
    func map(_ error: Error) -> APIClientError {
        if let apiError = error as? APIClientError {
            return apiError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }

            return .transport(urlError)
        }

        return .underlying(error.localizedDescription)
    }
}

enum APIClientError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case cancelled
    case transport(URLError)
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(type: String, message: String)
    case underlying(String)

    var statusCode: Int? {
        if case .requestFailed(let statusCode, _) = self {
            return statusCode
        }

        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            L10n.API.invalidURL
        case .invalidResponse:
            L10n.API.invalidResponse
        case .emptyResponse:
            L10n.API.emptyResponse
        case .cancelled:
            L10n.API.cancelled
        case .transport(let error):
            L10n.API.transportFailed(error.localizedDescription)
        case .requestFailed(let statusCode, let message):
            L10n.API.requestFailed(statusCode: statusCode, message: message)
        case .decodingFailed(let type, let message):
            L10n.API.decodingFailed("\(type): \(message)")
        case .underlying(let message):
            message
        }
    }
}

enum APIErrorDisplayMessage {
    static func message(for error: Error, locale: Locale = AppLocale.current) -> String {
        if let apiError = error as? APIClientError {
            return message(for: apiError, locale: locale)
        }

        if let urlError = error as? URLError {
            return transportMessage(urlError, locale: locale)
        }

        return APIErrorMessageSanitizer.displayMessage(error.localizedDescription)
            ?? L10n.API.unexpected(locale: locale)
    }

    static func message(for apiError: APIClientError, locale: Locale = AppLocale.current) -> String {
        switch apiError {
        case .invalidURL:
            L10n.API.invalidURLText(locale: locale)
        case .invalidResponse, .emptyResponse, .decodingFailed(_, _):
            L10n.API.invalidResponseText(locale: locale)
        case .cancelled:
            L10n.API.cancelledText(locale: locale)
        case .transport(let error):
            transportMessage(error, locale: locale)
        case .requestFailed(let statusCode, let message):
            requestMessage(statusCode: statusCode, fallback: message, locale: locale)
        case .underlying(let message):
            APIErrorMessageSanitizer.displayMessage(message) ?? L10n.API.unexpected(locale: locale)
        }
    }

    private static func requestMessage(statusCode: Int, fallback: String, locale: Locale) -> String {
        switch statusCode {
        case 401:
            L10n.API.credentialsRejected(locale: locale)
        case 403:
            L10n.API.permissionDenied(locale: locale)
        case 404:
            L10n.API.resourceUnavailable(locale: locale)
        case 408:
            L10n.API.timeout(locale: locale)
        case 429:
            L10n.API.rateLimited(locale: locale)
        case 500...599:
            L10n.API.serviceUnavailable(locale: locale)
        case 400...499:
            L10n.API.requestRejected(locale: locale)
        default:
            APIErrorMessageSanitizer.displayMessage(fallback)
                ?? L10n.API.requestFailed(statusCode: statusCode, message: fallback, locale: locale)
        }
    }

    private static func transportMessage(_ error: URLError, locale: Locale) -> String {
        switch error.code {
        case .timedOut:
            L10n.API.timeout(locale: locale)
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            L10n.API.networkUnavailable(locale: locale)
        default:
            L10n.API.networkRequestFailed(locale: locale)
        }
    }
}

extension URLSessionConfiguration {
    static var vicuAPI: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

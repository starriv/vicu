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
        do {
            return try await perform(request)
        } catch {
            throw configuration.errorHandler.map(error)
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

enum APIClientError: LocalizedError, Equatable {
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

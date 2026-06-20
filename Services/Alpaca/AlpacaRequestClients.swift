import Foundation

protocol AlpacaTradingRequesting: Sendable {
    func send<Response: Decodable & Sendable>(
        _ endpoint: AlpacaEndpoint,
        body: Data?,
        credentials: AlpacaCredentials
    ) async throws -> Response
}

protocol AlpacaMarketDataRequesting: Sendable {
    func send<Response: Decodable & Sendable>(
        _ endpoint: AlpacaMarketDataEndpoint,
        credentials: AlpacaCredentials
    ) async throws -> Response
}

struct AlpacaTradingClient: AlpacaTradingRequesting {
    private let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: AlpacaEndpoint,
        body: Data? = nil,
        credentials: AlpacaCredentials
    ) async throws -> Response {
        try await apiClient.send(
            APIRequest(
                baseURL: credentials.environment.baseURL,
                path: endpoint.path,
                method: endpoint.method,
                queryItems: endpoint.queryItems,
                body: body,
                retryPolicy: endpoint.method == .get && body == nil ? .alpacaGET : .none,
                requestInterceptors: [
                    AlpacaAuthenticationInterceptor(credentials: credentials)
                ],
                responseInterceptors: [
                    AlpacaErrorResponseInterceptor()
                ]
            )
        )
    }
}

struct AlpacaMarketDataClient: AlpacaMarketDataRequesting {
    private let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
    }

    func send<Response: Decodable & Sendable>(
        _ endpoint: AlpacaMarketDataEndpoint,
        credentials: AlpacaCredentials
    ) async throws -> Response {
        try await apiClient.send(
            APIRequest(
                baseURL: APIPaths.AlpacaMarketData.baseURL,
                path: endpoint.path,
                method: .get,
                queryItems: endpoint.queryItems,
                retryPolicy: .marketDataGET,
                requestInterceptors: [
                    AlpacaAuthenticationInterceptor(credentials: credentials)
                ],
                responseInterceptors: [
                    AlpacaErrorResponseInterceptor()
                ]
            )
        )
    }
}

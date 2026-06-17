import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let baseURL: URL
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?
    let cachePolicy: URLRequest.CachePolicy
    let timeoutInterval: TimeInterval?
    let requestInterceptors: [any APIRequestInterceptor]
    let responseInterceptors: [any APIResponseInterceptor]

    init(
        baseURL: URL,
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        timeoutInterval: TimeInterval? = nil,
        requestInterceptors: [any APIRequestInterceptor] = [],
        responseInterceptors: [any APIResponseInterceptor] = []
    ) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
    }
}

struct EmptyAPIResponse: Decodable, Sendable {}

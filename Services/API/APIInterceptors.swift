import Foundation
import OSLog

struct APIResponseContext {
    let request: URLRequest
    let response: HTTPURLResponse
    let data: Data
}

protocol APIRequestInterceptor: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

protocol APIResponseInterceptor: Sendable {
    func intercept(_ context: APIResponseContext) async throws -> APIResponseContext
}

struct DefaultHeadersInterceptor: APIRequestInterceptor {
    private let headers: [String: String]

    init(headers: [String: String] = [:]) {
        self.headers = headers
    }

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValueIfMissing("application/json", forHTTPHeaderField: "Accept")
        request.setValueIfMissing(AppLocale.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")

        if request.httpBody != nil {
            request.setValueIfMissing("application/json", forHTTPHeaderField: "Content-Type")
        }

        headers.forEach { field, value in
            request.setValueIfMissing(value, forHTTPHeaderField: field)
        }

        return request
    }
}

struct HTTPStatusValidationInterceptor: APIResponseInterceptor {
    func intercept(_ context: APIResponseContext) async throws -> APIResponseContext {
        guard (200..<300).contains(context.response.statusCode) else {
            let message = APIErrorMessageSanitizer.displayMessage(from: context.data)
            throw APIClientError.requestFailed(statusCode: context.response.statusCode, message: message)
        }

        return context
    }
}

enum APIErrorMessageSanitizer {
    private static let maxLength = 500

    static func displayMessage(from data: Data) -> String {
        displayMessage(String(data: data, encoding: .utf8)) ?? L10n.Common.noResponseBody
    }

    static func displayMessage(_ rawMessage: String?) -> String? {
        guard let rawMessage else {
            return nil
        }

        let message = rawMessage
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !message.isEmpty else {
            return nil
        }

        if message.count <= maxLength {
            return message
        }

        return String(message.prefix(maxLength))
    }
}

struct APIDebugLoggingInterceptor: APIRequestInterceptor, APIResponseInterceptor {
    private static let logger = Logger(subsystem: "com.starriv.vicu", category: "API")

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        #if DEBUG
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<invalid-url>"
        Self.logger.debug("request method=\(method, privacy: .public) url=\(url, privacy: .public)")
        #endif
        return request
    }

    func intercept(_ context: APIResponseContext) async throws -> APIResponseContext {
        #if DEBUG
        let method = context.request.httpMethod ?? "GET"
        let url = context.request.url?.absoluteString ?? "<invalid-url>"
        Self.logger.debug("response status=\(context.response.statusCode, privacy: .public) method=\(method, privacy: .public) url=\(url, privacy: .public)")
        #endif
        return context
    }
}

private extension URLRequest {
    mutating func setValueIfMissing(_ value: String, forHTTPHeaderField field: String) {
        if self.value(forHTTPHeaderField: field) == nil {
            setValue(value, forHTTPHeaderField: field)
        }
    }
}

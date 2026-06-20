import Foundation

struct AlpacaAuthenticationInterceptor: APIRequestInterceptor {
    let credentials: AlpacaCredentials

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(credentials.keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }
}

struct AlpacaErrorResponseInterceptor: APIResponseInterceptor {
    func intercept(_ context: APIResponseContext) async throws -> APIResponseContext {
        guard !(200..<300).contains(context.response.statusCode) else {
            return context
        }

        if let alpacaError = try? JSONDecoder().decode(AlpacaErrorResponse.self, from: context.data),
           let message = alpacaError.resolvedMessage {
            throw APIClientError.requestFailed(statusCode: context.response.statusCode, message: message)
        }

        return context
    }
}

private struct AlpacaErrorResponse: Decodable {
    let code: String?
    let message: String?

    var resolvedMessage: String? {
        APIErrorMessageSanitizer.displayMessage(message ?? code)
    }
}

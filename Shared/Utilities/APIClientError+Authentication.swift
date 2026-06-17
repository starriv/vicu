extension Error {
    var isAuthenticationFailure: Bool {
        guard let apiError = self as? APIClientError,
              let statusCode = apiError.statusCode else {
            return false
        }

        return statusCode == 401 || statusCode == 403
    }
}

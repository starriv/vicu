import Foundation

extension Error {
    var isRequestCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let apiError = self as? APIClientError, apiError == .cancelled {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        return false
    }
}

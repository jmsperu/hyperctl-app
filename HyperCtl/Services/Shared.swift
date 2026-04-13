import Foundation

// MARK: - Errors

enum HyperCtlError: LocalizedError {
    case apiError(String)
    case parseError(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return msg
        case .parseError(let msg): return "Parse error: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        }
    }
}

// MARK: - Insecure TLS Delegate

final class InsecureDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = InsecureDelegate()

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

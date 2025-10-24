//
//  AIServiceError.swift
//  GlobalBridge
//
//  Comprehensive error types for AI service operations
//  Provides detailed error information for debugging and user feedback
//

import Foundation

/// Comprehensive error types for all AI service operations
enum AIServiceError: LocalizedError, Equatable {

    // MARK: - Network Errors

    /// Network request failed (no internet, timeout, etc.)
    case networkError(Error)

    /// Invalid server response (not HTTPURLResponse)
    case invalidResponse

    /// HTTP error with status code
    case httpError(statusCode: Int, message: String?)

    // MARK: - Authentication Errors

    /// User not authenticated or token expired
    case unauthorized

    /// User does not have permission for this operation
    case forbidden

    // MARK: - Rate Limiting Errors

    /// Rate limit exceeded with retry information
    case rateLimitExceeded(retryAfter: Date?, remainingQuota: Int?, tierLimit: String?)

    /// Feature disabled for current tier
    case featureNotAvailable(feature: String, requiredTier: String)

    // MARK: - Validation Errors

    /// Invalid input parameters
    case invalidInput(reason: String)

    /// Thread not found or user doesn't have access
    case threadNotFound(threadId: UUID)

    /// Empty or invalid text for translation
    case invalidText

    /// Unsupported language code
    case unsupportedLanguage(code: String)

    // MARK: - Parsing Errors

    /// Failed to decode response JSON
    case decodingError(Error)

    /// Backend returned success: false
    case backendError(message: String)

    // MARK: - Vector Database Errors

    /// Vector database not available or unhealthy
    case vectorDatabaseError(reason: String)

    /// No embeddings found for thread
    case noEmbeddingsAvailable(threadId: UUID)

    // MARK: - Feature Flag Errors

    /// Feature is disabled via feature flags
    case featureDisabled(feature: String)

    // MARK: - Unknown Errors

    /// Unexpected error occurred
    case unknown(Error)

    // MARK: - LocalizedError Conformance

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"

        case .invalidResponse:
            return "Invalid response from server"

        case .httpError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            } else {
                return "Server error: HTTP \(statusCode)"
            }

        case .unauthorized:
            return "Authentication required. Please log in again."

        case .forbidden:
            return "You don't have permission to perform this action."

        case .rateLimitExceeded(let retryAfter, let remainingQuota, let tierLimit):
            var message = "Rate limit exceeded."
            if let quota = remainingQuota, quota == 0 {
                message += " You've used all your quota."
            }
            if let tier = tierLimit {
                message += " Upgrade to \(tier) for more capacity."
            }
            if let retry = retryAfter {
                let formatter = DateComponentsFormatter()
                formatter.unitsStyle = .full
                formatter.allowedUnits = [.hour, .minute, .second]
                if let timeString = formatter.string(from: Date(), to: retry) {
                    message += " Try again in \(timeString)."
                }
            }
            return message

        case .featureNotAvailable(let feature, let requiredTier):
            return "\(feature) is not available on your current plan. Upgrade to \(requiredTier) to unlock this feature."

        case .invalidInput(let reason):
            return "Invalid input: \(reason)"

        case .threadNotFound(let threadId):
            return "Thread not found: \(threadId)"

        case .invalidText:
            return "Invalid text provided. Text cannot be empty."

        case .unsupportedLanguage(let code):
            return "Language '\(code)' is not supported."

        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"

        case .backendError(let message):
            return "Backend error: \(message)"

        case .vectorDatabaseError(let reason):
            return "Vector database error: \(reason)"

        case .noEmbeddingsAvailable(let threadId):
            return "No message embeddings available for thread \(threadId). Try again after messages are indexed."

        case .featureDisabled(let feature):
            return "\(feature) is currently disabled."

        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    var failureReason: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .rateLimitExceeded:
            return "You've reached your usage limit for this feature."
        case .unauthorized:
            return "Your session has expired."
        case .forbidden:
            return "Insufficient permissions."
        case .featureNotAvailable:
            return "Upgrade your plan to access this feature."
        case .vectorDatabaseError, .noEmbeddingsAvailable:
            return "The AI search system is initializing. Try again in a moment."
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again."
        case .unauthorized:
            return "Please log in again to continue."
        case .rateLimitExceeded(let retryAfter, _, _):
            if let retry = retryAfter {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                return "You can try again at \(formatter.string(from: retry))."
            } else {
                return "Please try again later or upgrade your plan."
            }
        case .featureNotAvailable(_, let tier):
            return "Upgrade to \(tier) plan to unlock this feature."
        case .threadNotFound:
            return "Make sure the conversation still exists."
        case .vectorDatabaseError, .noEmbeddingsAvailable:
            return "Please wait a moment and try again."
        case .featureDisabled:
            return "This feature is temporarily unavailable."
        default:
            return "Please try again later."
        }
    }

    // MARK: - Equatable Conformance

    static func == (lhs: AIServiceError, rhs: AIServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.invalidText, .invalidText):
            return true

        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg

        case (.rateLimitExceeded(let lRetry, let lQuota, let lTier),
              .rateLimitExceeded(let rRetry, let rQuota, let rTier)):
            return lRetry == rRetry && lQuota == rQuota && lTier == rTier

        case (.featureNotAvailable(let lFeature, let lTier),
              .featureNotAvailable(let rFeature, let rTier)):
            return lFeature == rFeature && lTier == rTier

        case (.invalidInput(let lReason), .invalidInput(let rReason)):
            return lReason == rReason

        case (.threadNotFound(let lId), .threadNotFound(let rId)):
            return lId == rId

        case (.unsupportedLanguage(let lCode), .unsupportedLanguage(let rCode)):
            return lCode == rCode

        case (.backendError(let lMsg), .backendError(let rMsg)):
            return lMsg == rMsg

        case (.vectorDatabaseError(let lReason), .vectorDatabaseError(let rReason)):
            return lReason == rReason

        case (.noEmbeddingsAvailable(let lId), .noEmbeddingsAvailable(let rId)):
            return lId == rId

        case (.featureDisabled(let lFeature), .featureDisabled(let rFeature)):
            return lFeature == rFeature

        default:
            return false
        }
    }

    // MARK: - Helper Methods

    /// Whether this error should trigger automatic retry
    var shouldRetry: Bool {
        switch self {
        case .networkError, .httpError(500...599, _):
            return true
        case .rateLimitExceeded(let retryAfter, _, _):
            return retryAfter != nil
        default:
            return false
        }
    }

    /// Whether this error requires user authentication
    var requiresAuth: Bool {
        switch self {
        case .unauthorized, .forbidden:
            return true
        default:
            return false
        }
    }

    /// Whether this error is due to insufficient tier/quota
    var isTierLimited: Bool {
        switch self {
        case .rateLimitExceeded, .featureNotAvailable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Construction Helpers

extension AIServiceError {
    /// Create error from HTTP response
    static func from(httpResponse: HTTPURLResponse, data: Data?) -> AIServiceError {
        let statusCode = httpResponse.statusCode

        // Try to extract error message from response
        var message: String?
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = json["error"] as? String ?? json["message"] as? String {
            message = errorMessage
        }

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .httpError(statusCode: statusCode, message: message ?? "Resource not found")
        case 429:
            // Parse rate limit headers
            let retryAfter = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap { TimeInterval($0) }
                .map { Date(timeIntervalSince1970: $0) }
            let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining")
                .flatMap { Int($0) }
            let tier = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Tier")

            return .rateLimitExceeded(retryAfter: retryAfter, remainingQuota: remaining, tierLimit: tier)

        case 400...499:
            return .httpError(statusCode: statusCode, message: message ?? "Client error")
        case 500...599:
            return .httpError(statusCode: statusCode, message: message ?? "Server error")
        default:
            return .httpError(statusCode: statusCode, message: message)
        }
    }

    /// Create error from URLError
    static func from(urlError: URLError) -> AIServiceError {
        return .networkError(urlError)
    }

    /// Create error from decoding error
    static func from(decodingError: Error) -> AIServiceError {
        return .decodingError(decodingError)
    }
}

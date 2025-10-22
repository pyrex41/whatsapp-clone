//
//  AuthManager.swift
//  GlobalBridge
//
//  Authentication manager with Auth0 integration and error handling
//

import Foundation
import Combine
import Auth0

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case noRefreshToken
    case tokenExpired
    case invalidToken(reason: String)
    case networkError(Error)
    case auth0Error(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please log in again."
        case .tokenExpired:
            return "Your session has expired. Logging you out..."
        case .invalidToken(let reason):
            return "Invalid token: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .auth0Error(let error):
            return "Auth0 error: \(error.localizedDescription)"
        case .unknown:
            return "An unexpected authentication error occurred."
        }
    }
}

// MARK: - AuthManager

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var userId: String?
    @Published private(set) var authError: String?
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?
    private var refreshTask: Task<Void, Never>?
    
    // Auth0 Configuration from Auth0Config
    private var auth0Domain: String {
        Auth0Config.domain
    }
    
    private var auth0ClientId: String {
        Auth0Config.clientId
    }
    
    private var auth0Audience: String {
        Auth0Config.audience
    }

    private init() {
        // Check if we have stored credentials
        Task {
            await restoreSession()
        }
    }
    
    /// Restore session from stored credentials
    private func restoreSession() async {
        let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
            clientId: auth0ClientId,
            domain: auth0Domain
        ))
        
        guard let credentials = try? await credentialsManager.credentials() else {
            print("ℹ️ [AUTH] No stored credentials found")
            return
        }
        
        accessToken = credentials.accessToken
        refreshToken = credentials.refreshToken
        
        // Extract expiration time
        if let expiresIn = credentials.expiresIn {
            tokenExpiresAt = Date().addingTimeInterval(expiresIn)
        }
        
        // Extract user ID from ID token claims
        userId = extractUserIdFromToken(credentials.idToken)
        
        isAuthenticated = true
        
        print("✅ [AUTH] Session restored for user: \(userId ?? "unknown")")
        
        // Schedule token refresh if needed
        scheduleTokenRefresh()
    }
    
    /// Login with Auth0
    func login() async throws -> String {
        print("🔐 [AUTH] Starting Auth0 login...")
        print("📱 [AUTH] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("🔍 [AUTH] Auth0 Configuration:")
        print("   - Domain: \(auth0Domain)")
        print("   - Client ID: \(auth0ClientId)")
        print("   - Audience: \(auth0Audience)")
        print("🔗 [AUTH] Expected callback: \(Bundle.main.bundleIdentifier ?? "unknown")://\(auth0Domain)/ios/\(Bundle.main.bundleIdentifier ?? "unknown")/callback")
        
        do {
            let credentials = try await Auth0
                .webAuth(clientId: auth0ClientId, domain: auth0Domain)
                .scope("openid profile email offline_access")
                .audience(auth0Audience)
                .start()
            
            // Store credentials securely
            let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
                clientId: auth0ClientId,
                domain: auth0Domain
            ))
            _ = credentialsManager.store(credentials: credentials)
            
            // Update state
            accessToken = credentials.accessToken
            refreshToken = credentials.refreshToken
            
            // Store expiration time
            if let expiresIn = credentials.expiresIn {
                tokenExpiresAt = Date().addingTimeInterval(expiresIn)
                print("⏰ [AUTH] Token expires in \(Int(expiresIn)) seconds")
            }
            
            // Extract user ID from ID token
            userId = extractUserIdFromToken(credentials.idToken)
            
            isAuthenticated = true
            authError = nil
            
            print("✅ [AUTH] Login successful")
            print("   User ID: \(userId ?? "unknown")")
            print("   Access Token: \(credentials.accessToken.prefix(20))...")
            
            // Schedule token refresh
            scheduleTokenRefresh()
            
            return credentials.accessToken
        } catch {
            let authError = AuthError.auth0Error(error)
            self.authError = authError.errorDescription
            print("❌ [AUTH] Login failed: \(authError.errorDescription ?? "Unknown error")")
            throw authError
        }
    }
    
    /// Logout from Auth0
    func logout() async throws {
        print("🚪 [AUTH] Logging out...")
        
        // Cancel any pending refresh tasks
        refreshTask?.cancel()
        refreshTask = nil
        
        do {
            // Clear Auth0 session
            try await Auth0
                .webAuth(clientId: auth0ClientId, domain: auth0Domain)
                .clearSession()
            
            // Clear stored credentials
            let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
                clientId: auth0ClientId,
                domain: auth0Domain
            ))
            _ = credentialsManager.clear()
            
            // Clear local state
            accessToken = nil
            refreshToken = nil
            userId = nil
            tokenExpiresAt = nil
            isAuthenticated = false
            authError = nil
            
            print("✅ [AUTH] Logout complete")
        } catch {
            let authError = AuthError.auth0Error(error)
            self.authError = authError.errorDescription
            print("⚠️ [AUTH] Logout error (but continuing): \(authError.errorDescription ?? "Unknown error")")
        }
    }
    
    /// Get current access token, refreshing if needed
    func getAccessToken() async -> String? {
        // Check if token needs refresh
        if needsRefresh() {
            print("🔄 [AUTH] Token needs refresh, attempting refresh...")
            do {
                _ = try await refreshToken()
                return accessToken
            } catch {
                let authError = AuthError.auth0Error(error)
                self.authError = authError.errorDescription
                print("❌ [AUTH] Token refresh failed: \(authError.errorDescription ?? "Unknown error")")
                return nil
            }
        }
        
        return accessToken
    }
    
    /// Refresh the access token using refresh token
    func refreshToken() async throws -> String {
        guard let refreshToken = refreshToken else {
            throw AuthError.noRefreshToken
        }
        
        print("🔄 [AUTH] Refreshing token...")
        
        let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
            clientId: auth0ClientId,
            domain: auth0Domain
        ))
        
        do {
            let credentials = try await credentialsManager.credentials()
            
            self.accessToken = credentials.accessToken
            self.refreshToken = credentials.refreshToken
            
            if let expiresIn = credentials.expiresIn {
                tokenExpiresAt = Date().addingTimeInterval(expiresIn)
                print("✅ [AUTH] Token refreshed. New expiration in \(Int(expiresIn)) seconds")
            }
            
            authError = nil
            
            return credentials.accessToken
        } catch {
            let authError = AuthError.auth0Error(error)
            self.authError = authError.errorDescription
            throw authError
        }
    }
    
    /// Get current user ID
    func getUserId() -> String? {
        return userId
    }
    
    /// Manual token update (for testing)
    func updateAccessToken(_ token: String?) {
        accessToken = token
    }
    
    /// Check if token needs refresh
    func needsRefresh() -> Bool {
        guard let expiresAt = tokenExpiresAt else {
            return true
        }
        
        // Refresh if token expires within 5 minutes
        let refreshThreshold = Date().addingTimeInterval(5 * 60)
        return expiresAt < refreshThreshold
    }
    
    /// Schedule automatic token refresh
    private func scheduleTokenRefresh() {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        guard let expiresAt = tokenExpiresAt else {
            print("⚠️ [AUTH] No token expiration time set, skipping refresh schedule")
            return
        }
        
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow
        let refreshTime = max(0, timeUntilExpiry - (5 * 60)) // Refresh 5 minutes before expiry
        
        print("⏰ [AUTH] Scheduling token refresh in \(Int(refreshTime)) seconds")
        
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(refreshTime * 1_000_000_000))
            
            if !Task.isCancelled {
                print("🔄 [AUTH] Auto-refreshing token...")
                do {
                    _ = try await self.refreshToken()
                    self.scheduleTokenRefresh() // Schedule next refresh
                } catch {
                    print("❌ [AUTH] Auto-refresh failed: \(error)")
                }
            }
        }
    }
    
    /// Extract user ID from JWT ID token
    private func extractUserIdFromToken(_ token: String) -> String? {
        // JWT format: header.payload.signature
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        
        // Decode payload (base64url)
        let payloadPart = String(parts[1])
        
        // Convert base64url to base64
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        
        return sub
    }
    
    /// Clear any stored errors
    func clearError() {
        authError = nil
    }
}

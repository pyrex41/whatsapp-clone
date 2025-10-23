//
//  AuthManager.swift
//  GlobalBridge
//
//  Authentication manager with Auth0 integration and error handling
//

import Foundation
import Combine
import Auth0
import UIKit

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

        // IMPORTANT: Check if the stored token is JWE (encrypted) format
        // If so, we need to clear it and force a fresh login
        let tokenParts = credentials.accessToken.split(separator: ".")
        if tokenParts.count == 5 {
            print("⚠️  [AUTH] Stored token is JWE (encrypted) format - CLEARING!")
            print("   This token was issued before Auth0 API was configured.")
            print("   Forcing logout to get fresh JWT tokens...")

            // Clear the old encrypted credentials
            _ = credentialsManager.clear()

            accessToken = nil
            refreshToken = nil
            userId = nil
            tokenExpiresAt = nil
            isAuthenticated = false

            print("✅ [AUTH] Old JWE token cleared. User will need to login again.")
            return
        }

        // Token is valid JWT format, restore session
        accessToken = credentials.accessToken
        refreshToken = credentials.refreshToken

        // Extract expiration time
        tokenExpiresAt = credentials.expiresIn

        // Extract user ID from ID token claims
        userId = extractUserIdFromToken(credentials.idToken)

        isAuthenticated = true

        print("✅ [AUTH] Session restored for user: \(userId ?? "unknown")")
        print("   Token format: JWT (3 parts) ✅")

        // Schedule token refresh if needed
        scheduleTokenRefresh()
    }
    
    private var loginTask: Task<String, Error>?

    /// Login with Auth0
    func login() async throws -> String {
        // If login is already in progress, wait for it
        if let existingTask = loginTask {
            print("⏳ [AUTH] Login already in progress, waiting...")
            return try await existingTask.value
        }

        // Create new login task
        let task = Task<String, Error> {
            print("🔐 [AUTH] Starting Auth0 login...")
            print("📱 [AUTH] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
            print("🔍 [AUTH] Auth0 Configuration:")
            print("   - Domain: \(auth0Domain)")
            print("   - Client ID: \(auth0ClientId)")
            print("   - Audience: \(auth0Audience)")
            print("🔗 [AUTH] Expected callback: \(Bundle.main.bundleIdentifier ?? "unknown")://\(auth0Domain)/ios/\(Bundle.main.bundleIdentifier ?? "unknown")/callback")
            print("")
            print("⚠️  [AUTH] IMPORTANT: This callback URL must be registered in Auth0 Dashboard:")
            print("   1. Go to https://manage.auth0.com/dashboard")
            print("   2. Select your application: \(auth0ClientId)")
            print("   3. Go to 'Settings' tab")
            print("   4. Add to 'Allowed Callback URLs': name.reubenbrooks.globalbridge://\(auth0Domain)/ios/name.reubenbrooks.globalbridge/callback")
            print("   5. Add to 'Allowed Logout URLs': name.reubenbrooks.globalbridge://\(auth0Domain)/ios/name.reubenbrooks.globalbridge/callback")
            print("   6. Scroll down and click 'Save Changes'")
            print("")
            print("🌐 [AUTH] About to open Auth0 web login UI...")
            
            // IMPORTANT: Wait for window scene to be active
            // Auth0 WebAuth requires an active window scene to present
            print("⏳ [AUTH] Waiting for scene to be active...")
            var attempts = 0
            while attempts < 20 {  // Wait up to 2 seconds
                if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   scene.activationState == .foregroundActive {
                    print("✅ [AUTH] Scene is active, proceeding with login")
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                attempts += 1
            }
            
            if attempts >= 20 {
                print("⚠️  [AUTH] Scene activation timeout - attempting login anyway")
            }

            do {
                // IMPORTANT: Using .audience() causes Auth0 to return encrypted JWE tokens
                // For now, we'll use it but note that backend needs to handle JWE format
                print("🚀 [AUTH] Calling Auth0.webAuth().start()...")
                let credentials = try await Auth0
                    .webAuth(clientId: auth0ClientId, domain: auth0Domain)
                    .audience(auth0Audience)
                    .scope("openid profile email offline_access")
                    .start()

                print("✅ [AUTH] Auth0 webAuth completed successfully!")
                print("")
                print("📊 [AUTH] Token Analysis:")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                // Analyze access token
                let accessTokenParts = credentials.accessToken.split(separator: ".")
                print("🔑 ACCESS TOKEN:")
                print("   - Format: \(accessTokenParts.count) parts (\(accessTokenParts.count == 3 ? "JWT ✅" : accessTokenParts.count == 5 ? "JWE ❌" : "UNKNOWN ❌"))")
                print("   - Preview: \(credentials.accessToken.prefix(40))...")
                print("   - Full length: \(credentials.accessToken.count) characters")
                if accessTokenParts.count == 5 {
                    print("   ⚠️  WARNING: This is an ENCRYPTED JWE token!")
                    print("   ⚠️  Backend cannot decode this!")
                }

                // Analyze ID token
                let idTokenParts = credentials.idToken.split(separator: ".")
                print("")
                print("🆔 ID TOKEN:")
                print("   - Format: \(idTokenParts.count) parts (\(idTokenParts.count == 3 ? "JWT ✅" : idTokenParts.count == 5 ? "JWE ❌" : "UNKNOWN ❌"))")
                print("   - Preview: \(credentials.idToken.prefix(40))...")
                print("   - Full length: \(credentials.idToken.count) characters")
                if idTokenParts.count == 3 && accessTokenParts.count == 5 {
                    print("   ✅ ID token is JWT - we should use THIS instead of access token!")
                }

                print("")
                print("📦 OTHER DETAILS:")
                print("   - Refresh Token: \(credentials.refreshToken != nil ? "present" : "nil")")
                print("   - Token Type: \(credentials.tokenType ?? "unknown")")
                print("   - Expires In: \(credentials.expiresIn)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("")

                // Store credentials securely
                let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
                    clientId: auth0ClientId,
                    domain: auth0Domain
                ))
                _ = credentialsManager.store(credentials: credentials)

                // Update state
                await MainActor.run {
                    self.accessToken = credentials.accessToken
                    self.refreshToken = credentials.refreshToken

                    // Store expiration time
                    self.tokenExpiresAt = credentials.expiresIn
                    let secondsUntilExpiry = credentials.expiresIn.timeIntervalSinceNow
                    print("⏰ [AUTH] Token expires in \(Int(secondsUntilExpiry)) seconds")

                    // Extract user ID from ID token
                    self.userId = self.extractUserIdFromToken(credentials.idToken)

                    self.isAuthenticated = true
                    self.authError = nil

                    print("✅ [AUTH] Login successful")
                    print("   User ID: \(self.userId ?? "unknown")")
                    print("   Access Token: \(credentials.accessToken.prefix(20))...")

                    // Schedule token refresh
                    self.scheduleTokenRefresh()

                    // Clear login task
                    self.loginTask = nil
                }

                return credentials.accessToken
            } catch {
                let authError = AuthError.auth0Error(error)
                await MainActor.run {
                    self.authError = authError.errorDescription
                    self.loginTask = nil
                }
                print("❌ [AUTH] Login failed: \(authError.errorDescription ?? "Unknown error")")
                throw authError
            }
        }

        loginTask = task
        return try await task.value
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

            // Clear feature flags cache
            FeatureFlags.shared.clearCache()

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
            
            tokenExpiresAt = credentials.expiresIn
            let secondsUntilExpiry = credentials.expiresIn.timeIntervalSinceNow
            print("✅ [AUTH] Token refreshed. New expiration in \(Int(secondsUntilExpiry)) seconds")
            
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

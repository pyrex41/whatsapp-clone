//
//  AuthManager.swift
//  GlobalBridge
//
//  Authentication manager with Auth0 integration
//

import Foundation
import Combine
import Auth0

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var userId: String?
    
    private var accessToken: String?
    private var refreshToken: String?
    
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
            return
        }
        
        accessToken = credentials.accessToken
        refreshToken = credentials.refreshToken
        
        // Extract user ID from ID token claims
        userId = extractUserIdFromToken(credentials.idToken)
        
        isAuthenticated = true
        
        print("✅ [AUTH] Session restored for user: \(userId ?? "unknown")")
    }
    
    /// Login with Auth0
    func login() async throws -> String {
        print("🔐 [AUTH] Starting Auth0 login...")
        
        let credentials = try await Auth0
            .webAuth(clientId: auth0ClientId, domain: auth0Domain)
            .scope("openid profile email offline_access")
            .audience(auth0Audience)
            .useHTTPS()
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
        
        // Extract user ID from ID token
        userId = extractUserIdFromToken(credentials.idToken)
        
        isAuthenticated = true
        
        print("✅ [AUTH] Login successful")
        print("   User ID: \(userId ?? "unknown")")
        print("   Access Token: \(credentials.accessToken.prefix(20))...")
        
        return credentials.accessToken
    }
    
    /// Logout from Auth0
    func logout() async throws {
        print("🚪 [AUTH] Logging out...")
        
        // Clear Auth0 session
        try await Auth0
            .webAuth(clientId: auth0ClientId, domain: auth0Domain)
            .useHTTPS()
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
        isAuthenticated = false
        
        print("✅ [AUTH] Logout complete")
    }
    
    /// Get current access token, refreshing if needed
    func getAccessToken() async -> String? {
        // Return cached token if available
        if let token = accessToken {
            return token
        }
        
        // Try to get from credentials manager (will refresh if needed)
        let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
            clientId: auth0ClientId,
            domain: auth0Domain
        ))
        
        guard let credentials = try? await credentialsManager.credentials() else {
            print("⚠️ [AUTH] No valid credentials available")
            return nil
        }
        
        accessToken = credentials.accessToken
        return credentials.accessToken
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
    func needsRefresh() async -> Bool {
        guard accessToken != nil else {
            return true
        }
        
        let credentialsManager = CredentialsManager(authentication: Auth0.authentication(
            clientId: auth0ClientId,
            domain: auth0Domain
        ))
        
        return !credentialsManager.hasValid()
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
}

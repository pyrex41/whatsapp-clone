//
//  Auth0Config.swift
//  GlobalBridge
//
//  Auth0 configuration
//  Set these values in Xcode scheme environment variables or create an Auth0.plist file
//

import Foundation

enum Auth0Config {
    /// Auth0 Domain (e.g., "dev-abc123.us.auth0.com")
    static var domain: String {
        // TEMPORARY: Force correct domain (stripping https:// if present)
        let correctDomain = "dev-1672riu03fjuf7so.us.auth0.com"
        
        let envDomain = ProcessInfo.processInfo.environment["AUTH0_DOMAIN"] ?? "not set"
        print("⚠️ [Auth0Config] FORCING correct domain: \(correctDomain)")
        print("   Environment value: \(envDomain)")
        print("   Plist value: \(bundle.object(forInfoDictionaryKey: "Auth0Domain") as? String ?? "not set")")
        
        return correctDomain
    }
    
    /// Auth0 Client ID
    static var clientId: String {
        // TEMPORARY: Force correct client ID
        let correctClientId = "id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj"
        
        let envClientId = ProcessInfo.processInfo.environment["AUTH0_CLIENT_ID"] ?? "not set"
        print("⚠️ [Auth0Config] FORCING correct clientId: \(correctClientId)")
        print("   Environment value: \(envClientId)")
        print("   Plist value: \(bundle.object(forInfoDictionaryKey: "Auth0ClientId") as? String ?? "not set")")
        
        return correctClientId
    }
    
    /// Auth0 Audience
    static var audience: String {
        // TEMPORARY: Force correct audience
        let correctAudience = "https://globalbridge-api"
        
        let envAudience = ProcessInfo.processInfo.environment["AUTH0_AUDIENCE"] ?? "not set"
        print("⚠️ [Auth0Config] FORCING correct audience: \(correctAudience)")
        print("   Environment value: \(envAudience)")
        print("   Plist value: \(bundle.object(forInfoDictionaryKey: "Auth0Audience") as? String ?? "not set")")
        
        return correctAudience
    }
    
    private static var bundle: Bundle {
        Bundle.main
    }
}


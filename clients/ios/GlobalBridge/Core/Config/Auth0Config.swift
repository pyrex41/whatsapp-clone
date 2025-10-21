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
        if let domain = ProcessInfo.processInfo.environment["AUTH0_DOMAIN"], !domain.isEmpty {
            return domain
        }
        // Fallback to plist
        if let domain = bundle.object(forInfoDictionaryKey: "Auth0Domain") as? String {
            return domain
        }
        // Development default
        return "dev-1672riu03fjuf7so.us.auth0.com"
    }
    
    /// Auth0 Client ID
    static var clientId: String {
        if let clientId = ProcessInfo.processInfo.environment["AUTH0_CLIENT_ID"], !clientId.isEmpty {
            return clientId
        }
        // Fallback to plist
        if let clientId = bundle.object(forInfoDictionaryKey: "Auth0ClientId") as? String {
            return clientId
        }
        // Development default
        return "id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj"
    }
    
    /// Auth0 Audience
    static var audience: String {
        if let audience = ProcessInfo.processInfo.environment["AUTH0_AUDIENCE"], !audience.isEmpty {
            return audience
        }
        // Fallback to plist
        if let audience = bundle.object(forInfoDictionaryKey: "Auth0Audience") as? String {
            return audience
        }
        // Default audience
        return "globalbridge-api"
    }
    
    private static var bundle: Bundle {
        Bundle.main
    }
}


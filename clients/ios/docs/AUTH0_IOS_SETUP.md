# Auth0 iOS Setup Guide

## Issue
The error "Application with identifier name.reubenbrooks.globalbridge is not associated with domain" occurs when trying to use Auth0 authentication.

## Solution

You have two options to fix this:

### Option 1: Use Custom URL Scheme (Recommended - Already Implemented)

1. **Remove `.useHTTPS()` from Auth0 WebAuth calls** ✅ (Already done)
   - The code has been updated to remove `.useHTTPS()` from both login and logout methods

2. **Configure URL Scheme in Xcode:**
   - Open `GlobalBridge.xcodeproj` in Xcode
   - Select the GlobalBridge target
   - Go to the "Info" tab
   - Add a new URL Type:
     - **Identifier**: `auth0`
     - **URL Schemes**: `name.reubenbrooks.globalbridge`
     - **Role**: None

3. **Configure Auth0 Application Settings:**
   - Log in to your Auth0 Dashboard
   - Go to Applications > GlobalBridge iOS
   - In the "Allowed Callback URLs" field, add:
     ```
     name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
     ```
   - In the "Allowed Logout URLs" field, add:
     ```
     name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
     ```
   - Save the changes

### Option 2: Use HTTPS Callbacks with Associated Domains

If you prefer to use HTTPS callbacks (more secure but requires Apple Developer account):

1. **Add Associated Domains Capability** ✅ (Already done)
   - The entitlements file has been updated with:
     ```xml
     <key>com.apple.developer.associated-domains</key>
     <array>
         <string>webcredentials:dev-1672riu03fjuf7so.us.auth0.com</string>
     </array>
     ```

2. **Re-enable `.useHTTPS()` in AuthManager.swift**
   - Add `.useHTTPS()` back to the WebAuth configuration in login and logout methods

3. **Configure Auth0 Tenant:**
   - Your Auth0 tenant must have an apple-app-site-association file configured
   - Contact Auth0 support or configure it in your Auth0 dashboard

4. **Configure in Apple Developer Portal:**
   - Log in to Apple Developer Portal
   - Go to Certificates, Identifiers & Profiles
   - Select your App ID
   - Enable "Associated Domains" capability
   - Add your Auth0 domain

5. **Ensure Provisioning Profile includes Associated Domains:**
   - Regenerate your provisioning profile after enabling Associated Domains
   - Download and install the new profile in Xcode

## Current Configuration

- **Auth0 Domain**: `dev-1672riu03fjuf7so.us.auth0.com`
- **Client ID**: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
- **Bundle ID**: `name.reubenbrooks.globalbridge`
- **Audience**: `globalbridge-api`

## Testing

After making these changes:

1. Clean the build folder (Cmd+Shift+K)
2. Delete the app from the simulator
3. Build and run the app
4. Try logging in with Auth0

## Troubleshooting

If you still encounter issues:

1. **Verify Bundle ID**: Make sure the bundle ID in Xcode matches exactly: `name.reubenbrooks.globalbridge`

2. **Check URL Scheme**: Verify the URL scheme is correctly configured in Xcode's Info tab

3. **Auth0 Dashboard**: Double-check the callback URLs in your Auth0 application settings

4. **Clear Safari Cache**: On the simulator, go to Settings > Safari > Clear History and Website Data

5. **Use Custom Scheme**: If HTTPS callbacks continue to fail, stick with the custom URL scheme (Option 1)

## Code Changes Made

The following changes have been made to fix the issue:

1. **AuthManager.swift**: Removed `.useHTTPS()` from WebAuth calls to use custom URL scheme
2. **GlobalBridge.entitlements**: Added Associated Domains capability (for future HTTPS support)

The app is now configured to use a custom URL scheme for Auth0 authentication, which doesn't require Associated Domains configuration.

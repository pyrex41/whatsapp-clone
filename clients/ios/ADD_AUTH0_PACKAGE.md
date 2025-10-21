# Adding Auth0 Swift Package to Xcode

## Steps to Add Auth0.swift Dependency

1. **Open Xcode project**
   ```bash
   cd /Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge
   open GlobalBridge.xcodeproj
   ```

2. **Add Package Dependency**
   - In Xcode, click on the **GlobalBridge** project in the navigator
   - Select the **GlobalBridge** target
   - Go to the **Package Dependencies** tab
   - Click the **+** button

3. **Search for Auth0**
   - In the search field, enter: `https://github.com/auth0/Auth0.swift`
   - Click **Add Package**

4. **Select Package Products**
   - Select **Auth0** library
   - Click **Add Package**

5. **Verify Installation**
   - Build the project (Cmd+B)
   - Check that `import Auth0` compiles in `AuthManager.swift`

## Alternative: Command Line (if using xcodegen or SPM)

If you prefer to add via Package.swift or project.pbxproj editing:

```swift
dependencies: [
    .package(url: "https://github.com/auth0/Auth0.swift", from: "2.0.0")
]
```

## Package Info

- **Repository**: https://github.com/auth0/Auth0.swift
- **Minimum Version**: 2.0.0
- **Documentation**: https://auth0.com/docs/quickstart/native/ios-swift

## After Adding Package

The `AuthManager.swift` file is already configured to use Auth0. Just:

1. Configure Auth0 credentials (see `AUTH0_CREDENTIALS_SETUP.md`)
2. Build and run the app
3. Auth0 login will work automatically!

## Troubleshooting

**"No such module 'Auth0'"**
- Make sure package was added successfully
- Try cleaning build folder (Cmd+Shift+K)
- Rebuild project (Cmd+B)

**Package resolution fails**
- Check internet connection
- Verify GitHub is accessible
- Try removing and re-adding the package



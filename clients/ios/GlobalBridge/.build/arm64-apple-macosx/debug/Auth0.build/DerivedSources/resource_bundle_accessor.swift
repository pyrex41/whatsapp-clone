import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("Auth0_Auth0.bundle").path
        let buildPath = "/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/.build/arm64-apple-macosx/debug/Auth0_Auth0.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}
//
//  AppLaunchManager.swift
//  GlobalBridge
//
//  Created by Claude on 10/26/25.
//

import Foundation
import Combine

@MainActor
class AppLaunchManager: ObservableObject {
    static let shared = AppLaunchManager()

    @Published var shouldShowSplashVideo: Bool = false

    private let hasLaunchedKey = "HasLaunchedBefore"
    private let lastLaunchDateKey = "LastLaunchDate"

    private init() {
        checkIfShouldShowSplash()
    }

    /// Determines if splash video should be shown
    /// Shows only on:
    /// - First ever launch
    /// - Cold starts (app was terminated, not just backgrounded)
    private func checkIfShouldShowSplash() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedKey)

        if !hasLaunchedBefore {
            // First launch ever - show splash
            shouldShowSplashVideo = true
            markAsLaunched()
        } else {
            // Check if this is a cold start (app was terminated)
            let lastLaunchDate = UserDefaults.standard.object(forKey: lastLaunchDateKey) as? Date
            let now = Date()

            // If last launch was more than 5 minutes ago, consider it a cold start
            if let lastLaunch = lastLaunchDate,
               now.timeIntervalSince(lastLaunch) > 300 {
                shouldShowSplashVideo = true
            } else {
                shouldShowSplashVideo = false
            }

            markAsLaunched()
        }

        print("🎬 [SPLASH] Should show splash: \(shouldShowSplashVideo)")
    }

    private func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        UserDefaults.standard.set(Date(), forKey: lastLaunchDateKey)
    }

    func completeSplash() {
        shouldShowSplashVideo = false
    }
}

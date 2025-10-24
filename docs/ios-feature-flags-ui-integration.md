# Feature Flags UI Components Integration Guide

## Overview

This guide explains how to integrate the Feature Flags UI components into the GlobalBridge iOS app. These components provide visual feedback for user tiers, feature availability, and usage quotas.

## Components Created

### 1. FeatureBadgeView.swift
**Location:** `/clients/ios/GlobalBridge/UI/Views/FeatureBadgeView.swift`

Displays tier badges ("Free", "Pro", "Enterprise") with optional feature availability status.

**Features:**
- Compact and full display modes
- Tier-specific colors and icons
- Feature availability indicators
- Accessibility support (VoiceOver)
- Light/dark mode support
- Smooth animations

**Usage Examples:**

```swift
// Compact tier badge (for navigation bars, settings)
FeatureBadgeView(tier: .pro, compact: true)

// Full tier badge with feature status
FeatureBadgeView(
    tier: .free,
    feature: .e2ee,
    isEnabled: false
)
```

### 2. UsageQuotaView.swift
**Location:** `/clients/ios/GlobalBridge/UI/Views/UsageQuotaView.swift`

Displays usage quotas with progress bars, warnings, and upgrade prompts.

**Features:**
- Multiple quota types (group members, storage, file size, etc.)
- Visual progress indicators with color coding
- Warning states at 80%+ usage
- Upgrade prompts for free users
- Unlimited tier display
- Built-in upgrade sheet
- Accessibility support

**Usage Examples:**

```swift
// Compact quota display
UsageQuotaView(
    quotaType: .groupMembers,
    current: 45,
    limit: 100,
    tier: .free,
    compact: true
)

// Full quota display with warnings
UsageQuotaView(
    quotaType: .storage,
    current: 8,
    limit: 10,
    tier: .free
)

// Unlimited display (enterprise)
UsageQuotaView(
    quotaType: .storage,
    current: 150,
    limit: nil,
    tier: .enterprise
)
```

### 3. FeatureFlagsService.swift
**Location:** `/clients/ios/GlobalBridge/Core/Services/FeatureFlagsService.swift`

Observable wrapper for FeatureFlags providing reactive SwiftUI integration.

**Features:**
- `@Published` properties for reactive updates
- Singleton pattern for easy access
- Usage tracking per quota type
- Automatic cache management
- Error handling

## Integration Steps

### Step 1: Import the Service in Your View

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var featureService = FeatureFlagsService.shared

    var body: some View {
        // Your view implementation
    }
}
```

### Step 2: Display Tier Badge

Add tier badges to show user subscription level:

```swift
// In navigation bar
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        FeatureBadgeView(
            tier: featureService.currentTier,
            compact: true
        )
    }
}

// In settings header
VStack(alignment: .leading, spacing: 16) {
    Text("Your Plan")
        .font(.headline)

    FeatureBadgeView(tier: featureService.currentTier)
}
```

### Step 3: Display Usage Quotas

Show usage limits for different resources:

```swift
VStack(spacing: 16) {
    // Group members quota
    if let limit = featureService.getLimit(for: .groupMembers) {
        UsageQuotaView(
            quotaType: .groupMembers,
            current: featureService.getCurrentUsage(for: .groupMembers),
            limit: limit,
            tier: featureService.currentTier
        )
    }

    // Storage quota
    if let limit = featureService.getLimit(for: .storage) {
        UsageQuotaView(
            quotaType: .storage,
            current: featureService.getCurrentUsage(for: .storage),
            limit: limit,
            tier: featureService.currentTier
        )
    }
}
```

### Step 4: Check Feature Availability

Guard features behind availability checks:

```swift
Button("Start Voice Call") {
    if featureService.hasFeature(.voiceCalls) {
        // Initiate call
    } else {
        // Show upgrade prompt
        showUpgradeSheet = true
    }
}

// Or use inline badge
HStack {
    Text("Voice Calls")

    if !featureService.hasFeature(.voiceCalls) {
        FeatureBadgeView(
            tier: featureService.currentTier,
            feature: .voiceCalls,
            isEnabled: false,
            compact: true
        )
    }
}
```

### Step 5: Refresh Features on App Launch

In your app initialization or root view:

```swift
struct AppRootView: View {
    @ObservedObject var featureService = FeatureFlagsService.shared

    var body: some View {
        // Your main view
            .task {
                await featureService.refreshFeatures()
            }
    }
}
```

## Real-World Integration Examples

### Settings Screen

```swift
struct SettingsView: View {
    @ObservedObject var featureService = FeatureFlagsService.shared

    var body: some View {
        NavigationView {
            List {
                // Account section with tier badge
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Account Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(featureService.tierDisplayText)
                                .font(.headline)
                        }

                        Spacer()

                        FeatureBadgeView(
                            tier: featureService.currentTier,
                            compact: true
                        )
                    }
                } header: {
                    Text("Subscription")
                }

                // Usage quotas section
                Section {
                    if let groupLimit = featureService.getLimit(for: .groupMembers) {
                        UsageQuotaView(
                            quotaType: .groupMembers,
                            current: featureService.getCurrentUsage(for: .groupMembers),
                            limit: groupLimit,
                            tier: featureService.currentTier
                        )
                    }

                    if let storageLimit = featureService.getLimit(for: .storage) {
                        UsageQuotaView(
                            quotaType: .storage,
                            current: featureService.getCurrentUsage(for: .storage),
                            limit: storageLimit,
                            tier: featureService.currentTier
                        )
                    }
                } header: {
                    Text("Usage")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

### Feature-Gated Button

```swift
struct FeatureButton: View {
    let feature: FeatureFlags.Feature
    let title: String
    let action: () -> Void

    @ObservedObject var featureService = FeatureFlagsService.shared
    @State private var showUpgrade = false

    var body: some View {
        Button(action: {
            if featureService.hasFeature(feature) {
                action()
            } else {
                showUpgrade = true
            }
        }) {
            HStack {
                Text(title)

                if !featureService.hasFeature(feature) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                }
            }
        }
        .disabled(!featureService.hasFeature(feature))
        .sheet(isPresented: $showUpgrade) {
            UpgradePromptView(feature: feature)
        }
    }
}

// Usage
FeatureButton(
    feature: .videoCalls,
    title: "Start Video Call"
) {
    startVideoCall()
}
```

### Group Creation with Quota Check

```swift
struct NewGroupView: View {
    @ObservedObject var featureService = FeatureFlagsService.shared
    @State private var memberCount = 0

    var body: some View {
        VStack(spacing: 16) {
            // Member selection UI

            // Show quota status
            if let limit = featureService.getLimit(for: .groupMembers) {
                UsageQuotaView(
                    quotaType: .groupMembers,
                    current: memberCount,
                    limit: limit,
                    tier: featureService.currentTier,
                    compact: true
                )
            }

            Button("Create Group") {
                createGroup()
            }
            .disabled(isOverLimit)
        }
    }

    var isOverLimit: Bool {
        guard let limit = featureService.getLimit(for: .groupMembers) else {
            return false
        }
        return memberCount > limit
    }
}
```

## Quota Types Reference

Available quota types in `UsageQuotaView.QuotaType`:

| Type | Description | Format | Free Tier | Pro Tier | Enterprise |
|------|-------------|--------|-----------|----------|------------|
| `.groupMembers` | Max members per group | count | 100 | 250 | Unlimited |
| `.fileSize` | Max file upload size | MB | 20 | 100 | Unlimited |
| `.storage` | Total storage limit | GB | 10 | 100 | Unlimited |
| `.callParticipants` | Max call participants | count | 5 | 25 | Unlimited |
| `.messageHistory` | Message retention | days | 30 | 365 | Unlimited |

## Color Coding

### Usage Status Colors

- **Green** (0-49%): Healthy usage
- **Yellow** (50-79%): Moderate usage
- **Orange** (80-99%): Approaching limit (warning)
- **Red** (100%+): At or over limit

### Tier Colors

- **Blue**: Free tier
- **Purple**: Pro tier
- **Orange**: Enterprise tier

## Accessibility

Both components include full accessibility support:

- **VoiceOver labels**: Descriptive text for screen readers
- **Dynamic Type**: Text scales with user preferences
- **High Contrast**: Colors adapt to accessibility settings
- **Reduced Motion**: Respects animation preferences

## Testing in Xcode Previews

Both components include comprehensive SwiftUI previews:

```swift
// Preview different states
#Preview("All States") {
    ScrollView {
        VStack(spacing: 20) {
            // Low usage
            UsageQuotaView(quotaType: .groupMembers, current: 23, limit: 100, tier: .free)

            // High usage
            UsageQuotaView(quotaType: .storage, current: 8, limit: 10, tier: .free)

            // At limit
            UsageQuotaView(quotaType: .fileSize, current: 20, limit: 20, tier: .free)

            // Unlimited
            UsageQuotaView(quotaType: .storage, current: 150, limit: nil, tier: .enterprise)
        }
        .padding()
    }
}
```

## Performance Considerations

- **Caching**: FeatureFlags are cached locally and only fetched when needed
- **Reactive Updates**: Uses `@Published` for efficient SwiftUI updates
- **Lazy Loading**: Quotas only query when needed
- **Memory**: Lightweight components with minimal state

## Backend Integration

The components integrate with the backend Feature Flags API:

- **GET** `/api/v1/features` - Fetch all features and limits
- **GET** `/api/v1/features/:feature` - Check specific feature

See [api-integration-summary.md](/docs/api-integration-summary.md) for API details.

## Next Steps

1. Add upgrade flow implementation
2. Implement actual usage tracking (currently using UserDefaults)
3. Add analytics events for upgrade prompts
4. Create settings screen with all quota views
5. Add in-app purchase integration for upgrades

## Troubleshooting

### Features not updating
- Check network connectivity
- Verify authentication token is valid
- Call `await featureService.refreshFeatures()` manually

### Incorrect usage values
- Usage tracking is currently demo/mock data
- Implement actual usage tracking in your backend

### Accessibility issues
- Test with VoiceOver enabled
- Check Dynamic Type scaling
- Verify color contrast in accessibility inspector

## Related Files

- `/clients/ios/GlobalBridge/Core/Utilities/FeatureFlags.swift` - Core feature flags logic
- `/clients/ios/GlobalBridge/Core/Services/FeatureFlagsService.swift` - Observable service wrapper
- `/clients/ios/GlobalBridge/UI/Views/FeatureBadgeView.swift` - Tier badge component
- `/clients/ios/GlobalBridge/UI/Views/UsageQuotaView.swift` - Quota display component

## Support

For questions or issues, see the project documentation or contact the development team.

# Xcode Project Setup Instructions

## Step-by-Step Guide to Add New Files and Configure Project

### 1. Add New Swift Files to Xcode Project

#### A. Models
1. Open `GlobalBridge.xcodeproj` in Xcode
2. In Project Navigator, right-click on `Core/Models/Phoenix/` folder
3. Select **Add Files to "GlobalBridge"...**
4. Navigate to `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Models/Phoenix/`
5. Select `TypingIndicator.swift`
6. Ensure these settings:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: GlobalBridge
7. Click **Add**

#### B. Services
1. Right-click on `Core/` folder
2. Select **New Group** and name it `Services`
3. Right-click on `Core/Services/` folder
4. Select **Add Files to "GlobalBridge"...**
5. Navigate to `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Services/`
6. Select `NotificationManager.swift`
7. Ensure same settings as above
8. Click **Add**

#### C. UI Views
1. Right-click on project root
2. Select **New Group** and name it `UI`
3. Right-click on `UI/`
4. Select **New Group** and name it `Views`
5. Right-click on `UI/Views/` folder
6. Select **Add Files to "GlobalBridge"...**
7. Navigate to `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/UI/Views/`
8. Select all view files:
   - `TypingIndicatorView.swift`
   - `PresenceBadgeView.swift`
   - `MessageCellView.swift`
   - `ChatView.swift`
   - `ThreadListView.swift`
9. Ensure same settings
10. Click **Add**

#### D. Test Files
1. In Project Navigator, right-click on `Tests/` folder
2. Select **Add Files to "GlobalBridge"...**
3. Navigate to `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Tests/`
4. Select all test files:
   - `TypingIndicatorTests.swift`
   - `ReadReceiptTests.swift`
   - `NotificationManagerTests.swift`
   - `PhoenixStateManagerTests.swift`
5. Ensure these settings:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: GlobalBridgeTests
6. Click **Add**

### 2. Configure Push Notification Capability

1. Select **GlobalBridge** project in Navigator
2. Select **GlobalBridge** target
3. Click **Signing & Capabilities** tab
4. Click **+ Capability** button
5. Search for and add:
   - **Push Notifications**
6. Click **+ Capability** again
7. Search for and add:
   - **Background Modes**
8. Under Background Modes, enable:
   - ✅ Remote notifications
   - ✅ Background fetch

### 3. Update Info.plist

1. In Project Navigator, select `Info.plist`
2. Right-click in the editor area
3. Select **Add Row**
4. Add the following keys:

**Privacy - User Notifications Usage Description:**
- Key: `NSUserNotificationsUsageDescription`
- Type: `String`
- Value: `We need notification permissions to send you messages and updates.`

**Background Modes:**
- Key: `UIBackgroundModes`
- Type: `Array`
- Add items:
  - `remote-notification` (String)
  - `fetch` (String)

Or add this XML directly to Info.plist:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>We need notification permissions to send you messages and updates.</string>
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

### 4. Verify Project Structure

After adding files, your project structure should look like:

```
GlobalBridge/
├── GlobalBridge/
│   ├── GlobalBridgeApp.swift (modified)
│   └── ContentView.swift (modified)
├── Core/
│   ├── Models/
│   │   └── Phoenix/
│   │       ├── PhoenixMessage.swift (existing)
│   │       └── TypingIndicator.swift (new)
│   ├── Networking/
│   │   └── Phoenix/
│   │       ├── PhoenixChannelManager.swift (modified)
│   │       ├── PhoenixStateManager.swift (modified)
│   │       └── PhoenixConfig.swift (existing)
│   └── Services/
│       └── NotificationManager.swift (new)
├── UI/
│   └── Views/
│       ├── TypingIndicatorView.swift (new)
│       ├── PresenceBadgeView.swift (new)
│       ├── MessageCellView.swift (new)
│       ├── ChatView.swift (new)
│       └── ThreadListView.swift (new)
└── Tests/
    ├── TypingIndicatorTests.swift (new)
    ├── ReadReceiptTests.swift (new)
    ├── NotificationManagerTests.swift (new)
    └── PhoenixStateManagerTests.swift (new)
```

### 5. Build and Verify

1. Select a simulator (e.g., iPhone 15 Pro)
2. Press `Cmd + B` to build
3. Fix any build errors if they appear
4. Press `Cmd + R` to run
5. Accept notification permission when prompted

### 6. Run Tests

1. Press `Cmd + U` to run all tests
2. Verify all tests pass
3. Check test results in Test Navigator

## Troubleshooting

### Build Error: "Cannot find type 'TypingIndicator'"
**Solution:** Ensure `TypingIndicator.swift` is added to GlobalBridge target

### Build Error: "No such module 'UserNotifications'"
**Solution:** UserNotifications is a system framework, no import needed

### Files appear red in Xcode
**Solution:** Files are not in the correct location. Use "Add Files" instead of dragging

### Tests not running
**Solution:** Ensure test files are added to GlobalBridgeTests target

### Notification permission not requested
**Solution:** Check that `GlobalBridgeApp.swift` has been modified correctly

## Verification Checklist

- [ ] All Swift files added to Xcode project
- [ ] Files organized in correct groups
- [ ] Push Notifications capability added
- [ ] Background Modes capability added
- [ ] Info.plist updated with notification permission
- [ ] Project builds without errors (`Cmd + B`)
- [ ] App runs in simulator (`Cmd + R`)
- [ ] Tests pass (`Cmd + U`)
- [ ] Notification permission prompt appears on first launch

## Next Steps

After completing this setup:
1. Test typing indicators in ChatView
2. Test presence badges in ThreadListView
3. Send test notification to verify push notification handling
4. Configure APNs certificate for production

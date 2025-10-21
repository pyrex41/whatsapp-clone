# Fix: Add Auth0 Package in Xcode

The project file has been reverted. Auth0 package exists but needs to be linked to the target.

## Option 1: Let Xcode Resolve It (Easiest - 30 seconds)

1. **Open the project:**
   ```bash
   cd /Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge
   open GlobalBridge.xcodeproj
   ```

2. **Xcode will show a package resolution dialog** - Click "Resolve"

3. **Or manually resolve:**
   - File → Packages → Resolve Package Versions
   - Wait for it to finish

4. **Link Auth0 to target:**
   - Select **GlobalBridge** project (left sidebar)
   - Select **GlobalBridge** target
   - Go to **General** tab
   - Scroll to **Frameworks, Libraries, and Embedded Content**
   - Click **+** button
   - Search for "Auth0" in the list
   - Add **Auth0** library

5. **Build:**
   - Product → Clean Build Folder (Cmd+Shift+K)
   - Product → Build (Cmd+B)

The "No such module 'Auth0'" error should be gone!

## Option 2: Remove and Re-add Package (1 minute)

If Option 1 doesn't work:

1. **Open Xcode project**

2. **Remove Auth0 package:**
   - Select **GlobalBridge** project
   - Go to **Package Dependencies** tab
   - Select **Auth0** package
   - Click **-** (minus) button to remove it

3. **Re-add Auth0 package:**
   - Click **+** (plus) button
   - Paste: `https://github.com/auth0/Auth0.swift`
   - Click **Add Package**
   - Select **Auth0** library
   - Click **Add Package**

4. **Build:**
   - Product → Clean Build Folder
   - Product → Build

## Option 3: Manual Package Resolution (If Xcode UI fails)

```bash
cd /Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge

# Reset package caches
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf .build

# Open project
open GlobalBridge.xcodeproj
```

Then in Xcode:
- File → Packages → Reset Package Caches
- File → Packages → Resolve Package Versions

---

## Why This Happened

I manually edited the `project.pbxproj` file to link the Auth0 package, which created an invalid reference that Xcode couldn't understand. The file format is very strict and easy to corrupt.

**Solution:** Let Xcode handle package linking through its UI rather than manual file editing.

---

## After Fixing

Once Auth0 is properly linked:

1. **Build** (Cmd+B) - Should succeed
2. **Add URL scheme** (see TESTING_GUIDE.md)
3. **Configure Auth0 Dashboard** (see TESTING_GUIDE.md)
4. **Run and test!**

---

## If Still Having Issues

**Nuclear option - Recreate package dependencies:**

1. In Xcode, remove ALL packages
2. Re-add them one by one:
   - SwiftPhoenixClient
   - SQLite.swift
   - Auth0.swift

This ensures clean state.


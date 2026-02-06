# MULTIPLATFORM-DIR-3: Xcode Project Configuration

## Overview
Configure the Xcode project to build for macOS, iPad, and iPhone.
These steps are done in the Xcode UI — do NOT hand-edit project.pbxproj.

## Step 1: Add iOS Destination

1. Open the project in Xcode (click `mac-claude-chat.xcodeproj`)
2. In the **Project Navigator** (left sidebar), click the top-level 
   **mac-claude-chat** project (blue icon, not the yellow folder)
3. Select the **mac-claude-chat** target (under TARGETS, not PROJECT)
4. Click the **General** tab
5. Under **Supported Destinations**, you should see "macOS"
6. Click the **+** button below the destinations list
7. Select **iPhone** — this adds iOS support (covers both iPhone and iPad)
8. You should now see both "macOS" and "iPhone" listed

## Step 2: Set iOS Deployment Target

1. Still on the **General** tab for the mac-claude-chat target
2. Under **Minimum Deployments**, you should now see entries for both
   macOS and iOS
3. Set the iOS deployment target to **18.0** 
   (This gives broad device compatibility while supporting all the
   SwiftUI features we use — NavigationSplitView, etc.)
4. Keep macOS at its current value

## Step 3: Verify Signing

1. Click the **Signing & Capabilities** tab
2. You should see sections for both macOS and iOS
3. For iOS: ensure "Automatically manage signing" is checked
4. Select your Team (same Apple ID you use for macOS)
5. The bundle identifier should auto-fill as `JCC.mac-claude-chat`

## Step 4: iOS Entitlements

When you added the iOS destination, Xcode may have auto-created an
iOS entitlements file, or it may share the existing one. We need to 
verify the iOS build has network access and Keychain.

1. In **Signing & Capabilities** tab, with **iOS** selected at the top
2. Click **+ Capability**
3. Add **Keychain Sharing** if not already present
4. Set the Keychain Group to: `$(AppIdentifierPrefix)JCC.mac-claude-chat`
   (should match the macOS entitlement)
5. Verify **Outgoing Connections (Client)** is enabled under 
   App Sandbox (or that the network entitlement exists)

**Note:** iOS apps don't use App Sandbox the way macOS does — they're
always sandboxed. The network client entitlement (`com.apple.security.network.client`)
is macOS-specific. iOS gets network access by default. Xcode should 
handle this automatically, but verify the build doesn't complain.

## Step 5: App Icon for iOS

1. In the Project Navigator, expand **mac-claude-chat** folder → **Assets.xcassets**
2. Click **AppIcon**
3. You should see the existing macOS icon slots filled
4. If Xcode added an iOS section, drag your `icon_1024.png` into the 
   iOS 1024x1024 slot (Xcode generates all other sizes)
5. If there's no iOS section: Right-click in Assets.xcassets → 
   "New iOS App Icon" and add the 1024px image

**Shortcut:** Modern Xcode (15+) with a "Single Size" app icon only
needs the 1024x1024 source. Check if your AppIcon asset is configured
as "Single Size" — if so, the same icon works for both platforms
automatically.

## Step 6: First iOS Build (Simulator)

1. In the Xcode toolbar, click the destination/device picker
   (where it currently says "My Mac" or similar)
2. Select an iPad simulator (e.g., "iPad Pro 13-inch")
3. Press **Cmd+B** to build (not run yet, just build)
4. Fix any compilation errors — if DIR-1 and DIR-2 were applied
   correctly, there should be none
5. If it builds clean, press **Cmd+R** to run in the simulator
6. Verify: sidebar shows, you can create a chat, model picker works
7. Then switch to an iPhone simulator (e.g., "iPhone 16") and repeat

## Expected Behavior

**iPad:** Should look similar to Mac — sidebar on left, chat on right.
NavigationSplitView adapts automatically.

**iPhone:** Sidebar becomes the initial view. Tap a chat to push into
the message view. Swipe back (or tap Back) to return to chat list.
This is automatic NavigationSplitView behavior.

## Troubleshooting

- **"Cannot find type NSColor"** — DIR-1 was not applied correctly,
  check for remaining `nsColor` references
- **"menuStyle(.borderlessButton) unavailable"** — DIR-1 Step 4 
  was missed
- **Signing errors** — Make sure your Apple Developer team is selected
  for the iOS target
- **"No such module" errors** — All our imports (SwiftUI, SwiftData, 
  Foundation, Security) are available on both platforms. If you see this,
  check that the iOS deployment target is set correctly.

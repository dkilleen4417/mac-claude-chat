# MULTIPLATFORM-DIR-1: Git Branch + Platform Conditionals

## Overview
Create a working branch and fix all macOS-specific code in ContentView.swift
so the source compiles for both macOS and iOS.

## Step 1: Create Git Branch

```bash
cd ~/.projects/mac-claude-chat
git checkout -b multiplatform-ios
```

## Step 2: Add Platform Color Helper (ContentView.swift)

Add this extension **immediately after** the existing `import SwiftData` line at the top
of `ContentView.swift` (line 4). This keeps the platform conditionals in one clean place
instead of scattering `#if` blocks throughout the views.

```swift
// MARK: - Platform Colors

enum PlatformColor {
    static var windowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
    
    static var textBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}
```

## Step 3: Replace All NSColor References (ContentView.swift)

There are exactly 4 lines to change. Replace each one:

### Line ~224 (header bar background)
**Find:**
```swift
.background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
```
**Replace with:**
```swift
.background(PlatformColor.windowBackground.opacity(0.8))
```

### Line ~368 (text field background)
**Find:**
```swift
.background(Color(nsColor: .textBackgroundColor))
```
**Replace with:**
```swift
.background(PlatformColor.textBackground)
```

### Line ~842 (CodeBlockView background)
**Find:**
```swift
.background(Color(nsColor: .textBackgroundColor).opacity(0.8))
```
**Replace with:**
```swift
.background(PlatformColor.textBackground.opacity(0.8))
```

## Step 4: Wrap menuStyle Modifier (ContentView.swift)

### Line ~320 (model picker menu style)
**Find:**
```swift
                    .menuStyle(.borderlessButton)
```
**Replace with:**
```swift
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
```

## Step 5: Wrap the Preview (ContentView.swift)

The `.frame(width: 900, height: 600)` on the Preview is fine for macOS but
misleading for iOS. Replace the Preview at the bottom:

**Find:**
```swift
#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
```
**Replace with:**
```swift
#Preview {
    ContentView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}
```

## Verification

After these changes, `ContentView.swift` should have:
- Zero references to `NSColor`, `nsColor`, or `NSBezierPath`
- A `PlatformColor` enum near the top with two static properties
- Two `#if os(macOS)` blocks (menuStyle and Preview)
- All other code unchanged

**Do NOT build yet** — the Xcode project still targets macOS only.
Directive 2 handles project configuration.

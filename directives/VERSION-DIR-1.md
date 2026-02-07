# DIR-1: Add App Version Display for Multi-Device Sync Awareness

## Objective
Add a visible version string so Drew can glance at any device (Mac, iPhone, iPad) and confirm it's running the current build. Essential for maintaining CloudKit/SwiftData schema concurrency across devices.

## Prerequisites
- Current app compiles and runs

## Instructions

### Step 1: Create AppConfig.swift
**File**: `mac-claude-chat/AppConfig.swift`
**Action**: Create new file

```swift
//
//  AppConfig.swift
//  mac-claude-chat
//
//  Created by Drew on 2/6/26.
//

import Foundation

/// Central app configuration. Bump buildVersion before any SwiftData
/// schema change, then rebuild and deploy to ALL devices before
/// making the schema change.
enum AppConfig {
    /// Manual build version — bump this with every deployment.
    /// Format: "YYYY.MM.DD" with optional letter suffix for same-day builds.
    static let buildVersion = "2025.02.06a"

    /// App display name shown in UI headers.
    static let appName = "mac-claude-chat"
}
```

### Step 2: Display Version in Sidebar Footer
**File**: `mac-claude-chat/ContentView.swift`
**Location**: Inside the `NavigationSplitView` sidebar `VStack`, after the `List(sortedChats, ...)` closing brace
**Action**: Add version footer between the List and the closing `}` of the sidebar VStack

**Find this code**:
```swift
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !chat.isDefault {
                            Button(role: .destructive) {
                                deleteChat(chat)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
```

**Replace with**:
```swift
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !chat.isDefault {
                            Button(role: .destructive) {
                                deleteChat(chat)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("v\(AppConfig.buildVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
```

## Verification
1. Build and run on Mac
2. Confirm "v2025.02.06a" appears at the bottom of the sidebar, below the chat list
3. Build and run on iPhone — same version string visible
4. Both devices show identical version

## Checkpoint
- [ ] App compiles without errors
- [ ] Version string visible at bottom of sidebar on all devices
- [ ] Existing chat functionality unchanged

## Usage Going Forward
Before any SwiftData model change:
1. Bump `AppConfig.buildVersion` (e.g., "2025.02.07a")
2. Build and deploy to ALL devices with the new version but OLD schema
3. Confirm all devices show matching version
4. THEN make the schema change in the next build

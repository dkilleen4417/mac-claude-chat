# DIR-1: Extend KeychainService and APIKeySetupView for Tool API Keys

## Objective
Add Tavily and OpenWeatherMap key storage to KeychainService, and add optional key fields to the API key setup UI. App continues to work exactly as before — these are additive changes only.

## Prerequisites
- Current app compiles and runs

## Instructions

### Step 1: Refactor KeychainService to Support Multiple Keys
**File**: `mac-claude-chat/KeychainService.swift`
**Action**: Replace entire file contents

```swift
//
//  KeychainService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import Foundation
import Security

/// A service for securely storing and retrieving API keys from the macOS Keychain
enum KeychainService {
    private static let service = "JCC.mac-claude-chat"

    // MARK: - Account Identifiers

    private static let anthropicAccount = "anthropic-api-key"
    private static let tavilyAccount = "tavily-api-key"
    private static let owmAccount = "owm-api-key"

    // MARK: - Generic Keychain Helpers

    @discardableResult
    private static func saveKey(_ key: String, account: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete any existing key first
        deleteKey(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func getKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    @discardableResult
    private static func deleteKey(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Anthropic API Key

    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        saveKey(apiKey, account: anthropicAccount)
    }

    static func getAPIKey() -> String? {
        getKey(account: anthropicAccount)
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        deleteKey(account: anthropicAccount)
    }

    static func hasAPIKey() -> Bool {
        getAPIKey() != nil
    }

    // MARK: - Tavily API Key

    @discardableResult
    static func saveTavilyKey(_ key: String) -> Bool {
        saveKey(key, account: tavilyAccount)
    }

    static func getTavilyKey() -> String? {
        if let keychainKey = getKey(account: tavilyAccount), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["TAVILY_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    // MARK: - OpenWeatherMap API Key

    @discardableResult
    static func saveOWMKey(_ key: String) -> Bool {
        saveKey(key, account: owmAccount)
    }

    static func getOWMKey() -> String? {
        if let keychainKey = getKey(account: owmAccount), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["OWM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }
}
```

### Step 2: Update APIKeySetupView with Optional Tool Key Fields
**File**: `mac-claude-chat/APIKeySetupView.swift`
**Action**: Replace entire file contents

```swift
//
//  APIKeySetupView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI

struct APIKeySetupView: View {
    @Binding var isPresented: Bool
    @State private var apiKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var owmKey: String = ""
    @State private var showingKey: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    var onSave: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("API Key Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your keys are stored securely in the macOS Keychain.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Anthropic API Key (required)
            VStack(alignment: .leading, spacing: 4) {
                Text("Anthropic API Key (required)")
                    .font(.caption)
                    .fontWeight(.semibold)

                HStack {
                    if showingKey {
                        TextField("sk-ant-api03-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-ant-api03-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button(action: { showingKey.toggle() }) {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 400)

            Divider()
                .frame(maxWidth: 400)

            // Tool API Keys (optional)
            VStack(alignment: .leading, spacing: 12) {
                Text("Tool API Keys (optional — enables web search and weather)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tavily Search API Key")
                        .font(.caption)
                    TextField("tvly-...", text: $tavilyKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenWeatherMap API Key")
                        .font(.caption)
                    TextField("OpenWeatherMap key", text: $owmKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: 400)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                if KeychainService.hasAPIKey() {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .keyboardShortcut(.escape)
                }

                Button(action: saveKeys) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save Keys")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .keyboardShortcut(.return)
            }
            .padding(.top, 8)

            HStack(spacing: 16) {
                Link("Anthropic API Key",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                Link("Tavily API Key",
                     destination: URL(string: "https://app.tavily.com/home")!)
                Link("OWM API Key",
                     destination: URL(string: "https://home.openweathermap.org/api_keys")!)
            }
            .font(.caption)
        }
        .padding(32)
        .frame(width: 500)
        .onAppear {
            if let existingKey = KeychainService.getAPIKey() {
                apiKey = existingKey
            }
            if let existingTavily = KeychainService.getTavilyKey() {
                tavilyKey = existingTavily
            }
            if let existingOWM = KeychainService.getOWMKey() {
                owmKey = existingOWM
            }
        }
    }

    private func saveKeys() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            errorMessage = "Please enter an Anthropic API key"
            return
        }

        guard trimmedKey.hasPrefix("sk-ant-") else {
            errorMessage = "Invalid API key format. Keys should start with 'sk-ant-'"
            return
        }

        isSaving = true
        errorMessage = nil

        // Save Anthropic key (required)
        guard KeychainService.saveAPIKey(trimmedKey) else {
            errorMessage = "Failed to save Anthropic API key to Keychain"
            isSaving = false
            return
        }

        // Save optional tool keys
        let trimmedTavily = tavilyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTavily.isEmpty {
            KeychainService.saveTavilyKey(trimmedTavily)
        }

        let trimmedOWM = owmKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOWM.isEmpty {
            KeychainService.saveOWMKey(trimmedOWM)
        }

        isPresented = false
        onSave?()
    }
}

#Preview {
    APIKeySetupView(isPresented: .constant(true))
}
```

## Verification
1. Build and run the app
2. Open API Key Settings (⌘,)
3. Confirm you see the Anthropic field (existing key pre-filled) plus Tavily and OWM fields
4. Enter test values in Tavily/OWM fields, save, reopen — values should persist
5. Existing chat functionality unchanged

## Checkpoint
- [ ] App compiles without errors
- [ ] API Key Settings sheet shows all three key fields
- [ ] Anthropic key still works as before (chat functions normally)
- [ ] Tavily and OWM keys persist across settings reopens

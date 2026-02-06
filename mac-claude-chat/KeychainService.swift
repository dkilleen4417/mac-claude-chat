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

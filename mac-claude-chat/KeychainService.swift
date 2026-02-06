//
//  KeychainService.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import Foundation
import Security

/// A service for securely storing and retrieving the Anthropic API key from the macOS Keychain
enum KeychainService {
    private static let service = "com.mac-claude-chat.api-key"
    private static let account = "anthropic-api-key"
    
    /// Saves the API key to the Keychain
    /// - Parameter apiKey: The API key to store
    /// - Returns: True if successful, false otherwise
    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else {
            return false
        }
        
        // Delete any existing key first
        deleteAPIKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieves the API key from the Keychain
    /// - Returns: The stored API key, or nil if not found
    static func getAPIKey() -> String? {
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
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    /// Deletes the API key from the Keychain
    /// - Returns: True if successful or key didn't exist, false on error
    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Checks if an API key exists in the Keychain
    /// - Returns: True if an API key is stored
    static func hasAPIKey() -> Bool {
        return getAPIKey() != nil
    }
}

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
    @State private var showingKey: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    
    var onSave: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("Anthropic API Key")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter your Anthropic API key to use Claude. Your key will be stored securely in the macOS Keychain.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
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
                
                Button(action: saveKey) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .keyboardShortcut(.return)
            }
            .padding(.top, 8)
            
            Link("Get an API key from Anthropic",
                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
        }
        .padding(32)
        .frame(width: 500)
        .onAppear {
            // Pre-fill with existing key if updating
            if let existingKey = KeychainService.getAPIKey() {
                apiKey = existingKey
            }
        }
    }
    
    private func saveKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            errorMessage = "Please enter an API key"
            return
        }
        
        guard trimmedKey.hasPrefix("sk-ant-") else {
            errorMessage = "Invalid API key format. Keys should start with 'sk-ant-'"
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        if KeychainService.saveAPIKey(trimmedKey) {
            isPresented = false
            onSave?()
        } else {
            errorMessage = "Failed to save API key to Keychain"
            isSaving = false
        }
    }
}

#Preview {
    APIKeySetupView(isPresented: .constant(true))
}

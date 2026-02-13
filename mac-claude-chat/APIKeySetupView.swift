//
//  APIKeySetupView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/5/26.
//

import SwiftUI

struct APIKeySetupView: View {
    @Binding var isPresented: Bool
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
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

            Divider()
                .frame(maxWidth: 400)

            // Appearance Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.caption)
                    .fontWeight(.semibold)

                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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

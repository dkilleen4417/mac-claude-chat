//
//  SettingsView.swift
//  mac-claude-chat
//
//  Created by Drew on 2/13/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
                .tag(1)
            
            SystemPromptTab()
                .tabItem {
                    Label("System Prompt", systemImage: "doc.text")
                }
                .tag(2)
        }
        .frame(width: 650, height: 500)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @State private var apiKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var owmKey: String = ""
    @State private var showingKey: Bool = false
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    @State private var showSuccessMessage: Bool = false
    
    var body: some View {
        Form {
            Section("API Keys") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your keys are stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Anthropic API Key
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
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Tool API Keys
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
                    
                    HStack(spacing: 8) {
                        Button(action: saveKeys) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Save Keys")
                            }
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        
                        if showSuccessMessage {
                            Text("✓ Saved")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                    
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
            }
            
            Section("Appearance") {
                Picker("Color Scheme", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            loadKeys()
        }
    }
    
    private func loadKeys() {
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
        showSuccessMessage = false
        
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
        
        isSaving = false
        showSuccessMessage = true
        
        // Hide success message after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSuccessMessage = false
        }
    }
}

// MARK: - Models Tab

struct ModelsSettingsTab: View {
    @AppStorage("routerEnabled") private var routerEnabled: Bool = true
    @AppStorage("fixedModel") private var fixedModel: String = ClaudeModel.fast.rawValue
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The router automatically selects between Haiku and Sonnet based on message complexity. Turn it off to always use a specific model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Toggle("Enable Automatic Router", isOn: $routerEnabled)
                        .toggleStyle(.switch)
                    
                    if !routerEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fixed Model")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Picker("", selection: $fixedModel) {
                                ForEach(ClaudeModel.allCases) { model in
                                    HStack {
                                        Text(model.emoji)
                                        Text(model.displayName)
                                    }
                                    .tag(model.rawValue)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                        .padding(.top, 8)
                    }
                }
            } header: {
                Text("Model Selection")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Slash commands always work regardless of router setting:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("/haiku")
                                .font(.caption.monospaced())
                                .fontWeight(.semibold)
                            Text("— Use Haiku for this message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("/sonnet")
                                .font(.caption.monospaced())
                                .fontWeight(.semibold)
                            Text("— Use Sonnet for this message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("/opus")
                                .font(.caption.monospaced())
                                .fontWeight(.semibold)
                            Text("— Use Opus for this message")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Slash Commands")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - System Prompt Tab

/// Default system prompt template
private let defaultSystemPrompt = """
You are Claude, an AI assistant in a natural conversation with Drew (Andrew Killeen), a retired engineer and programmer in Catonsville, Maryland.

CONVERSATIONAL APPROACH:
- This is a real conversation, not a series of isolated requests and responses.
- Build on what's been discussed, reference earlier parts of conversation.
- Express curiosity, surprise, agreement, or thoughtful disagreement naturally.
- Be genuine and conversational, not formulaic.

USER CONTEXT:
- Name: Drew (Andrew Killeen), prefers "Drew"
- Location: Catonsville, Maryland (Eastern timezone)
- Background: 74-year-old retired engineer, 54 years of coding experience
- Current interests: Python/Streamlit/SwiftUI development, AI applications, gardening, weather

TOOL USAGE:
You have tools available — use them confidently:
- get_datetime: Get current date and time (Eastern timezone)
- search_web: Search the web for current information (news, sports, events, research)
- get_weather: Get current weather (defaults to Catonsville, Maryland)
- web_lookup: Look up information from curated web sources
Don't deflect with "I don't have real-time data" — search for it.
IMPORTANT: Use all tools silently. Never announce that you are checking the date, time, weather, or searching. Just do it and weave the results into your response naturally.
You can call multiple tools in a single response when needed.
For weather queries with no specific location, default to Drew's location.

TEMPORAL REFERENCES:
When the user mentions any relative time ("last Sunday", "this week", "yesterday", "recently", "the latest"), ALWAYS call get_datetime first to anchor your reasoning to the actual current date before proceeding.
Never assume you know today's date — always verify with the tool.
Use tools silently — don't announce that you're checking the date, time, or weather. Just do it and incorporate the results naturally.

ICEBERG TIP:
At the very end of every response, append a one-line summary of this exchange wrapped in an HTML comment marker. This summary captures the essence of what was discussed or accomplished in this turn — it will be used for conversation context in future turns. Format:
<!--tip:Brief summary of what was discussed or accomplished-->
Keep tips under 20 words. Examples:
<!--tip:Greeted user, casual check-in-->
<!--tip:Explained SwiftData CloudKit constraints and migration strategy-->
<!--tip:Provided weather for Catonsville, clear skies 44°F-->
"""

struct SystemPromptTab: View {
    @AppStorage("systemPromptTemplate") private var systemPromptTemplate: String = defaultSystemPrompt
    @State private var editedPrompt: String = ""
    @State private var showResetConfirmation: Bool = false
    @State private var hasUnsavedChanges: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with info and buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize the system prompt that defines Claude's behavior and context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Button("Reset to Default") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if hasUnsavedChanges {
                        Button("Revert") {
                            editedPrompt = systemPromptTemplate
                            hasUnsavedChanges = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Save Changes") {
                            systemPromptTemplate = editedPrompt
                            hasUnsavedChanges = false
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("✓ Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            
            Divider()
            
            // Text editor
            TextEditor(text: $editedPrompt)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .onChange(of: editedPrompt) { oldValue, newValue in
                    hasUnsavedChanges = (newValue != systemPromptTemplate)
                }
        }
        .onAppear {
            editedPrompt = systemPromptTemplate
        }
        .alert("Reset System Prompt", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                editedPrompt = defaultSystemPrompt
                systemPromptTemplate = defaultSystemPrompt
                hasUnsavedChanges = false
            }
        } message: {
            Text("This will reset the system prompt to its default value. Your custom prompt will be lost.")
        }
    }
}

#Preview {
    SettingsView()
}

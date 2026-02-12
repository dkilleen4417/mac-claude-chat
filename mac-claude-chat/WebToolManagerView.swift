//
//  WebToolManagerView.swift
//  mac-claude-chat
//
//  Web Tools: Manager view for configuring web tool categories and sources.
//  Standalone sheet accessible from the menu bar.
//

import SwiftUI
import SwiftData

struct WebToolManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var categories: [WebToolCategory] = []
    @State private var selectedCategoryId: String?
    @State private var errorMessage: String?

    // New category sheet
    @State private var showingAddCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryKeyword: String = ""
    @State private var newCategoryIcon: String = "globe"
    @State private var newCategoryHint: String = ""

    // New source sheet
    @State private var showingAddSource: Bool = false
    @State private var newSourceName: String = ""
    @State private var newSourceURL: String = ""
    @State private var newSourceHint: String = ""
    @State private var newSourceNotes: String = ""

    // Test result
    @State private var showingTestResult: Bool = false
    @State private var testResultText: String = ""
    @State private var isTesting: Bool = false

    private var dataService: SwiftDataService {
        SwiftDataService(modelContext: modelContext)
    }

    private var selectedCategory: WebToolCategory? {
        categories.first { $0.categoryId == selectedCategoryId }
    }

    var body: some View {
        NavigationSplitView {
            categoryList
        } detail: {
            if let category = selectedCategory {
                categoryDetail(category)
            } else {
                ContentUnavailableView(
                    "Select a Category",
                    systemImage: "globe",
                    description: Text("Choose a web tool category to view and edit its sources.")
                )
            }
        }
        .navigationTitle("Web Tools")
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 450)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        #endif
        .onAppear { loadCategories() }
        .alert("Add Category", isPresented: $showingAddCategory) {
            TextField("Name (e.g., Weather)", text: $newCategoryName)
            TextField("Keyword (e.g., weather)", text: $newCategoryKeyword)
            TextField("SF Symbol (e.g., sun.max)", text: $newCategoryIcon)
            TextField("Extraction hint", text: $newCategoryHint)
            Button("Cancel", role: .cancel) { clearNewCategoryFields() }
            Button("Add") { addCategory() }
                .disabled(newCategoryName.isEmpty || newCategoryKeyword.isEmpty)
        } message: {
            Text("Create a new web tool category.")
        }
        .alert("Add Source", isPresented: $showingAddSource) {
            TextField("Name (e.g., NWS Forecast)", text: $newSourceName)
            TextField("URL pattern", text: $newSourceURL)
            TextField("Extraction hint (optional)", text: $newSourceHint)
            TextField("Notes (optional)", text: $newSourceNotes)
            Button("Cancel", role: .cancel) { clearNewSourceFields() }
            Button("Add") { addSource() }
                .disabled(newSourceName.isEmpty || newSourceURL.isEmpty)
        } message: {
            Text("Add a web source to this category.\nUse {placeholders} in the URL for dynamic values.")
        }
        .sheet(isPresented: $showingTestResult) {
            testResultSheet
        }
    }

    // MARK: - Category List (Sidebar)

    private var categoryList: some View {
        VStack(spacing: 0) {
            if categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "globe",
                    description: Text("Add a category to get started.")
                )
            } else {
                List(selection: $selectedCategoryId) {
                    ForEach(categories, id: \.categoryId) { category in
                        HStack(spacing: 8) {
                            Image(systemName: category.iconName)
                                .frame(width: 20)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.body)
                                Text(category.keyword)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !category.isEnabled {
                                Text("OFF")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(Capsule())
                            }

                            Text("\(category.safeSources.filter { $0.isEnabled }.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(category.categoryId)
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCategory(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)

                Spacer()
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
    }

    // MARK: - Category Detail (Main Area)

    private func categoryDetail(_ category: WebToolCategory) -> some View {
        VStack(spacing: 0) {
            // Category properties header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: category.iconName)
                        .font(.title)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Keyword: \(category.keyword)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Enabled", isOn: Binding(
                        get: { category.isEnabled },
                        set: { newValue in
                            category.isEnabled = newValue
                            saveContext()
                        }
                    ))
                    .toggleStyle(.switch)
                }

                if !category.extractionHint.isEmpty {
                    Text(category.extractionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()

            Divider()

            // Sources list
            if category.safeSources.isEmpty {
                ContentUnavailableView(
                    "No Sources",
                    systemImage: "link",
                    description: Text("Add a web source to this category.")
                )
            } else {
                List {
                    ForEach(sortedSources(for: category), id: \.sourceId) { source in
                        sourceRow(source, in: category)
                    }
                    .onMove { from, to in
                        moveSources(in: category, from: from, to: to)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    showingAddSource = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Drag to reorder priority")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
        }
    }

    // MARK: - Source Row

    private func sourceRow(_ source: WebToolSource, in category: WebToolCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Priority badge
                Text("\(source.priority)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(source.isEnabled ? Color.blue : Color.gray)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(source.urlPattern)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { source.isEnabled },
                    set: { newValue in
                        source.isEnabled = newValue
                        saveContext()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Button {
                    testSource(source)
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.circle")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isTesting)
                .help("Test this source")
            }

            if !source.notes.isEmpty {
                Text(source.notes)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteSource(source)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Test Result Sheet

    private var testResultSheet: some View {
        NavigationStack {
            ScrollView {
                Text(testResultText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Source Test Result")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingTestResult = false }
                }
            }
            .frame(minWidth: 500, minHeight: 300)
            #else
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingTestResult = false }
                }
            }
            #endif
        }
    }

    // MARK: - Data Operations

    private func loadCategories() {
        do {
            categories = try dataService.loadWebToolCategories()
            // Auto-select first if none selected
            if selectedCategoryId == nil, let first = categories.first {
                selectedCategoryId = first.categoryId
            }
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func sortedSources(for category: WebToolCategory) -> [WebToolSource] {
        category.safeSources.sorted { $0.priority < $1.priority }
    }

    private func addCategory() {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeyword = newCategoryKeyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let icon = newCategoryIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = newCategoryHint.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedKeyword.isEmpty else { return }

        do {
            let nextOrder = categories.count
            try dataService.createWebToolCategory(
                name: trimmedName,
                keyword: trimmedKeyword,
                extractionHint: hint,
                iconName: icon.isEmpty ? "globe" : icon,
                displayOrder: nextOrder
            )
            clearNewCategoryFields()
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCategory(_ category: WebToolCategory) {
        do {
            try dataService.deleteWebToolCategory(category.categoryId)
            if selectedCategoryId == category.categoryId {
                selectedCategoryId = nil
            }
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSource() {
        guard let categoryId = selectedCategoryId else { return }

        let trimmedName = newSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = newSourceHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = newSourceNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }

        // Next priority = current count + 1
        let nextPriority = (selectedCategory?.safeSources.count ?? 0) + 1

        do {
            try dataService.addWebToolSource(
                toCategoryId: categoryId,
                name: trimmedName,
                urlPattern: trimmedURL,
                extractionHint: hint,
                priority: nextPriority,
                notes: notes
            )
            clearNewSourceFields()
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSource(_ source: WebToolSource) {
        do {
            try dataService.deleteWebToolSource(source.sourceId)
            loadCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveSources(in category: WebToolCategory, from: IndexSet, to: Int) {
        var sorted = sortedSources(for: category)
        sorted.move(fromOffsets: from, toOffset: to)

        // Reassign priorities based on new order
        for (index, source) in sorted.enumerated() {
            source.priority = index + 1
        }
        saveContext()
        loadCategories()
    }

    private func testSource(_ source: WebToolSource) {
        isTesting = true

        // Use sample parameters for testing
        let sampleParams: [String: String] = [
            "lat": "39.2720",
            "lon": "-76.7319",
            "city": "Catonsville",
            "state": "MD",
            "zip": "21228",
            "query": "test"
        ]

        Task {
            let resolvedURL = WebFetchService.resolveURL(
                pattern: source.urlPattern,
                parameters: sampleParams
            ) ?? source.urlPattern

            let result = await WebFetchService.fetch(url: resolvedURL)

            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let content, let url):
                    testResultText = "✅ Success\nURL: \(url)\nLength: \(content.count) chars\n\n--- Content ---\n\n\(content)"
                case .failure(let reason, let url):
                    testResultText = "❌ Failed\nURL: \(url)\nReason: \(reason)"
                }
                showingTestResult = true
            }
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func clearNewCategoryFields() {
        newCategoryName = ""
        newCategoryKeyword = ""
        newCategoryIcon = "globe"
        newCategoryHint = ""
    }

    private func clearNewSourceFields() {
        newSourceName = ""
        newSourceURL = ""
        newSourceHint = ""
        newSourceNotes = ""
    }
}

#Preview {
    WebToolManagerView()
}

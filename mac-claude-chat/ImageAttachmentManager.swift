//
//  ImageAttachmentManager.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition.
//  Handles image attachment processing: paste, drag/drop, file import.
//  No UI state — returns results for the caller to apply.
//

import Foundation
import UniformTypeIdentifiers

enum ImageAttachmentManager {

    // MARK: - Image Processing

    /// Process raw image data into a PendingImage ready for attachment.
    /// Delegates to ImageProcessor for downscaling and base64 encoding.
    ///
    /// - Parameter data: Raw image data (PNG, JPEG, etc.)
    /// - Returns: A PendingImage with processed base64 data and thumbnail, or nil on failure.
    static func processForAttachment(_ data: Data) -> PendingImage? {
        guard let processed = ImageProcessor.process(data) else {
            print("Failed to process image")
            return nil
        }

        // Create thumbnail for preview (use original data if small enough, otherwise use processed)
        let thumbnailData = data.count < 100_000 ? data : Data(base64Encoded: processed.base64Data) ?? data

        return PendingImage(
            id: processed.id,
            base64Data: processed.base64Data,
            mediaType: processed.mediaType,
            thumbnailData: thumbnailData
        )
    }

    // MARK: - Drag and Drop

    /// Process drag-and-drop providers for image data.
    /// Handles both file URL drops (Finder) and raw image data drops.
    /// Calls `onImageData` on the main thread for each successfully loaded image.
    ///
    /// - Parameters:
    ///   - providers: NSItemProviders from the drop event.
    ///   - onImageData: Callback invoked on the main thread with raw image data for each image.
    static func processDropProviders(_ providers: [NSItemProvider], onImageData: @escaping (Data) -> Void) {
        for provider in providers {
            // Try file URL first (most common for Finder drops)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {
                        print("Drop: Failed to load URL - \(error?.localizedDescription ?? "unknown")")
                        return
                    }

                    // Check if it's an image file
                    guard let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                          let uti = UTType(typeIdentifier),
                          uti.conforms(to: .image) else {
                        print("Drop: Not an image file")
                        return
                    }

                    // Read the image data
                    guard let imageData = try? Data(contentsOf: url) else {
                        print("Drop: Failed to read image data from \(url)")
                        return
                    }

                    DispatchQueue.main.async {
                        onImageData(imageData)
                    }
                }
            }
            // Fallback: try to load as raw image data
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data {
                        DispatchQueue.main.async {
                            onImageData(data)
                        }
                    }
                }
            }
        }
    }

    // MARK: - File Import

    /// Process a file importer result for image data.
    /// Handles security-scoped URL access for sandboxed apps.
    /// Calls `onImageData` for each successfully loaded image file.
    ///
    /// - Parameters:
    ///   - result: The Result from SwiftUI's `.fileImporter`.
    ///   - onImageData: Callback invoked with raw image data for each image.
    static func processFileImport(_ result: Result<[URL], Error>, onImageData: (Data) -> Void) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                if let imageData = try? Data(contentsOf: url) {
                    onImageData(imageData)
                }
            }
        case .failure(let error):
            print("File import error: \(error)")
        }
    }
}

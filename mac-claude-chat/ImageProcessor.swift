//
//  ImageProcessor.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 3 decomposition
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Image Processing

/// Utility for processing images before sending to Claude API
/// Downscales to 1024px max edge and encodes as JPEG base64
enum ImageProcessor {

    /// Result of processing an image
    struct ProcessedImage {
        let id: UUID
        let base64Data: String
        let mediaType: String  // Always "image/jpeg"
    }

    /// Process platform image data into base64 JPEG
    /// - Parameter imageData: Raw image data (PNG, JPEG, etc.)
    /// - Returns: ProcessedImage with base64 data, or nil if processing fails
    static func process(_ imageData: Data) -> ProcessedImage? {
        #if os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return processNSImage(nsImage)
        #else
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return processUIImage(uiImage)
        #endif
    }

    #if os(macOS)
    /// Process NSImage (macOS)
    static func processNSImage(_ image: NSImage) -> ProcessedImage? {
        // Get the actual pixel dimensions from the image rep
        guard let bitmapRep = image.representations.first else { return nil }
        let pixelWidth = CGFloat(bitmapRep.pixelsWide)
        let pixelHeight = CGFloat(bitmapRep.pixelsHigh)

        // Calculate scale to fit within 1024px on the long edge
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / max(pixelWidth, pixelHeight), 1.0)
        let newWidth = pixelWidth * scale
        let newHeight = pixelHeight * scale

        // Create scaled image
        let newSize = NSSize(width: newWidth, height: newHeight)
        let scaledImage = NSImage(size: newSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: NSSize(width: pixelWidth, height: pixelHeight)),
                   operation: .copy,
                   fraction: 1.0)
        scaledImage.unlockFocus()

        // Convert to JPEG data
        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }

        let base64 = jpegData.base64EncodedString()
        return ProcessedImage(id: UUID(), base64Data: base64, mediaType: "image/jpeg")
    }
    #endif

    #if os(iOS)
    /// Process UIImage (iOS)
    static func processUIImage(_ image: UIImage) -> ProcessedImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale

        // Calculate scale to fit within 1024px on the long edge
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / max(pixelWidth, pixelHeight), 1.0)
        let newWidth = pixelWidth * scale
        let newHeight = pixelHeight * scale

        // Create scaled image
        let newSize = CGSize(width: newWidth, height: newHeight)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaledImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Convert to JPEG data
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.7) else {
            return nil
        }

        let base64 = jpegData.base64EncodedString()
        return ProcessedImage(id: UUID(), base64Data: base64, mediaType: "image/jpeg")
    }
    #endif
}

/// Pending image attachment waiting to be sent
struct PendingImage: Identifiable {
    let id: UUID
    let base64Data: String
    let mediaType: String
    let thumbnailData: Data  // For preview display

    #if os(macOS)
    var thumbnailImage: NSImage? {
        NSImage(data: thumbnailData)
    }
    #else
    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailData)
    }
    #endif
}

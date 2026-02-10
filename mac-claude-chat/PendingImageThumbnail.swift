//
//  PendingImageThumbnail.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - Pending Image Thumbnail View

struct PendingImageThumbnail: View {
    let pending: PendingImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            #if os(macOS)
            if let image = pending.thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #else
            if let image = pending.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
}

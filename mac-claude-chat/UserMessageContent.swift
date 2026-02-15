//
//  UserMessageContent.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - User Message Content View

struct UserMessageContent: View {
    let images: [(id: String, mediaType: String, base64Data: String)]
    let text: String
    @Binding var expandedImageId: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Render images if present
            if !images.isEmpty {
                HStack(spacing: 8) {
                    ForEach(images, id: \.id) { imageData in
                        MessageImageView(
                            base64Data: imageData.base64Data,
                            isExpanded: expandedImageId == imageData.id,
                            onTap: {
                                if expandedImageId == imageData.id {
                                    expandedImageId = nil
                                } else {
                                    expandedImageId = imageData.id
                                }
                            }
                        )
                    }
                }
            }

            // Render text if present
            if !text.isEmpty {
                Text(text)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
    }
}

//
//  MessageImageView.swift
//  mac-claude-chat
//
//  Extracted from ContentView.swift — Phase 2 decomposition
//

import SwiftUI

// MARK: - Message Image View

struct MessageImageView: View {
    let base64Data: String
    let isExpanded: Bool
    let onTap: () -> Void

    #if os(macOS)
    private var image: NSImage? {
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return NSImage(data: data)
    }
    #else
    private var image: UIImage? {
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return UIImage(data: data)
    }
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                    .frame(
                        maxWidth: isExpanded ? 600 : 200,
                        maxHeight: isExpanded ? 500 : 150
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(perform: onTap)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            #else
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                    .frame(
                        maxWidth: isExpanded ? 600 : 200,
                        maxHeight: isExpanded ? 500 : 150
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(perform: onTap)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            #endif
        }
    }
}

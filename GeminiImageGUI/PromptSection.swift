// PromptSection.swift
import SwiftUI

struct PromptSection: View {
    @Binding var prompt: String
    @Binding var isUnsafe: Bool
    
    @Binding var platformTextView: (any PlatformTextView)?  // Changed to @Binding to receive from parent
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground).opacity(0.5)
        #elseif os(macOS)
        Color(nsColor: .textBackgroundColor).opacity(0.5)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 16) {
            CustomTextEditor(text: $prompt, platformTextView: $platformTextView)
                .frame(minHeight: 120)
                .background(backgroundColor)
                .cornerRadius(12)
                .overlay {
                    if prompt.isEmpty {
                        Text("Enter your prompt for image generation here...")
                            .foregroundColor(.secondary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .font(.system(size: 16, weight: .regular, design: .default))  // Applies if needed; font set in representable
            
            if isUnsafe {
                Text("Warning: Prompt may contain inappropriate content.")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}


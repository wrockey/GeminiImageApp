//PromptSection.swift
import SwiftUI

struct PromptSection: View {
    @Binding var prompt: String
    
    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $prompt)
                .frame(minHeight: 120)  // Slightly reduced for compactness
                .background(Color(.systemBackground).opacity(0.5))
                .cornerRadius(12)  // Softer corners
                .overlay {
                    if prompt.isEmpty {
                        Text("Enter your image generation prompt here...")
                            .foregroundColor(.secondary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .font(.system(size: 16, weight: .regular, design: .default))
        }
    }
    
}

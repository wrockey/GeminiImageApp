//PromptSection.swift
import SwiftUI

struct PromptSection: View {
    @Binding var prompt: String
    
    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $prompt)
                .frame(minHeight: 150)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .font(.system(.body, design: .default))
                .autocorrectionDisabled()
        }
    }
}

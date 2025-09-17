import SwiftUI

struct PromptSection: View {
    @Binding var prompt: String
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground).opacity(0.5)
        #elseif os(macOS)
        Color(nsColor: .textBackgroundColor).opacity(0.5)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 16) {
            TextEditor(text: $prompt)
                .frame(minHeight: 120)  // Slightly reduced for compactness
                .background(backgroundColor)
                .cornerRadius(12)  // Softer corners
                .overlay {
                    if prompt.isEmpty {
                        Text("Enter your prompt for image generation here...")
                            .foregroundColor(.secondary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .font(.system(size: 16, weight: .regular, design: .default))
        }
    }
}

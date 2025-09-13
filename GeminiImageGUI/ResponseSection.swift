// ResponseSection.swift
import SwiftUI

struct ResponseSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var imageScale: CGFloat
    @Binding var showFullImage: Bool
    @Binding var errorMessage: String?
    @Binding var showErrorAlert: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @State private var finalScale: CGFloat = 1.0
    @State private var showCopiedOverlay: Bool = false
    @State private var textHeight: CGFloat = 60  // Initial height for ~3 lines (adjust based on font)
    
    var body: some View {
        VStack(spacing: 16) {  // Changed to VStack for vertical layout
            imageContent
            textContent
        }
        .frame(minHeight: 250)  // Slightly taller min height for balance
        .padding(16)  // Outer padding for section spacing
        .cornerRadius(16)
        .onChange(of: appState.ui.responseText) { newText in
            // Dynamically adjust textHeight based on content (approximate)
            let lineHeight: CGFloat = 20  // Approximate line height for .body font
            let lineCount = newText.split(separator: "\n").count
            textHeight = max(60, CGFloat(lineCount) * lineHeight + 20)  // +padding
        }
        .onChange(of: appState.ui.outputImage) { _ in
            finalScale = 1.0
            imageScale = 1.0
        }
    }
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray  // Fallback for macOS
        #endif
    }
    
    private var secondaryBackgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray  // Fallback for macOS
        #endif
    }
    
    private var systemBackgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)  // macOS equivalent
        #endif
    }
    
    private var secondarySystemBackgroundColor: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)  // macOS equivalent
        #endif
    }
    
    @ViewBuilder
    private var imageContent: some View {
        if let platformImage = appState.ui.outputImage {
            VStack(spacing: 12) {  // Changed to VStack for buttons below image
                Image(platformImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(imageScale)
                    .cornerRadius(16)  // Softer corners
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)  // Enhanced shadow for pop
                    .gesture(MagnificationGesture()
                        .onChanged { value in
                            imageScale = finalScale * value
                        }
                        .onEnded { value in
                            finalScale *= value
                            imageScale = finalScale
                        }
                    )
                    .overlay(
                        Group {
                            if showCopiedOverlay {
                                Text("Copied to Clipboard")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                    .transition(.opacity)
                            }
                        }
                    )
                
                HStack(spacing: 12) {  // HStack for buttons below image
                    Button("View") {
                        showFullImage = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    
                    Button("Copy") {
                        PlatformPasteboard.clearContents()
                        PlatformPasteboard.writeImage(platformImage)
                        withAnimation {
                            showCopiedOverlay = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopiedOverlay = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    
                    Button("Save As...") {
                        saveImageAs(image: platformImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)  // Internal padding for cleanliness
        } else {
            VStack {
                Text("No image generated.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private var textContent: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $appState.ui.responseText)
                .font(.system(.body))  // Standard readable font
                .foregroundColor(.primary)  // High contrast
                .background(secondarySystemBackgroundColor)  // Softer background
                .cornerRadius(12)
                .shadow(radius: 2)  // Subtle shadow for depth
                .disabled(true)
        }
        .frame(maxWidth: .infinity, idealHeight: textHeight, maxHeight: .infinity)  // Dynamic height starting small
    }
    
    private func saveImageAs(image: PlatformImage) {
        // Platform-abstracted save panel (macOS-specific for now)
#if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated_image.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = image.platformTiffRepresentation(), let bitmap = NSBitmapImageRep(data: data), let pngData = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try pngData.write(to: url)
                } catch {
                    errorMessage = "Failed to save image: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
#elseif os(iOS)
        // iOS share sheet for saving to Photos/Files
        guard let pngData = image.pngData() else {
            errorMessage = "Failed to prepare image for saving."
            showErrorAlert = true
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [pngData], applicationActivities: nil)
        
        // Fix popover source for iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityVC.popoverPresentationController?.sourceView = UIApplication.shared.windows.first?.rootViewController?.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            activityVC.popoverPresentationController?.permittedArrowDirections = []
        }
        
        if let topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            topVC.present(activityVC, animated: true)
        } else {
            errorMessage = "Unable to present save dialog."
            showErrorAlert = true
        }
#endif
    }
}

// ResponseSection.swift
import SwiftUI

struct ResponseSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var imageScale: CGFloat
    @Binding var showFullImage: Bool
    @Binding var errorMessage: String?
    @Binding var showErrorAlert: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @State private var textWidth: CGFloat = 300  // Fixed width for text; adjust as needed
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 16) {  // Added spacing instead of 0 for natural separation
                imageContent
                textContent
            }
        }
        .frame(minHeight: 250)  // Slightly taller min height for balance
        .padding(16)  // Outer padding for section spacing
        .background(backgroundColor.opacity(0.5))  // Very light backdrop to separate from others
        .cornerRadius(16)
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
            HStack(spacing: 12) {  // HStack for image + vertical buttons
                GeometryReader { imageGeo in
                    let fitScale = min(imageGeo.size.width / platformImage.platformSize.width, imageGeo.size.height / platformImage.platformSize.height)
                    ScrollView {
                        Image(platformImage: platformImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: platformImage.platformSize.width * fitScale * imageScale, height: platformImage.platformSize.height * fitScale * imageScale)
                            .cornerRadius(16)  // Softer corners
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)  // Enhanced shadow for pop
                            .gesture(MagnificationGesture()
                                .onChanged { value in
                                    imageScale = value
                                }
                                .onEnded { _ in
                                }
                            )
                    }
                }
                .frame(maxHeight: 600)  // Taller for larger previews
                .background(secondaryBackgroundColor.opacity(0.8))  // Lighter material for image backdrop
                .cornerRadius(16)
                
                VStack(spacing: 12) {  // Vertical stack for buttons
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
            .background(systemBackgroundColor.opacity(0.95))  // Subtle card effect
            .cornerRadius(16)
            .shadow(radius: 4)
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
        .frame(width: textWidth)
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

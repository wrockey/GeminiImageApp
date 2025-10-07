//ResponseSection.swift
import SwiftUI
 
struct ResponseSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var imageScale: CGFloat
    @Binding var errorItem: AlertError?
    @Environment(\.colorScheme) var colorScheme
   
    @State private var finalScale: CGFloat = 1.0
    @State private var showCopiedOverlay: Bool = false
    @State private var showDeleteAlert: Bool = false
   
    var body: some View {
        VStack(spacing: 16) {  // Changed to VStack for vertical layout
            imageContent
            textContent
        }
        .frame(minHeight: 250)  // Slightly taller min height for balance
        .padding(16)  // Outer padding for section spacing
        .cornerRadius(16)
        .onChange(of: appState.ui.outputImages) { _ in
            finalScale = 1.0
            imageScale = 1.0
        }
        .alert("Delete Response", isPresented: $showDeleteAlert) {
            Button("Delete from History Only") {
                deleteCurrentImage(deleteFile: false)
            }
            Button("Delete from History and File", role: .destructive) {
                deleteCurrentImage(deleteFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to delete the image from history only or also delete the file?")
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
        let count = appState.ui.outputImages.count
        let index = appState.ui.currentOutputIndex
        if count > 0, let optionalImage = appState.ui.outputImages[safe: index], let platformImage = optionalImage {
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
                    .help("Generated image. Pinch to zoom.")
                    .accessibilityLabel("Generated image")
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
                                    .help("Confirmation that the image was copied to the clipboard")
                                    .accessibilityLabel("Image copied to clipboard")
                            }
                        }
                    )
           
                // +++ NEW: Navigation if multiples
                if count > 1 {
                    HStack(spacing: 12) {
                        Button {
                            if index > 0 { appState.ui.currentOutputIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(index == 0)
                        .buttonStyle(.bordered)
                        .tint(.blue)
           
                        Text("\(index + 1) of \(count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
           
                        Button {
                            if index < count - 1 { appState.ui.currentOutputIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(index == count - 1)
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .help("Navigate between generated images")
                    .accessibilityLabel("Image navigation")
                }
           
                HStack(spacing: 12) {  // HStack for buttons below image
                    Button {
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
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .help("Copy the image to the clipboard")
                    .accessibilityLabel("Copy image")
           
                    Button {
                        saveImageAs(image: platformImage)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .help("Save the image to a file")
                    .accessibilityLabel("Save image as")
           
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .help("Delete the response")
                    .accessibilityLabel("Delete response")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)  // Internal padding for cleanliness
        } else {
            VStack {
                Text("No image generated.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("No image has been generated yet")
                    .accessibilityLabel("No image generated")
            }
            .frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder
    private var textContent: some View {
        let index = appState.ui.currentOutputIndex
        let text = appState.ui.outputTexts[safe: index] ?? ""
        if text.isEmpty {
            Rectangle()
                .fill(secondarySystemBackgroundColor)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)  // Small initial height (decreased by ~75% from typical 60)
                .cornerRadius(12)
                .shadow(radius: 2)
                .help("Placeholder for response text")
                .accessibilityLabel("No response text")
        } else {
            Text(text)
                .font(.system(.body))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(secondarySystemBackgroundColor)
                .cornerRadius(12)
                .shadow(radius: 2)
                .help("Generated text response")
                .accessibilityLabel("Response text: \(text)")
        }
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
                    errorItem = AlertError(message: "Failed to save image: \(error.localizedDescription)", fullMessage: nil)
                }
            }
        }
#elseif os(iOS)
        // iOS share sheet for saving to Photos/Files
        guard let pngData = image.pngData() else {
            errorItem = AlertError(message: "Failed to prepare image for saving.", fullMessage: nil)
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
            errorItem = AlertError(message: "Unable to present save dialog.", fullMessage: nil)
        }
#endif
    }
   
    // NEW: Delete handler for current image
    private func deleteCurrentImage(deleteFile: Bool) {
        let index = appState.ui.currentOutputIndex
        if index < appState.ui.outputImages.count, let path = appState.ui.outputPaths[safe: index] {
            // Delete file if chosen
            if deleteFile, let fileURL = path.flatMap({ URL(fileURLWithPath: $0) }) {
                let fileManager = FileManager.default
                if let dir = appState.settings.outputDirectory {
                    do {
                        try withSecureAccess(to: dir) {
                            try fileManager.removeItem(at: fileURL)
                        }
                    } catch { /* log error */ }
                }
            }
           
            // Find and remove matching history item
            _ = appState.historyState.findAndRemoveEntry(matching: { $0.imagePath == path })
        }
   
        // Remove from UI arrays
        appState.ui.outputImages.remove(at: index)
        appState.ui.outputTexts.remove(at: index)
        appState.ui.outputPaths.remove(at: index)
   
        // Adjust index
        if !appState.ui.outputImages.isEmpty {
            appState.ui.currentOutputIndex = min(index, appState.ui.outputImages.count - 1)
        } else {
            appState.ui.currentOutputIndex = 0
        }
    }
}






import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

struct ResponseSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var imageScale: CGFloat
    @Binding var errorItem: AlertError?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) private var undoManager
    
    @Binding var showUndoButton: Bool
    
    @State private var finalScale: CGFloat = 1.0
    @State private var showCopiedOverlay: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // Default aspect ratio
    @State private var isVideoPlayable: Bool = false // Track video playability
    
    var body: some View {
        VStack(spacing: 16) {
            imageContent
            textContent
        }
        .frame(minHeight: 250)
        .padding(16)
        .cornerRadius(16)
        .onChange(of: appState.ui.outputImages) { _ in
            finalScale = 1.0
            imageScale = 1.0
        }
        .onChange(of: appState.ui.outputPaths) { _ in
            // Load aspect ratio for the current video when outputPaths changes
            Task {
                await loadVideoAspectRatio()
            }
        }
        .onAppear {
            // Initial load of aspect ratio for the current video
            Task {
                await loadVideoAspectRatio()
            }
        }
        .sheet(isPresented: $showDeleteAlert) {
            DeleteConfirmationView(
                title: "Delete Response",
                message: deleteMessage,
                hasDeletableFiles: hasFile && fileExists,
                deleteAction: { deleteFiles in
                    deleteCurrentImage(deleteFile: deleteFiles)
                },
                cancelAction: {}
            )
        }
        #if os(macOS)
        .overlay(
            Group {
                if #available(macOS 14.0, *) {
                    if fileExists {
                        Color.clear.dialogSeverity(.critical)
                    }
                }
            }
            .dialogIcon(Image(systemName: "trash"))
        )
        #endif
    }
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray
        #endif
    }
    
    private var secondaryBackgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray
        #endif
    }
    
    private var systemBackgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    private var secondarySystemBackgroundColor: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    @ViewBuilder
    private var imageContent: some View {
        let count = appState.ui.outputImages.count
        let index = appState.ui.currentOutputIndex
        if let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, !path.isEmpty, path.hasSuffix(".mp4") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                if isVideoPlayable {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(maxWidth: .infinity, idealHeight: 300, maxHeight: 400)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .help("Generated video. Use playback controls to play, pause, or seek.")
                        .accessibilityLabel("Generated video with playback controls")
                } else {
                    Text("Video file is corrupted or unplayable.")
                        .font(.system(.body, weight: .medium))
                        .foregroundColor(.secondary)
                        .help("Video file is invalid or corrupted")
                        .accessibilityLabel("Corrupted video")
                }
            } else {
                Text("Video file not found.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("Video file is missing or inaccessible")
                    .accessibilityLabel("Video not found")
            }
            
            // Warn if multiple videos (unexpected for AIML API)
            if count > 1 && appState.ui.outputPaths.contains(where: { $0?.hasSuffix(".mp4") ?? false }) {
                Text("Warning: Multiple videos detected. AIML API typically returns one video.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                    .help("Unexpected multiple video outputs")
                    .accessibilityLabel("Multiple video warning")
            }
            
            // Navigation controls for multiple outputs
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
                .help("Navigate between generated outputs")
                .accessibilityLabel("Output navigation")
            }
            
            // Action buttons for video
            HStack(spacing: 12) {
                Button {
                    saveMediaAs(path: path)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .cornerRadius(10)
                .shadow(radius: 2)
                .help("Save the video to a file")
                .accessibilityLabel("Save video as")
                
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
        } else if count > 0, let optionalImage = appState.ui.outputImages[safe: index], let platformImage = optionalImage {
            // Image case
            VStack(spacing: 12) {
                Image(platformImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(imageScale)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
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
                
                // Navigation controls for multiple outputs
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
                
                // Action buttons for image
                HStack(spacing: 12) {
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
            .padding(12)
        } else {
            // No media case
            VStack {
                Text("No media generated.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("No image or video has been generated yet")
                    .accessibilityLabel("No media generated")
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
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
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
    
    private var hasFile: Bool {
        let index = appState.ui.currentOutputIndex
        return appState.ui.outputPaths[safe: index] != nil
    }
    
    private var fileExists: Bool {
        let index = appState.ui.currentOutputIndex
        guard let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, !path.isEmpty else {
            return false
        }
        let url = URL(fileURLWithPath: path)
        var exists = false
        if let dir = appState.settings.outputDirectory {
            if dir.startAccessingSecurityScopedResource() {
                exists = FileManager.default.fileExists(atPath: url.path)
                dir.stopAccessingSecurityScopedResource()
            }
        } else {
            exists = FileManager.default.fileExists(atPath: url.path)
        }
        return exists
    }
    
    private var deleteMessage: String {
        var msg = "Are you sure you want to delete this response from history?"
        if hasFile && !fileExists {
            msg += "\nNote: File is missing or inaccessible."
        }
        return msg
    }
    
    private func loadVideoAspectRatio() async {
        let index = appState.ui.currentOutputIndex
        guard let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, !path.isEmpty, path.hasSuffix(".mp4") else {
            videoAspectRatio = 16.0 / 9.0 // Default if not a video
            isVideoPlayable = false
            return
        }
        
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            videoAspectRatio = 16.0 / 9.0
            isVideoPlayable = false
            return
        }
        
        let asset = AVAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let size = try await tracks.first?.load(.naturalSize) ?? CGSize(width: 16, height: 9)
            videoAspectRatio = size.width / size.height
            isVideoPlayable = asset.isPlayable
        } catch {
            videoAspectRatio = 16.0 / 9.0 // Fallback
            isVideoPlayable = false
        }
    }
    
    private func saveImageAs(image: PlatformImage) {
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
        guard let pngData = image.pngData() else {
            errorItem = AlertError(message: "Failed to prepare image for saving.", fullMessage: nil)
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [pngData], applicationActivities: nil)
        
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
    
    private func saveMediaAs(path: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "generated_video.mp4"
        
        if panel.runModal() == .OK, let url = panel.url {
            let fileManager = FileManager.default
            do {
                try fileManager.copyItem(at: URL(fileURLWithPath: path), to: url)
            } catch {
                errorItem = AlertError(message: "Failed to save video: \(error.localizedDescription)", fullMessage: nil)
            }
        }
        #elseif os(iOS)
        let url = URL(fileURLWithPath: path)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
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
    
    private func deleteCurrentImage(deleteFile: Bool) {
        let index = appState.ui.currentOutputIndex
        if index < appState.ui.outputImages.count, let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath {
            // Store state for undo
            let image = appState.ui.outputImages[safe: index]
            let text = appState.ui.outputTexts[safe: index]
            let oldHistory = appState.historyState.history
            let historyEntryRemoved = appState.historyState.findAndRemoveEntry(matching: { $0.imagePath == path })
            
            print("Deleting image at index \(index), path: \(path), history entry removed: \(historyEntryRemoved)")
            print("History before deletion: \(appState.historyState.history.map { $0.id })")
            
            // Register undo action
            if let undoManager = undoManager {
                let oldImages = appState.ui.outputImages
                let oldTexts = appState.ui.outputTexts
                let oldPaths = appState.ui.outputPaths
                let oldIndex = appState.ui.currentOutputIndex
                
                undoManager.registerUndo(withTarget: appState) { target in
                    print("Undoing delete: Restoring history with \(oldHistory.count) entries: \(oldHistory.map { $0.id })")
                    // Restore UI state
                    target.ui.outputImages = oldImages
                    target.ui.outputTexts = oldTexts
                    target.ui.outputPaths = oldPaths
                    target.ui.currentOutputIndex = oldIndex
                    
                    // Restore history state
                    target.historyState.history = oldHistory
                    target.historyState.saveHistory()
                    target.historyState.objectWillChange.send()
                    target.ui.objectWillChange.send()
                    
                    print("History after undo: \(target.historyState.history.map { $0.id })")
                    
                    // Register redo action
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        let redoIndex = redoTarget.ui.currentOutputIndex
                        if redoIndex < redoTarget.ui.outputImages.count, let redoOptionalPath = redoTarget.ui.outputPaths[safe: redoIndex], let redoPath = redoOptionalPath {
                            // Redo file deletion if applicable
                            if deleteFile {
                                let fileURL = URL(fileURLWithPath: redoPath)
                                let fileManager = FileManager.default
                                if let dir = redoTarget.settings.outputDirectory {
                                    do {
                                        try withSecureAccess(to: dir) {
                                            try fileManager.removeItem(at: fileURL)
                                        }
                                    } catch {
                                        print("Redo: Failed to delete file: \(error)")
                                    }
                                }
                            }
                            
                            // Redo history entry removal
                            _ = redoTarget.historyState.findAndRemoveEntry(matching: { $0.imagePath == redoPath })
                            
                            // Redo UI array removals
                            redoTarget.ui.outputImages.remove(at: redoIndex)
                            redoTarget.ui.outputTexts.remove(at: redoIndex)
                            redoTarget.ui.outputPaths.remove(at: redoIndex)
                            
                            // Adjust index for redo
                            if !redoTarget.ui.outputImages.isEmpty {
                                redoTarget.ui.currentOutputIndex = min(redoIndex, redoTarget.ui.outputImages.count - 1)
                            } else {
                                redoTarget.ui.currentOutputIndex = 0
                            }
                            
                            redoTarget.ui.objectWillChange.send()
                            redoTarget.historyState.saveHistory()
                            redoTarget.historyState.objectWillChange.send()
                            print("Redo: History after deletion: \(redoTarget.historyState.history.map { $0.id })")
                        }
                    }
                    undoManager.setActionName("Delete Response")
                }
            }
            
            // Delete file if chosen
            if deleteFile {
                let fileURL = URL(fileURLWithPath: path)
                let fileManager = FileManager.default
                if let dir = appState.settings.outputDirectory {
                    do {
                        try withSecureAccess(to: dir) {
                            try fileManager.removeItem(at: fileURL)
                        }
                    } catch {
                        print("Failed to delete file: \(error)")
                    }
                }
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
            
            // Show undo button
            withAnimation {
                showUndoButton = true
            }
            
            appState.ui.objectWillChange.send()
            appState.historyState.saveHistory()
            appState.historyState.objectWillChange.send()
            print("History after deletion: \(appState.historyState.history.map { $0.id })")
        }
    }
}

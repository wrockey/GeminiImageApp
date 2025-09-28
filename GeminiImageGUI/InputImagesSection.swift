import SwiftUI
import ImageIO  // For PNG metadata extraction
import UniformTypeIdentifiers  // Added for UTType on macOS
import PhotosUI  // Added for PHPicker on iOS
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// Moved out: Overload parsePromptNodes for Data
func parsePromptNodes(from data: Data) -> [NodeInfo] {
    print("DEBUG: Parsing prompts from pasted PNG data, size: \(data.count)")
    
    var offset: Int = 8  // Skip PNG signature
    let totalLength = data.count
    var workflowStr: String? = nil
    
    while offset + 11 < totalLength {
        let lengthRange = offset..<(offset + 4)
        let lengthData = data.subdata(in: lengthRange)
        let lengthBytes = [UInt8](lengthData)
        let length = (UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) |
                    (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3])
        
        let fullChunkSize = 12 + Int(length)
        let fullChunkEnd = offset + fullChunkSize
        guard fullChunkEnd <= totalLength else { break }
        
        let typeStart = offset + 4
        let typeRange = typeStart..<(typeStart + 4)
        let typeData = data.subdata(in: typeRange)
        let typeBytes = [UInt8](typeData)
        let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""
        
        if chunkType == "tEXt" {
            let textStart = typeStart + 4
            let textRange = textStart ..< (textStart + Int(length))
            let textData = data.subdata(in: textRange)
            if let textStr = String(data: textData, encoding: .utf8),
               let nullIndex = textStr.firstIndex(of: "\0") {
                let keyword = String(textStr[..<nullIndex]).trimmingCharacters(in: .whitespaces)
                if ["workflow", "prompt", "Workflow", "Prompt"].contains(keyword) {
                    let valueStart = textStr.index(after: nullIndex)
                    workflowStr = String(textStr[valueStart...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        
        offset = fullChunkEnd
    }
    
    // Fallback to ImageIO if manual didn't find it
    if workflowStr == nil {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return parsePromptNodes(from: tempURL)  // Reuse file version
        } catch {
            print("DEBUG: Temp file for ImageIO failed: \(error)")
            return []
        }
    }
    
    guard let extractedWorkflowStr = workflowStr else { return [] }
    
    guard let jsonData = extractedWorkflowStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return [] }
    
    var promptNodes: [NodeInfo] = []
    
    if let nodesArray = json["nodes"] as? [[String: Any]] {
        for node in nodesArray {
            guard let nodeID = node["id"] as? Int,
                  let classType = node["type"] as? String else { continue }
            let nodeIDStr = String(nodeID)
            
            if classType.contains("CLIPTextEncode") {
                let widgetsValues = node["widgets_values"] as? [Any] ?? []
                let text = widgetsValues.compactMap { $0 as? String }.first ?? ""
                let label = text.isEmpty ? "Node \(nodeIDStr)" : "Node \(nodeIDStr): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: text))
            }
        }
    } else {
        for (nodeID, node) in json {
            guard let nodeDict = node as? [String: Any],
                  let classType = nodeDict["class_type"] as? String else { continue }
            
            if classType.contains("CLIPTextEncode") {
                let text = (nodeDict["inputs"] as? [String: Any])?["text"] as? String ?? ""
                let label = text.isEmpty ? "Node \(nodeID)" : "Node \(nodeID): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: text))
            }
        }
    }
    
    return promptNodes.sorted { $0.id < $1.id }
}

// Moved out: Overload parsePromptNodes for URL
func parsePromptNodes(from url: URL) -> [NodeInfo] {
    print("DEBUG: Parsing prompts from PNG: \(url.path)")
    
    // Manual PNG chunk parsing to extract tEXt
    guard let data = try? Data(contentsOf: url) else {
        print("DEBUG: Failed to load PNG binary data")
        return []
    }
    print("DEBUG: PNG binary loaded, size: \(data.count) bytes")
    
    var offset: Int = 8  // Skip PNG signature (first 8 bytes)
    let totalLength = data.count
    var workflowStr: String? = nil
    
    while offset + 11 < totalLength {  // Ensure room for min chunk (12 bytes) + safety
        // Read chunk length (4 bytes, big-endian)
        let lengthRange = offset..<(offset + 4)
        guard lengthRange.upperBound <= totalLength else {
            print("DEBUG: Length range exceeds file; breaking at offset \(offset)")
            break
        }
        let lengthData = data.subdata(in: lengthRange)
        
        // Safer big-endian UInt32 read (manual shift for reliability)
        let lengthBytes = [UInt8](lengthData)
        let length = (UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) |
        (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3])
        
        // DEBUG: Log length bytes (remove after fix)
        print("DEBUG: Length bytes at offset \(offset): [\(lengthBytes.map { String(format: "%02x", $0) }.joined(separator: " "))], length: \(length)")
        
        let fullChunkSize = 12 + Int(length)  // 4 len + 4 type + len data + 4 CRC
        let fullChunkEnd = offset + fullChunkSize
        guard fullChunkEnd <= totalLength else {
            print("DEBUG: Full chunk end \(fullChunkEnd) > total \(totalLength); skipping invalid chunk at offset \(offset)")
            break
        }
        
        let typeStart = offset + 4
        let typeRange = typeStart..<(typeStart + 4)
        guard typeRange.upperBound <= totalLength else {
            print("DEBUG: Type range exceeds; breaking")
            break
        }
        let typeData = data.subdata(in: typeRange)
        let typeBytes = [UInt8](typeData)
        let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""
        
        // DEBUG: Log type bytes (remove after fix)
        print("DEBUG: Type bytes: [\(typeBytes.map { String(format: "%02x", $0) }.joined(separator: " "))], chunk: \(chunkType) length: \(length)")
        
        // For tEXt chunk: keyword\0value
        if chunkType == "tEXt" {
            let textStart = typeStart + 4  // After type
            let textRange = textStart ..< (textStart + Int(length))
            guard textRange.lowerBound < textRange.upperBound else {
                offset = fullChunkEnd
                continue
            }
            let textData = data.subdata(in: textRange)
            if let textStr = String(data: textData, encoding: .utf8),
               let nullIndex = textStr.firstIndex(of: "\0") {
                let keyword = String(textStr[..<nullIndex]).trimmingCharacters(in: .whitespaces)
                if ["workflow", "prompt", "Workflow", "Prompt"].contains(keyword) {
                    let valueStart = textStr.index(after: nullIndex)
                    workflowStr = String(textStr[valueStart...]).trimmingCharacters(in: .whitespaces)
                    print("DEBUG: Found \(keyword) in tEXt chunk: \(workflowStr!.prefix(100))...")
                    break  // Found it
                }
            }
        }
        // For zTXt: Skip for now (ComfyUI uses tEXt; add decompression if logs show zTXt)
        else if chunkType == "zTXt" {
            print("DEBUG: zTXt chunk found at offset \(offset), length \(length); skipping (decompression needed?)")
        }
        
        // Advance to next chunk
        offset = fullChunkEnd
        // DEBUG: (remove after fix)
        print("DEBUG: Advanced to next offset: \(offset)")
    }
    
    // Fallback to ImageIO if manual didn't find it
    if workflowStr == nil {
        print("DEBUG: No tEXt chunks found; falling back to ImageIO")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? NSDictionary,
              let pngDict = props["{PNG}"] as? NSDictionary else {
            print("DEBUG: ImageIO fallback failed - no {PNG} dict")
            return []
        }
        print("DEBUG: ImageIO PNG dict keys: \(pngDict.allKeys)")
        
        let fallbackStr: String? = pngDict["workflow"] as? String ?? pngDict["prompt"] as? String ?? pngDict["Workflow"] as? String ?? pngDict["Prompt"] as? String ?? nil
        workflowStr = fallbackStr
        if let ws = workflowStr {
            print("DEBUG: Found via ImageIO: \(ws.prefix(100))...")
        } else {
            print("DEBUG: No workflow/prompt keys in ImageIO. Available keys: \(pngDict.allKeys)")
            return []
        }
    }
    
    guard let extractedWorkflowStr = workflowStr else {
        print("DEBUG: No workflow string extracted after all methods")
        return []
    }
    print("DEBUG: Workflow string length: \(extractedWorkflowStr.count)")
    print("DEBUG: Using workflow str: \(extractedWorkflowStr.prefix(100))...")
    
    // Parse JSON
    guard let jsonData = extractedWorkflowStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        print("DEBUG: Failed to parse JSON. Raw preview: \(extractedWorkflowStr.prefix(200))")
        return []
    }
    print("DEBUG: JSON parsed. Top-level keys: \(Array(json.keys).sorted())")
    
    var promptNodes: [NodeInfo] = []
    
    // Full workflow: "nodes" array
    if let nodesArray = json["nodes"] as? [[String: Any]] {
        print("DEBUG: Full workflow - \(nodesArray.count) nodes")
        for node in nodesArray {
            guard let nodeID = node["id"] as? Int,
                  let classType = node["type"] as? String else { continue }
            let nodeIDStr = String(nodeID)
            
            if classType.contains("CLIPTextEncode") {
                let widgetsValues = node["widgets_values"] as? [Any] ?? []
                let text = widgetsValues.compactMap { $0 as? String }.first ?? ""
                let label = text.isEmpty ? "Node \(nodeIDStr)" : "Node \(nodeIDStr): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: text))
                print("DEBUG: Added node \(nodeIDStr): \(label)")
            }
        }
    } else {
        // Flat "prompt" dict (API format)
        print("DEBUG: Flat prompt dict mode")
        for (nodeID, node) in json {
            guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
            
            if classType.contains("CLIPTextEncode") {
                let text = (nodeDict["inputs"] as? [String: Any])?["text"] as? String ?? ""
                let label = text.isEmpty ? "Node \(nodeID)" : "Node \(nodeID): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: text))
            }
        }
    }
    
    let result = promptNodes.sorted { $0.id < $1.id }
    print("DEBUG: Total prompt nodes: \(result.count)")
    return result
}

struct InputImagesSection: View {
    @Binding var imageSlots: [ImageSlot]
    @Binding var errorItem: AlertError?
    let onAnnotate: (UUID) -> Void
    @EnvironmentObject var appState: AppState
    
    @State private var showCopiedMessage: Bool = false
    @State private var showClearConfirmation: Bool = false
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemGray5)
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
    
    var body: some View {
        if appState.settings.mode == .grok {
            Text("Input images not supported in Grok mode.")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Input images not supported in Grok mode")
        } else {
            ZStack {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        Button(action: addImageSlot) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))  // Larger for touch
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)  // Cleaner look
                        .shadow(radius: 2)
                        .help("Add a new image slot") // Tooltip
                        .accessibilityLabel("Add image slot")
                        .accessibilityHint("Adds a new slot for uploading or pasting an image.")
    
                        Button(action: { showClearConfirmation = true }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .shadow(radius: 2)
                        .help("Remove all image slots") // Tooltip
                        .accessibilityLabel("Clear all images")
                        .accessibilityHint("Removes all loaded images and slots.")
                    }
                    
                    if imageSlots.isEmpty {
                        Text("Add images for reference (optional)")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .accessibilityLabel("Add images for reference (optional)")
                    } else {
                        ForEach($imageSlots) { $slot in
                            ImageSlotItemView(
                                slot: $slot,
                                errorItem: $errorItem,
                                onAnnotate: onAnnotate,
                                onRemove: removeImageSlot,
                                showCopiedMessage: $showCopiedMessage,
                                backgroundColor: backgroundColor,
                                systemBackgroundColor: systemBackgroundColor
                            )
                        }
                    }
                }
                
                if showCopiedMessage {
                    Text("Copied to Clipboard")
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .transition(.opacity)
                        .accessibilityLabel("Copied to Clipboard")
                        .accessibilityHint("The prompt text has been copied.")
                }
            }
            .alert("Confirm Removal", isPresented: $showClearConfirmation) {
                Button("Yes", role: .destructive) { clearImageSlots() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to remove all input image slots?")
            }
        }
    }

    private func addImageSlot() {
        imageSlots.append(ImageSlot())
    }
    
    private func clearImageSlots() {
        imageSlots.removeAll()
    }
    
    private func removeImageSlot(_ id: UUID) {
        if let index = imageSlots.firstIndex(where: { $0.id == id }) {
            imageSlots.remove(at: index)
        }
    }
    
    // New: Cross-platform clipboard copy (moved earlier for clarity)
    private func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }
}

struct ImageSlotItemView: View {
    @Binding var slot: ImageSlot
    @Binding var errorItem: AlertError?
    let onAnnotate: (UUID) -> Void
    let onRemove: (UUID) -> Void  // Added for remove
    @Binding var showCopiedMessage: Bool
    let backgroundColor: Color
    let systemBackgroundColor: Color
    
    @State private var isDropTargeted: Bool = false  // Added for drop highlight
    @State private var showPicker: Bool = false  // Added for PHPicker

    @Environment(\.horizontalSizeClass) private var sizeClass  // Added: Detect compact (iPhone) vs regular (iPad)
    
    var body: some View {
        Group {
            if sizeClass == .compact {
                // Vertical layout for iPhone (compact): Thumbnail above, icons below
                VStack(alignment: .leading, spacing: 12) {
                    thumbnailView
                    
                    slotDetailsAndButtons
                    
                    if !slot.promptNodes.isEmpty {
                        promptNodesView
                    }
                    
                    removeButton
                }
            } else {
                // Horizontal layout for iPad (regular): Keep original
                HStack(spacing: 16) {
                    thumbnailView
                    
                    slotDetailsAndButtons
                    
                    if !slot.promptNodes.isEmpty {
                        promptNodesView
                    }
                    
                    removeButton
                }
            }
        }
        .padding(16)
        .cornerRadius(16)  // Card style for each slot
        .shadow(color: .black.opacity(0.1), radius: 2)  // Softer shadow
        .sheet(isPresented: $showPicker) {
#if os(iOS)
            PHPickerWrapper { result in
                handlePickerResult(result)
            }
#endif
        }
    }
    
    // Extracted: Thumbnail view (smaller on compact)
    private var thumbnailView: some View {
        ZStack {
            if let img = slot.image {
                Image(platformImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: sizeClass == .compact ? 100 : 150, height: sizeClass == .compact ? 100 : 150)  // Smaller on iPhone
                    .cornerRadius(16)
                    .shadow(radius: 4)
                    .accessibilityLabel("Loaded image")
                    .accessibilityHint("Preview of the selected or pasted image.")
            } else {
                Rectangle()
                    .fill(backgroundColor)
                    .frame(width: sizeClass == .compact ? 100 : 150, height: sizeClass == .compact ? 100 : 150)
                    .cornerRadius(16)
                    .shadow(radius: 4)
                    .accessibilityLabel("Empty image slot")
                    .accessibilityHint("No image loaded yet. Use browse or paste to add one.")
            }
            
            // Highlight border for drop target
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: sizeClass == .compact ? 100 : 150, height: sizeClass == .compact ? 100 : 150)
            }
        }
        #if os(macOS)
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        #endif
    }
    
    // Extracted: Path text and action buttons (browse, paste, annotate)
    private var slotDetailsAndButtons: some View {
        VStack(alignment: .leading, spacing: 12) {  // More spacing
            Text(slot.path.isEmpty ? "No image selected" : {
#if os(iOS)
                return URL(fileURLWithPath: slot.path).lastPathComponent
#else
                return slot.path
#endif
            }())
            .font(.system(.body, weight: .medium))
            .foregroundColor(.primary)
            .accessibilityLabel("Image path")
            .accessibilityValue(slot.path.isEmpty ? "No image selected" : slot.path)
            
            HStack {
                Button {
                    showImageOpenPanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .cornerRadius(10)
                .shadow(radius: 2)
                .help("Browse for an image file") // Tooltip
                .accessibilityLabel("Browse")
                .accessibilityHint("Opens file picker to select an image.")
                
                Button {
                    pasteImage()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .cornerRadius(10)
                .shadow(radius: 2)
                .help("Paste image from clipboard") // Tooltip
                .accessibilityLabel("Paste")
                .accessibilityHint("Pastes an image from the clipboard into this slot.")
                
                #if os(iOS)
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .cornerRadius(10)
                .shadow(radius: 2)
                .help("Add from Photos") // Tooltip
                .accessibilityLabel("Add from Photos")
                .accessibilityHint("Opens photo picker to select an image from your library.")
                #endif
                
                #if os(iOS)
                // Show annotate button only on iPad (not iPhone)
                if sizeClass != .compact || UIDevice.current.userInterfaceIdiom != .phone {
                    Button {
                        if slot.image != nil {
                            print("DEBUG: Annotate tapped for slot \(slot.id), image exists: true")
                            onAnnotate(slot.id)
                        } else {
                            print("DEBUG: Annotate tapped but no image in slot \(slot.id)")
                            errorItem = AlertError(message: "No image loaded to annotate.")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .help("Annotate the loaded image") // Tooltip
                    .accessibilityLabel("Annotate")
                    .accessibilityHint("Opens annotation tool for the loaded image.")
                }
                #elseif os(macOS)
                Button {
                    if slot.image != nil {
                        print("DEBUG: Annotate tapped for slot \(slot.id), image exists: true")
                        onAnnotate(slot.id)
                    } else {
                        print("DEBUG: Annotate tapped but no image in slot \(slot.id)")
                        errorItem = AlertError(message: "No image loaded to annotate.")
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .cornerRadius(10)
                .shadow(radius: 2)
                .help("Annotate the loaded image") // Tooltip
                .accessibilityLabel("Annotate")
                .accessibilityHint("Opens annotation tool for the loaded image.")
                #endif
            }
        }
    }
    
    // Extracted: Prompt nodes picker and copy button
    private var promptNodesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embedded Workflow Prompts")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityLabel("Embedded Workflow Prompts")
            
            Menu {
                ForEach(0..<slot.promptNodes.count, id: \.self) { index in
                    Button {
                        slot.selectedPromptIndex = index
                    } label: {
                        Text(slot.promptNodes[index].label)
                            .font(.caption)
                    }
                }
            } label: {
                Text(slot.promptNodes[slot.selectedPromptIndex].label)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.blue)
            }
            .help("Select a prompt from the embedded workflow")
            .accessibilityLabel("Select Prompt")
            .accessibilityHint("Choose a prompt node from the list.")
            
            Button {
                let selectedText = slot.promptNodes[slot.selectedPromptIndex].promptText ?? ""
                copyToClipboard(selectedText)
                withAnimation {
                    showCopiedMessage = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCopiedMessage = false
                    }
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .cornerRadius(10)
            .shadow(radius: 2)
            .help("Copy selected prompt to clipboard") // Tooltip
            .accessibilityLabel("Copy Prompt")
            .accessibilityHint("Copies the selected prompt text to the clipboard.")
        }
    }
    
    // Extracted: Remove button
    private var removeButton: some View {
        Button(action: { onRemove(slot.id) }) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .shadow(radius: 2)
        .help("Remove this image slot") // Tooltip
        .accessibilityLabel("Remove image slot")
        .accessibilityHint("Removes this image and its slot.")
    }
    
    private func showImageOpenPanel() {
        PlatformFilePicker.presentOpenPanel(allowedTypes: [.image], allowsMultiple: false, canChooseDirectories: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImageFromURL(url)
            case .failure(let error):
                errorItem = AlertError(message: "Failed to select image: \(error.localizedDescription)")
            }
        }
    }
    
    // Added: Handle PHPicker result on iOS
    private func handlePickerResult(_ result: PHPickerResult?) {
        guard let result = result else { return }
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorItem = AlertError(message: "Failed to load image: \(error.localizedDescription)")
                }
                return
            }
            guard let data = data else { return }
            guard let platformImage = PlatformImage(data: data) else { return }
            DispatchQueue.main.async {
                self.slot.image = platformImage
                self.slot.path = "Selected from Photos"
                
                var origData: Data? = nil
                // Extract prompts if PNG (check signature and parse from original data)
                if isPNGData(data) {
                    origData = data
                    let promptNodes = parsePromptNodes(from: data)
                    if !promptNodes.isEmpty {
                        self.slot.promptNodes = promptNodes.sorted { $0.id < $1.id }
                        self.slot.selectedPromptIndex = 0
                    }
                }
                self.slot.originalData = origData
            }
        }
    }
    
    private func pasteImage() {
        var pngData: Data? = nil
        var image: PlatformImage? = nil
        
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) {
            pngData = data
            image = PlatformImage(data: data)
        } else if let data = pasteboard.data(forType: .tiff), let nsImg = NSImage(data: data) {
            image = nsImg
        } else if let nsImg = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            image = nsImg
            pngData = nsImg.tiffRepresentation  // Attempt to get PNG data if possible
        }
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        if let data = pasteboard.data(forPasteboardType: "public.png") {
            pngData = data
            image = PlatformImage(data: data)
        } else if let uiImg = pasteboard.image {
            image = uiImg
            pngData = uiImg.pngData()  // Fallback, but may lose metadata
        }
        #endif
        
        guard let pastedImage = image else {
            errorItem = AlertError(message: "No image data in clipboard")
            return
        }
        
        slot.image = pastedImage
        slot.path = "Pasted from Clipboard"
        
        var origData: Data? = nil
        var promptNodes: [NodeInfo] = []
        if let data = pngData, isPNGData(data) {
            origData = data
            promptNodes = parsePromptNodes(from: data)
        }
        
        slot.originalData = origData
        
        if !promptNodes.isEmpty {
            slot.promptNodes = promptNodes.sorted { $0.id < $1.id }
            slot.selectedPromptIndex = 0
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
    
    // New: Handle drop (macOS only)
#if os(macOS)
private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }
    
    // First, try loading as URL (for file drags)
    provider.loadObject(ofClass: URL.self) { reading, error in
        if let url = reading as? URL, error == nil {
            DispatchQueue.main.async {
                self.loadImageFromURL(url)
            }
            return
        }
        
        // Fallback: Load as raw image data (for direct image drags, e.g., from Photos or browsers)
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorItem = AlertError(message: "Drop error: \(error.localizedDescription)")
                }
                return
            }
            
            guard let data = data else { return }
            
            guard let nsImage = NSImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self.slot.image = nsImage
                self.slot.path = "Dropped Image"
                
                var origData: Data? = nil
                // Attempt to extract prompts if PNG (check signature and parse from original data)
                if isPNGData(data) {
                    origData = data
                    let promptNodes = parsePromptNodes(from: data)
                    if !promptNodes.isEmpty {
                        self.slot.promptNodes = promptNodes.sorted { $0.id < $1.id }
                        self.slot.selectedPromptIndex = 0
                    }
                }
                self.slot.originalData = origData
            }
        }
    }
    
    return true
}
#endif
    private func loadImageFromURL(_ url: URL) {
        do {
            let (image, promptNodes, originalData) = try withSecureAccess(to: url) {
                var img: PlatformImage? = nil
                var nodes: [NodeInfo] = []
                var origData: Data? = nil
                if url.pathExtension.lowercased() == "png" {
                    let data = try Data(contentsOf: url)
                    origData = data
                    nodes = parsePromptNodes(from: data)
                    img = PlatformImage(data: data)
                } else {
                    img = PlatformImage(contentsOf: url)
                }
                return (img, nodes, origData)
            }
            
            if let img = image {
                slot.image = img
                slot.path = url.path
                slot.originalData = originalData
                
                if !promptNodes.isEmpty {
                    slot.promptNodes = promptNodes.sorted { $0.id < $1.id }
                    slot.selectedPromptIndex = 0
                }
            } else {
                errorItem = AlertError(message: "Failed to load image.")
            }
        } catch {
            errorItem = AlertError(message: "Failed to access image: \(error.localizedDescription)")
        }
    }
    

}

// Added: Wrapper for PHPickerViewController
#if os(iOS)
struct PHPickerWrapper: UIViewControllerRepresentable {
    let onCompletion: (PHPickerResult?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1  // Single selection
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper
        
        init(_ parent: PHPickerWrapper) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            parent.onCompletion(results.first)
        }
    }
}
#endif

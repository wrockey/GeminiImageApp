//GeminiImageApp.swift
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import PencilKit
#endif
 
enum GenerationMode: String, Codable {
    case gemini
    case comfyUI
}
 
// Updated NodeInfo struct (make promptText optional to accommodate non-prompt nodes)
struct NodeInfo: Identifiable {
    let id: String
    let label: String
    let promptText: String?  // Optional: only set for prompt nodes
}
 
class SettingsState: ObservableObject {
    @Published var apiKey: String = ""
    @Published var outputDirectory: URL? = nil
    @Published var apiKeyFileURL: URL? = nil
    @Published var mode: GenerationMode = .gemini
    @AppStorage("comfyServerURL") var comfyServerURL: String = "http://localhost:8188"
    @Published var comfyJSONURL: URL? = nil
    @Published var comfyJSONPath: String = ""
}
 
class GenerationState: ObservableObject {
    @Published var comfyWorkflow: [String: Any]? = nil
    @Published var comfyPromptNodeID: String = ""
    @Published var comfyPromptKey: String = "text"
    @Published var comfyImageNodeID: String = ""
    @Published var comfyImageKey: String = "image"
    @Published var comfyOutputNodeID: String = ""
    @Published var promptNodes: [NodeInfo] = []
    @Published var outputNodes: [NodeInfo] = []
    @Published var imageNodes: [NodeInfo] = []
    @Published var workflowError: String? = nil
    
    func loadWorkflowFromFile(comfyJSONURL: URL?) {
        guard let url = comfyJSONURL else {
            resetNodes(withError: "No URL provided.")
            return
        }
        
        // Resolve bookmark if available (handles stale cases)
        var targetURL = url
        if let bookmarkData = UserDefaults.standard.data(forKey: "comfyJSONBookmark") {
            var isStale = false
            do {
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                targetURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    #if os(macOS)
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                    #else
                    let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                    #endif
                    if let newBookmark = try? targetURL.bookmarkData(options: bookmarkOptions) {
                        UserDefaults.standard.set(newBookmark, forKey: "comfyJSONBookmark")
                    }
                }
            } catch {
                resetNodes(withError: "Bookmark resolution error: \(error.localizedDescription)")
                return
            }
        }
        
        // Use coordinator for safe access
        var coordError: NSError?
        var innerError: Error?
        var json: [String: Any]?
        
        NSFileCoordinator().coordinate(readingItemAt: targetURL, options: [], error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                
                do {
                    let ext = coordinatedURL.pathExtension.lowercased()
                    if ext == "json" {
                        let data = try Data(contentsOf: coordinatedURL)
                        json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    } else if ext == "png" {
                        if let workflowStr = self.extractWorkflowFromPNG(url: coordinatedURL) {
                            if let data = workflowStr.data(using: .utf8) {
                                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                            } else {
                                innerError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                            }
                        } else {
                            innerError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                        }
                    } else {
                        innerError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type. Please select a JSON or PNG file."])
                    }
                } catch {
                    innerError = error
                }
            } else {
                innerError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
            }
        }
        
        if let coordError = coordError {
            resetNodes(withError: "Coordination error: \(coordError.localizedDescription)")
            return
        }
        if let innerError = innerError {
            resetNodes(withError: "Failed to load or parse workflow: \(innerError.localizedDescription)")
            return
        }
        guard let json = json else {
            resetNodes(withError: "Failed to load or parse workflow.")
            return
        }
        
        processJSON(json: json)
        
        // Save/refresh bookmark if needed (already handled in resolution above)
    }
    
    func extractWorkflowFromPNG(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
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
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? NSDictionary,
                  let pngDict = props["{PNG}"] as? NSDictionary else { return nil }
            
            workflowStr = pngDict["workflow"] as? String ?? pngDict["prompt"] as? String ?? pngDict["Workflow"] as? String ?? pngDict["Prompt"] as? String
        }
        
        return workflowStr
    }
    
    // Updated processJSON function (full corrected version with promptText: text for prompts, nil for others)
    private func processJSON(json: [String: Any]) {
        var promptNodes: [NodeInfo] = []
        var outputNodes: [NodeInfo] = []
        var imageNodes: [NodeInfo] = []
        
        if let nodesArray = json["nodes"] as? [[String: Any]] {
            for node in nodesArray {
                guard let nodeID = node["id"] as? Int, let classType = node["type"] as? String else { continue }
                let nodeIDStr = String(nodeID)
                
                if classType == "CLIPTextEncode" {
                    let text = (node["widgets_values"] as? [Any])?.first(where: { $0 is String }) as? String ?? ""
                    let label = text.isEmpty ? "Node \(nodeIDStr)" : "Node \(nodeIDStr): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                    promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: text))
                } else if ["SaveImage", "PreviewImage"].contains(classType) {
                    let label = "Node \(nodeIDStr): \(classType)"
                    outputNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: nil))
                } else if classType == "LoadImage" {
                    let label = "Node \(nodeIDStr): \(classType)"
                    imageNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: nil))
                }
            }
        } else {
            for (nodeID, node) in json {
                guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                
                if classType == "CLIPTextEncode" {
                    let text = (nodeDict["inputs"] as? [String: Any])?["text"] as? String ?? ""
                    let label = text.isEmpty ? "Node \(nodeID)" : "Node \(nodeID): \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                    promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: text))
                } else if ["SaveImage", "PreviewImage"].contains(classType) {
                    let label = "Node \(nodeID): \(classType)"
                    outputNodes.append(NodeInfo(id: nodeID, label: label, promptText: nil))
                } else if classType == "LoadImage" {
                    let label = "Node \(nodeID): \(classType)"
                    imageNodes.append(NodeInfo(id: nodeID, label: label, promptText: nil))
                }
            }
        }
        
        if promptNodes.isEmpty && outputNodes.isEmpty && imageNodes.isEmpty {
            workflowError = "Invalid workflow format or no relevant nodes found. Please load a valid ComfyUI JSON (API or standard format)."
            self.promptNodes = []
            self.outputNodes = []
            self.imageNodes = []
            return
        }
        
        self.promptNodes = promptNodes.sorted { $0.id < $1.id }
        self.outputNodes = outputNodes.sorted { $0.id < $1.id }
        self.imageNodes = imageNodes.sorted { $0.id < $1.id }
        
        comfyPromptNodeID = promptNodes.first?.id ?? ""
        comfyOutputNodeID = outputNodes.first?.id ?? ""
        comfyImageNodeID = imageNodes.first?.id ?? ""
        workflowError = nil
    }
    private func resetNodes(withError error: String) {
        promptNodes = []
        outputNodes = []
        imageNodes = []
        workflowError = error
    }
}
 
class HistoryState: ObservableObject {
    @Published var history: [HistoryItem] = []
    
    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "history"),
           let loadedHistory = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = loadedHistory
        }
    }
    
    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "history")
        }
    }
}
 
class UIState: ObservableObject {
    @Published var imageSlots: [ImageSlot] = []
    @Published var responseText: String = ""
    @Published var outputImage: PlatformImage? = nil
}
 
class AppState: ObservableObject {
    @Published var settings = SettingsState()
    @Published var generation = GenerationState()
    @Published var historyState = HistoryState()
    @Published var ui = UIState()
    @Published var prompt: String = ""
    
    #if os(iOS)
    @Published var showFullHistoryItem: UUID? = nil
    @Published var showMarkupSlotId: UUID? = nil
    @Published var showResponseSheet: Bool = false
    #endif
    
    @Published var batchPrompts: [String] = []
    @Published var batchFileURL: URL? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    @objc func setPrompt(_ newPrompt: String) {
        self.prompt = newPrompt
    }
    
    init() {
        settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        generation.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        historyState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        ui.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
 
struct ImageSlot: Identifiable {
    let id = UUID()
    var path: String = ""
    var image: PlatformImage? = nil
    var promptNodes: [NodeInfo] = []
    var selectedPromptIndex: Int = 0
}
 
struct HistoryItem: Identifiable, Codable {
    let id = UUID()
    let prompt: String
    let responseText: String
    let imagePath: String?
    let date: Date
    let mode: GenerationMode?
    let workflowName: String?
}
 
struct Part: Codable {
    let text: String?
    let inlineData: InlineData?
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
    
    init(text: String? = nil, inlineData: InlineData? = nil) {
        self.text = text
        self.inlineData = inlineData
    }
}
 
struct InlineData: Codable {
    let mimeType: String
    let data: String
    
    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}
 
struct Content: Codable {
    let parts: [Part]
}
 
struct GenerateContentRequest: Codable {
    let contents: [Content]
}
 
struct GenerateContentResponse: Codable {
    let candidates: [Candidate]
}
 
struct Candidate: Codable {
    let content: ResponseContent
}
 
struct ResponseContent: Codable {
    let parts: [ResponsePart]
}
 
struct ResponsePart: Codable {
    let text: String?
    let inlineData: InlineData?
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
    }
}
 
struct ResponseInlineData: Codable {
    let mimeType: String
    let data: String
    
    enum CodingKeys: String, CodingKey {
        case mimeType
        case data
    }
}
 
struct NewResponsePart: Codable {
    let text: String?
    let inlineData: ResponseInlineData?
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}
 
struct NewResponseContent: Codable {
    let parts: [NewResponsePart]
}
 
struct NewCandidate: Codable {
    let content: NewResponseContent
}
 
struct NewGenerateContentResponse: Codable {
    let candidates: [NewCandidate]
}
 
@main
struct GeminiImageApp: App {
    let appState = AppState()
    
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        
        WindowGroup(for: UUID.self) { $slotId in
            if let slotId {
                MarkupWindowView(slotId: slotId)
                    .environmentObject(appState)
            }
        }
        
        WindowGroup(id: "history-viewer", for: UUID.self) { $historyId in
            if let historyId {
                FullHistoryItemView(initialId: historyId)
                    .environmentObject(appState)
            }
        }
        .defaultSize(width: 800, height: 600)
        
        Window("Response", id: "response-window") {
            PopOutView()
                .environmentObject(appState)
        }
        .defaultSize(width: 800, height: 600)
        #else
        WindowGroup {
            SplashView()
//            ContentView()
                .environmentObject(appState)
            #if os(iOS)
            .sheet(isPresented: Binding(get: { appState.showResponseSheet }, set: { appState.showResponseSheet = $0 })) {
                PopOutView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: Binding(
                get: { appState.showFullHistoryItem != nil },
                set: { if !$0 { appState.showFullHistoryItem = nil } }
            )) {
                if let id = appState.showFullHistoryItem {
                    FullHistoryItemView(initialId: id)
                        .environmentObject(appState)
                }
            }
            #endif
        }
        #endif
    }
}
 
struct MarkupWindowView: View {
    let slotId: UUID
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if let index = appState.ui.imageSlots.firstIndex(where: { $0.id == slotId }),
           let image = appState.ui.imageSlots[index].image {
            let path = appState.ui.imageSlots[index].path
            let fileURL = URL(fileURLWithPath: path)
            let lastComponent = fileURL.lastPathComponent
            let components = lastComponent.components(separatedBy: ".")
            let baseFileName = components.count > 1 ? components.dropLast().joined(separator: ".") : (lastComponent.isEmpty ? "image" : lastComponent)
            let fileExtension = components.count > 1 ? components.last! : "png"
            MarkupView(image: image, baseFileName: baseFileName, fileExtension: fileExtension) { updatedImage in
                appState.ui.imageSlots[index].image = updatedImage
            }
            .navigationTitle("Annotate Image")
        }
    }
}

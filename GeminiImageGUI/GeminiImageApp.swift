// GeminiImageApp.swift
import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import PencilKit
#endif

enum GenerationMode: String, Codable, CaseIterable {
    case gemini
    case comfyUI
    case grok
    case aimlapi
}

struct NodeInfo: Identifiable {
    let id: String
    let label: String
    let promptText: String?
}

class SettingsState: ObservableObject {
    @Published var apiKey: String = KeychainHelper.loadAPIKey() ?? ""
    @Published var outputDirectory: URL? = nil
    @Published var mode: GenerationMode = .gemini
    @AppStorage("comfyServerURL") var comfyServerURL: String = "http://localhost:8188"
    @Published var comfyJSONURL: URL? = nil
    @Published var comfyJSONPath: String = ""
    @Published var grokApiKey: String = KeychainHelper.loadGrokAPIKey() ?? ""
    @Published var selectedGrokModel: String = "grok-2-image-1212"
    @Published var aimlapiKey: String = KeychainHelper.loadAIMLAPIKey() ?? ""
    @Published var imgbbApiKey: String = KeychainHelper.loadImgBBAPIKey() ?? ""
    @Published var selectedAIMLModel: String = ""
    @Published var selectedImageSize: String = "square_hd"
    @Published var selectedResolutionString : String = "2048x2048"
    @Published var selectedImageHeight : Int = 2048
    @Published var selectedImageWidth : Int = 2048
    @Published var aimlAdvancedParams: ModelParameters = ModelParameters()
    @Published var comfyBatchSize: Int = 1
    var supportsCustomResolution: Bool {
        let supportingModels = [
            "bytedance/seedream-v4-text-to-image",
            "bytedance/seedream-v4-edit",
            "black-forest-labs/flux-pro",
            "black-forest-labs/flux-realism"
        ]
        return supportingModels.contains(selectedAIMLModel)
    }
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
    }
    
    func extractWorkflowFromPNG(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
    
        var offset: Int = 8
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
    
        if workflowStr == nil {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? NSDictionary,
                  let pngDict = props["{PNG}"] as? NSDictionary else { return nil }
    
            workflowStr = pngDict["workflow"] as? String ?? pngDict["prompt"] as? String ?? pngDict["Workflow"] as? String ?? pngDict["Prompt"] as? String
        }
    
        return workflowStr
    }
    
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
    weak var appState: AppState?
    @Published var history: [HistoryEntry] = []
    
    struct FolderOption: Identifiable {
        let id: UUID
        let name: String
        
        func containsAny(ids: Set<UUID>, in entries: [HistoryEntry]) -> Bool {
            func checkSubtree(for folderId: UUID, in subEntries: [HistoryEntry]) -> Bool {
                for entry in subEntries {
                    if ids.contains(entry.id) {
                        return true
                    }
                    if case .folder(let folder) = entry {
                        if checkSubtree(for: folderId, in: folder.children) {
                            return true
                        }
                    }
                }
                return false
            }
            
            for entry in entries {
                if case .folder(let folder) = entry, folder.id == self.id {
                    return checkSubtree(for: self.id, in: folder.children)
                } else if case .folder(let folder) = entry {
                    if containsAny(ids: ids, in: folder.children) {
                        return true
                    }
                }
            }
            return false
        }
    }
    
    func allFolders() -> [FolderOption] {
        var folders: [FolderOption] = []
        func collectFolders(from entries: [HistoryEntry]) {
            for entry in entries {
                if case .folder(let folder) = entry {
                    folders.append(FolderOption(id: folder.id, name: folder.name))
                    collectFolders(from: folder.children)
                }
            }
        }
        collectFolders(from: history)
        return folders.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func moveToFolder(entriesWithIds ids: [UUID], toFolderId: UUID?, undoManager: UndoManager?) -> Bool {
        let oldHistory = history
        var snapshot = history
        var movedEntries: [HistoryEntry] = []
        var skippedCount: Int = 0
        
        // Helper to find the parent folder ID of an entry
        func findParentFolderId(for entryId: UUID, in entries: [HistoryEntry]) -> UUID? {
            for entry in entries {
                if case .folder(let folder) = entry {
                    if folder.children.contains(where: { $0.id == entryId }) {
                        return folder.id
                    }
                    if let nestedParent = findParentFolderId(for: entryId, in: folder.children) {
                        return nestedParent
                    }
                }
            }
            return nil
        }
        
        // Helper to check if targetFolderId is a descendant of entryId
        func isDescendant(entryId: UUID, targetFolderId: UUID, in entries: [HistoryEntry]) -> Bool {
            for entry in entries {
                if case .folder(let folder) = entry {
                    if folder.id == entryId {
                        if folder.children.contains(where: { $0.id == targetFolderId }) {
                            return true
                        }
                        return folder.children.contains { isDescendant(entryId: $0.id, targetFolderId: targetFolderId, in: folder.children) }
                    }
                    if isDescendant(entryId: entryId, targetFolderId: targetFolderId, in: folder.children) {
                        return true
                    }
                }
            }
            return false
        }
        
        // Remove entries, skipping those already in the target folder or invalid moves
        for id in ids {
            if let entry = findAndRemoveEntry(id: id, in: &snapshot) {
                if let targetId = toFolderId {
                    // Check if the entry is already in the target folder
                    let parentId = findParentFolderId(for: id, in: snapshot)
                    if parentId == targetId {
                        skippedCount += 1
                        continue
                    }
                    // For folders, prevent moving into a descendant
                    if case .folder = entry, isDescendant(entryId: id, targetFolderId: targetId, in: snapshot) {
                        skippedCount += 1
                        continue
                    }
                }
                movedEntries.append(entry)
            } else {
                print("Failed to find and remove entry with ID: \(id)")
            }
        }
        
        if movedEntries.isEmpty {
            print("No entries found to move for IDs: \(ids)")
            return false
        }
        
        // Insert into destination
        let insertIndex = toFolderId == nil ? snapshot.count : 0
        if insert(entries: movedEntries, inFolderId: toFolderId, at: insertIndex, into: &snapshot) {
            history = snapshot
            saveHistory()
            let movedCount = movedEntries.count
            let totalAttempted = movedCount + skippedCount
            if skippedCount > 0 {
                print("Moved \(movedCount) of \(totalAttempted) items; \(skippedCount) already in target or invalid")
            }
            if let undoManager {
                let newHistory = history
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move to Folder")
            }
            return true
        } else {
            print("Failed to insert entries into folder ID: \(String(describing: toFolderId))")
            return false
        }
    }
    
    func findAndRemoveEntry(id: UUID, in entries: inout [HistoryEntry]) -> HistoryEntry? {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            return entries.remove(at: index)
        }
        for i in entries.indices {
            if case .folder(var folder) = entries[i] {
                if let removed = findAndRemoveEntry(id: id, in: &folder.children) {
                    entries[i] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }
    
    func insert(entries toInsert: [HistoryEntry], inFolderId: UUID?, at index: Int, into snapshot: inout [HistoryEntry]) -> Bool {
        if let inFolderId = inFolderId {
            for i in snapshot.indices {
                if case .folder(var folder) = snapshot[i], folder.id == inFolderId {
                    folder.children.insert(contentsOf: toInsert, at: min(index, folder.children.count))
                    snapshot[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = snapshot[i] {
                    if insert(entries: toInsert, inFolderId: inFolderId, at: index, into: &folder.children) {
                        snapshot[i] = .folder(folder)
                        return true
                    }
                }
            }
            print("Target folder ID \(inFolderId) not found in snapshot")
            return false
        } else {
            snapshot.insert(contentsOf: toInsert, at: min(index, snapshot.count))
            return true
        }
    }
    
    func move(inFolderId: UUID?, from: IndexSet, to: Int, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    folder.children.move(fromOffsets: from, toOffset: to)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            snapshot.move(fromOffsets: from, toOffset: to)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                let newHistory = history
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move Items")
            }
        }
    }
    
    func moveToTop(entriesWithIds ids: [UUID], inFolderId: UUID?, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    let selectedEntries = ids.compactMap { id in
                        folder.children.firstIndex(where: { $0.id == id }).map { folder.children.remove(at: $0) }
                    }
                    folder.children.insert(contentsOf: selectedEntries.reversed(), at: 0)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            let selectedEntries = ids.compactMap { id in
                snapshot.firstIndex(where: { $0.id == id }).map { snapshot.remove(at: $0) }
            }
            snapshot.insert(contentsOf: selectedEntries.reversed(), at: 0)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                let newHistory = history
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move to Top")
            }
        }
    }
    
    func moveToBottom(entriesWithIds ids: [UUID], inFolderId: UUID?, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    let selectedEntries = ids.compactMap { id in
                        folder.children.firstIndex(where: { $0.id == id }).map { folder.children.remove(at: $0) }
                    }
                    folder.children.append(contentsOf: selectedEntries)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            let selectedEntries = ids.compactMap { id in
                snapshot.firstIndex(where: { $0.id == id }).map { snapshot.remove(at: $0) }
            }
            snapshot.append(contentsOf: selectedEntries)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                let newHistory = history
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move to Bottom")
            }
        }
    }
    
    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "history") {
            do {
                let loaded = try JSONDecoder().decode([HistoryEntry].self, from: data)
                history = loaded
            } catch {
                if let loadedOld = try? JSONDecoder().decode([HistoryItem].self, from: data) {
                    history = loadedOld.map { .item($0) }
                    saveHistory()
                } else {
                    history = []
                }
            }
        } else {
            history = []
        }
    }
    
    func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: "history")
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    func addFolder(undoManager: UndoManager?) {
        let oldHistory = history
        history.append(.folder(Folder()))
        saveHistory()
        if let undoManager {
            let newHistory = history
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Add Folder")
        }
    }
    
    func delete(at offsets: IndexSet, undoManager: UndoManager?) {
        let oldHistory = history
        history.remove(atOffsets: offsets)
        saveHistory()
        if let undoManager {
            let newHistory = history
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Delete Items")
        }
    }
    
    func clearHistory(undoManager: UndoManager?) {
        let oldHistory = history
        history = []
        saveHistory()
        if let undoManager {
            let newHistory = history
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Clear History")
        }
    }
    
    func updateFolderName(with id: UUID, newName: String, undoManager: UndoManager?) {
        let oldHistory = history
        var mutableHistory = history
        func update(in entries: inout [HistoryEntry]) -> Bool {
            if let index = entries.firstIndex(where: { $0.id == id }),
              case .folder(var folder) = entries[index] {
                folder.name = newName
                entries[index] = .folder(folder)
                return true
            }
            for i in entries.indices {
                if case .folder(var folder) = entries[i] {
                    if update(in: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        if update(in: &mutableHistory) {
            history = mutableHistory
            saveHistory()
            if let undoManager {
                let newHistory = history
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Rename Folder")
            }
        }
    }
    
    func findEntries(with ids: Set<UUID>) -> [HistoryEntry] {
        var result: [HistoryEntry] = []
        func collect(from entries: [HistoryEntry]) {
            for entry in entries {
                if ids.contains(entry.id) {
                    result.append(entry)
                }
                if let children = entry.childrenForOutline {
                    collect(from: children)
                }
            }
        }
        collect(from: history)
        return result
    }
    
    private func findAndRemoveEntry(with id: UUID, in entries: inout [HistoryEntry]) -> HistoryEntry? {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            return entries.remove(at: index)
        }
        for i in entries.indices {
            if case .folder(var folder) = entries[i] {
                if let removed = findAndRemoveEntry(with: id, in: &folder.children) {
                    entries[i] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }
    
    func addEntry(_ entry: HistoryEntry, toFolderWithId folderId: UUID) {
        var snapshot = history
        func add(to entries: inout [HistoryEntry]) -> Bool {
            for i in entries.indices {
                if case .folder(var folder) = entries[i], folder.id == folderId {
                    folder.children.append(entry)
                    entries[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = entries[i] {
                    if add(to: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        if add(to: &snapshot) {
            history = snapshot
            saveHistory()
        }
    }
    
    func addEntry(_ entry: HistoryEntry, toFolderWithId folderId: UUID, into snapshot: inout [HistoryEntry]) {
        func add(to entries: inout [HistoryEntry]) -> Bool {
            for i in entries.indices {
                if case .folder(var folder) = entries[i], folder.id == folderId {
                    folder.children.append(entry)
                    entries[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = entries[i] {
                    if add(to: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        if add(to: &snapshot) {
            history = snapshot
            saveHistory()
        }
    }
    
    func findAndRemoveEntry(matching predicate: (HistoryItem) -> Bool) -> Bool {
        func remove(from entries: inout [HistoryEntry]) -> Bool {
            if let index = entries.firstIndex(where: {
                if case .item(let item) = $0 {
                    return predicate(item)
                }
                return false
            }) {
                entries.remove(at: index)
                return true
            }
            for i in entries.indices {
                if case .folder(var folder) = entries[i] {
                    if remove(from: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        var mutableHistory = history
        if remove(from: &mutableHistory) {
            history = mutableHistory
            saveHistory()
            return true
        }
        return false
    }
    
    func deleteEntries(_ entries: [HistoryEntry], deleteFiles: Bool, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        
        if deleteFiles {
            for entry in entries {
                deleteFilesRecursively(entry: entry)
            }
        }
        
        for entry in entries {
            _ = findAndRemoveEntry(id: entry.id, in: &snapshot)
        }
        
        history = snapshot
        saveHistory()
        
        if let undoManager {
            let newHistory = history
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Delete Items")
        }
    }
    
    private func deleteFilesRecursively(entry: HistoryEntry) {
        switch entry {
        case .item(let item):
            guard let path = item.imagePath else { return }
            let fileURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if let dir = appState?.settings.outputDirectory {
                var coordError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: dir, options: .forDeleting, error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            print("Failed to delete file: \(error)")
                        }
                    }
                }
                if let coordError = coordError {
                    print("Coordination error during file delete: \(coordError.localizedDescription)")
                }
            } else {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    print("Failed to delete file: \(error)")
                }
            }
        case .folder(let folder):
            for child in folder.children {
                deleteFilesRecursively(entry: child)
            }
        }
    }
}

class UIState: ObservableObject {
    @Published var imageSlots: [ImageSlot] = []
    @Published var outputImages: [PlatformImage?] = []
    @Published var outputTexts: [String] = []
    @Published var outputPaths: [String?] = []
    @Published var currentOutputIndex: Int = 0
}

class AppState: ObservableObject {
    @Published var settings = SettingsState()
    @Published var generation = GenerationState()
    @Published var historyState = HistoryState()
    @Published var ui = UIState()
    @Published var prompt: String = ""
    var currentAIMLModel: AIMLModel? {
        ModelRegistry.modelFor(id: settings.selectedAIMLModel)
    }
    
    var canAddImages: Bool {
        switch settings.mode {
        case .gemini:
            return true
        case .aimlapi:
            return currentAIMLModel?.isI2I ?? false
        case .comfyUI:
            return true
        case .grok:
            return false
        }
    }
    
    var maxImageSlots: Int {
        switch settings.mode {
        case .gemini:
            return 4
        case .aimlapi:
            return currentAIMLModel?.maxInputImages ?? 0
        case .comfyUI:
            return 1
        case .grok:
            return 0
        }
    }
    
    var preferImgBBForImages: Bool {
        !settings.imgbbApiKey.isEmpty && (currentAIMLModel?.acceptsPublicURL ?? true)
    }
    
    #if os(iOS)
    @Published var showFullHistoryItem: UUID? = nil
    @Published var showMarkupSlotId: UUID? = nil
    @Published var showResponseSheet: Bool = false
    @Published var presentedModal: PresentedModal? = nil
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
        historyState.appState = self
    }
}

struct ImageSlot: Identifiable {
    let id = UUID()
    var path: String = ""
    var image: PlatformImage? = nil
    var promptNodes: [NodeInfo] = []
    var selectedPromptIndex: Int = 0
    var originalData: Data? = nil
}

struct HistoryItem: Identifiable, Codable, Equatable {
    let id = UUID()
    let prompt: String
    let responseText: String
    let imagePath: String?
    let date: Date
    let mode: GenerationMode?
    let workflowName: String?
    let modelUsed: String?
    let batchId: UUID?
    let indexInBatch: Int?
    let totalInBatch: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, prompt, responseText, imagePath, date, mode, workflowName, modelUsed
        case batchId, indexInBatch, totalInBatch
    }
}

enum HistoryEntry: Identifiable, Codable, Equatable {
    case item(HistoryItem)
    case folder(Folder)
    
    var childrenForOutline: [HistoryEntry]? {
        if case .folder(let folder) = self {
            return folder.children
        }
        return nil
    }
    
    var id: UUID {
        switch self {
        case .item(let item): return item.id
        case .folder(let folder): return folder.id
        }
    }
    
    func collectAllIDs(into set: inout Set<UUID>) {
        set.insert(id)
        if case .folder(let folder) = self {
            for child in folder.children {
                child.collectAllIDs(into: &set)
            }
        }
    }
    
    var imageCount: Int {
        switch self {
        case .item:
            return 1
        case .folder(let folder):
            return folder.children.reduce(0) { $0 + $1.imageCount }
        }
    }
    
    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        switch (lhs, rhs) {
        case (.item(let a), .item(let b)):
            return a == b
        case (.folder(let a), .folder(let b)):
            return a == b
        default:
            return false
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, content
    }
    
    private enum EntryType: String, Codable {
        case item, folder
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntryType.self, forKey: .type)
        switch type {
        case .item:
            let item = try container.decode(HistoryItem.self, forKey: .content)
            self = .item(item)
        case .folder:
            let folder = try container.decode(Folder.self, forKey: .content)
            self = .folder(folder)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .item(let item):
            try container.encode(EntryType.item, forKey: .type)
            try container.encode(item, forKey: .content)
        case .folder(let folder):
            try container.encode(EntryType.folder, forKey: .type)
            try container.encode(folder, forKey: .content)
        }
    }
}

struct Folder: Identifiable, Codable, Equatable {
    let id: UUID = UUID()
    var name: String = "New Folder"
    var children: [HistoryEntry] = []
    
    static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.children == rhs.children
    }
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
    let finishReason: String?
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
    let finishReason: String?
}

struct NewGenerateContentResponse: Codable {
    let candidates: [NewCandidate]
    let finishReason: String?
}

@main
struct GeminiImageApp: App {
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @State private var batchFilePath: String = ""
    #if os(macOS)
    @State private var showClearHistoryConfirmation = false
    #endif
    
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
                    Button("Clear", role: .destructive) {
                        appState.historyState.clearHistory(undoManager: NSApp.keyWindow?.undoManager)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all history entries but keep your files intact. Are you sure?")
                }
        }
        .commands {
            CommandMenu("History") {
                Button("Clear History") {
                    showClearHistoryConfirmation = true
                }
                .disabled(appState.historyState.history.isEmpty)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        WindowGroup(id: "text-editor", for: Data.self) { $data in
            TextEditorView(bookmarkData: data, batchFilePath: $batchFilePath)
                .frame(minWidth: 400, minHeight: 300)
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
        
        WindowGroup(id: "response-window") {
            PopOutView()
                .environmentObject(appState)
        }
        .defaultSize(width: 800, height: 600)
        #else
        WindowGroup {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                showSplash = false
                            }
                        }
                    }
            } else {
                ContentView()
                    .environmentObject(appState)
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
            }
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

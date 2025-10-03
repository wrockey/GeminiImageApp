// HistoryTreeNode.swift
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// Move TreeNodeView outside
struct TreeNodeView: View {
    let entry: HistoryEntry
    @State private var isExpanded: Bool = true
    @State private var showRenameAlert: Bool = false
    @State private var newFolderName: String = ""
    @Binding var showDeleteAlert: Bool
    @Binding var entriesToDelete: [HistoryEntry]
    let appState: AppState
    @Binding var selectedIDs: Set<UUID>
    @Binding var searchText: String
    @Binding var activeEntry: HistoryEntry?
    let entryRowProvider: (HistoryEntry) -> AnyView
    let copyPromptProvider: (String) -> Void
    let folderId: UUID?
    @Binding var isEditing: Bool
    @Binding var toastMessage: String?
    @Binding var showToast: Bool
    let addToInputProvider: (HistoryItem) -> Void
    
    init(
        entry: HistoryEntry,
        showDeleteAlert: Binding<Bool>,
        entriesToDelete: Binding<[HistoryEntry]>,
        appState: AppState,
        selectedIDs: Binding<Set<UUID>>,
        searchText: Binding<String>,
        activeEntry: Binding<HistoryEntry?>,
        entryRowProvider: @escaping (HistoryEntry) -> AnyView,
        copyPromptProvider: @escaping (String) -> Void,
        folderId: UUID? = nil,
        isEditing: Binding<Bool>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        addToInputProvider: @escaping (HistoryItem) -> Void
    ) {
        self.entry = entry
        self._showDeleteAlert = showDeleteAlert
        self._entriesToDelete = entriesToDelete
        self.appState = appState
        self._selectedIDs = selectedIDs
        self._searchText = searchText
        self._activeEntry = activeEntry
        self.entryRowProvider = entryRowProvider
        self.copyPromptProvider = copyPromptProvider
        self.folderId = folderId
        self._isEditing = isEditing
        self._toastMessage = toastMessage
        self._showToast = showToast
        self.addToInputProvider = addToInputProvider
    }
    
    var body: some View {
        if case .folder(let folder) = entry {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    if searchText.isEmpty {
                        ReorderableForEach(
                            folder.children,
                            active: $activeEntry,
                            appState: appState,
                            folderId: folder.id,
                            selectedIDs: $selectedIDs,
                            toastMessage: $toastMessage,
                            showToast: $showToast
                        ) { child in
                            AnyView(
                                TreeNodeView(
                                    entry: child,
                                    showDeleteAlert: $showDeleteAlert,
                                    entriesToDelete: $entriesToDelete,
                                    appState: appState,
                                    selectedIDs: $selectedIDs,
                                    searchText: $searchText,
                                    activeEntry: $activeEntry,
                                    entryRowProvider: entryRowProvider,
                                    copyPromptProvider: copyPromptProvider,
                                    folderId: folder.id,
                                    isEditing: $isEditing,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast,
                                    addToInputProvider: addToInputProvider
                                )
                            )
                        } moveAction: { from, to in
                            appState.historyState.move(inFolderId: folder.id, from: from, to: to)
                        }
                    } else {
                        ForEach(folder.children) { child in
                            AnyView(
                                TreeNodeView(
                                    entry: child,
                                    showDeleteAlert: $showDeleteAlert,
                                    entriesToDelete: $entriesToDelete,
                                    appState: appState,
                                    selectedIDs: $selectedIDs,
                                    searchText: $searchText,
                                    activeEntry: $activeEntry,
                                    entryRowProvider: entryRowProvider,
                                    copyPromptProvider: copyPromptProvider,
                                    folderId: folder.id,
                                    isEditing: $isEditing,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast,
                                    addToInputProvider: addToInputProvider
                                )
                            )
                        }
                    }
                }
                .padding(.leading, 20)
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else {
                        activeEntry = nil
                        return false
                    }
                    provider.loadObject(ofClass: NSString.self) { reading, _ in
                        guard let str = reading as? String else {
                            DispatchQueue.main.async {
                                self.toastMessage = "Drop failed: Invalid data"
                                self.showToast = true
                                self.hideToastAfterDelay()
                            }
                            return
                        }
                        let idStrings = str.split(separator: ",").map(String.init)
                        let ids = idStrings.compactMap(UUID.init(uuidString:))
                        guard !ids.isEmpty else {
                            DispatchQueue.main.async {
                                self.toastMessage = "Drop failed: No valid items"
                                self.showToast = true
                                self.hideToastAfterDelay()
                            }
                            return
                        }
                        DispatchQueue.main.async {
                            var movedEntries: [HistoryEntry] = []
                            var snapshot = appState.historyState.history
                            for id in ids {
                                if let entry = appState.historyState.findAndRemoveEntry(id: id, in: &snapshot) {
                                    movedEntries.append(entry)
                                } else {
                                    print("Drop failed to find entry with ID: \(id)")
                                }
                            }
                            if movedEntries.isEmpty {
                                self.toastMessage = "Drop failed: Items not found"
                                self.showToast = true
                                self.hideToastAfterDelay()
                                return
                            }
                            let insertIndex = snapshot.first(where: { $0.id == folder.id })?.childrenForOutline?.count ?? 0
                            if appState.historyState.insert(entries: movedEntries, inFolderId: folder.id, at: insertIndex, into: &snapshot) {
                                appState.historyState.history = snapshot
                                appState.historyState.saveHistory()
                                self.selectedIDs.removeAll()
                                self.toastMessage = "Moved \(movedEntries.count) item(s)"
                                self.showToast = true
                                self.hideToastAfterDelay()
                            } else {
                                self.toastMessage = "Failed to move to folder"
                                self.showToast = true
                                self.hideToastAfterDelay()
                            }
                        }
                    }
                    return true
                }
            } label: {
                entryRowProvider(entry)
                    .onLongPressGesture {
                        newFolderName = folder.name
                        showRenameAlert = true
                    }
            }
            .contextMenu {
                if !isEditing {
                    Button("Rename Folder") {
                        newFolderName = folder.name
                        showRenameAlert = true
                    }
                    Button("Delete", role: .destructive) {
                        let isMulti = isEditing && selectedIDs.count > 1 && selectedIDs.contains(folder.id)
                        if isMulti {
                            entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                        } else {
                            entriesToDelete = [.folder(folder)]
                        }
                        showDeleteAlert = true
                    }
                    #if os(macOS)
                    Menu("Move to...") {
                        Button("Root") {
                            let success = appState.historyState.moveToFolder(entriesWithIds: [folder.id], toFolderId: nil)
                            if success {
                                selectedIDs.removeAll()
                                toastMessage = "Moved to root"
                                showToast = true
                                hideToastAfterDelay()
                            } else {
                                toastMessage = "Failed to move to root"
                                showToast = true
                                hideToastAfterDelay()
                            }
                        }
                        .accessibilityLabel("Move folder to root")
                        ForEach(appState.historyState.allFolders()) { folderOption in
                            if !folderOption.containsAny(ids: Set([folder.id]), in: appState.historyState.history) {
                                Button(folderOption.name) {
                                    let success = appState.historyState.moveToFolder(entriesWithIds: [folder.id], toFolderId: folderOption.id)
                                    if success {
                                        selectedIDs.removeAll()
                                        toastMessage = "Moved to \(folderOption.name)"
                                        showToast = true
                                        hideToastAfterDelay()
                                    } else {
                                        toastMessage = "Failed to move to \(folderOption.name)"
                                        showToast = true
                                        hideToastAfterDelay()
                                    }
                                }
                                .accessibilityLabel("Move folder to \(folderOption.name)")
                            }
                        }
                    }
                    .disabled(appState.historyState.allFolders().isEmpty)
                    .onAppear {
                        print("Context menu for folder \(folder.id): Move to... menu rendered with \(appState.historyState.allFolders().count) folders")
                    }
                    #endif
                } else if selectedIDs.contains(folder.id) {
                    Button("Move to Top") {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: folderId)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to top")
                    Button("Move to Bottom") {
                        appState.historyState.moveToBottom(entriesWithIds: Array(selectedIDs), inFolderId: folderId)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to bottom"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to bottom")
                    #if os(macOS)
                    Menu("Move to...") {
                        Button("Root") {
                            let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: nil)
                            if success {
                                selectedIDs.removeAll()
                                toastMessage = "Moved to root"
                                showToast = true
                                hideToastAfterDelay()
                            } else {
                                toastMessage = "Failed to move to root"
                                showToast = true
                                hideToastAfterDelay()
                            }
                        }
                        .accessibilityLabel("Move selected items to root")
                        ForEach(appState.historyState.allFolders()) { folderOption in
                            if !folderOption.containsAny(ids: selectedIDs, in: appState.historyState.history) {
                                Button(folderOption.name) {
                                    let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: folderOption.id)
                                    if success {
                                        selectedIDs.removeAll()
                                        toastMessage = "Moved to \(folderOption.name)"
                                        showToast = true
                                        hideToastAfterDelay()
                                    } else {
                                        toastMessage = "Failed to move to \(folderOption.name)"
                                        showToast = true
                                        hideToastAfterDelay()
                                    }
                                }
                                .accessibilityLabel("Move selected items to folder \(folderOption.name)")
                            }
                        }
                    }
                    .disabled(appState.historyState.allFolders().isEmpty)
                    .onAppear {
                        print("Context menu for selected folder \(folder.id): Move to... menu rendered with \(appState.historyState.allFolders().count) folders")
                    }
                    #endif
                    Button("Delete Selected", role: .destructive) {
                        entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                        showDeleteAlert = true
                    }
                    .accessibilityLabel("Delete selected items")
                }
            }
            .alert("Rename Folder", isPresented: $showRenameAlert) {
                TextField("Folder Name", text: $newFolderName)
                Button("OK") {
                    if !newFolderName.isEmpty {
                        appState.historyState.updateFolderName(with: folder.id, newName: newFolderName)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a new name for the folder.")
            }
        } else {
            entryRowProvider(entry) // Rely on itemRow(for:) for context menu
        }
    }
    
    private func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
}

// Move LazyThumbnailView outside
struct LazyThumbnailView: View {
    let item: HistoryItem
    @State private var thumbnail: PlatformImage? = nil
    @EnvironmentObject var appState: AppState
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        Group {
            if let img = thumbnail {
                Image(platformImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .help("Thumbnail of generated image")
                    .accessibilityLabel("Thumbnail of image generated on \(dateFormatter.string(from: item.date))")
                    .onDrag {
                        guard let data = img.pngData() else {
                            return NSItemProvider()
                        }
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                            completion(data, nil)
                            return nil
                        }
                        return provider
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                    .help("Placeholder for image thumbnail")
            }
        }
        .onAppear {
            if thumbnail == nil {
                loadThumbnail()
            }
        }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .background).async {
            let loadedImage = loadImage(for: item)
            DispatchQueue.main.async {
                thumbnail = loadedImage
            }
        }
    }
    
    private func loadImage(for item: HistoryItem) -> PlatformImage? {
        guard let path = item.imagePath else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        if let dir = appState.settings.outputDirectory {
            let didStart = dir.startAccessingSecurityScopedResource()
            let image = PlatformImage(contentsOfFile: fileURL.path)
            if didStart {
                dir.stopAccessingSecurityScopedResource()
            }
            return image
        } else {
            return PlatformImage(contentsOfFile: fileURL.path)
        }
    }
}

// Assume PlatformImage extension for pngData()
#if os(macOS)
extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
#elseif os(iOS)
extension UIImage {
    func pngData() -> Data? {
        return self.pngData()
    }
}
#endif

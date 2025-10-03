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
        isEditing: Binding<Bool>? = nil,
        toastMessage: Binding<String?> = .constant(nil),
        showToast: Binding<Bool> = .constant(false)
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
        #if os(macOS)
        self._isEditing = isEditing ?? .constant(false)
        #endif
        self._toastMessage = toastMessage
        self._showToast = showToast
    }
    
    var body: some View {
        if case .folder(let folder) = entry {
            AnyView(
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        if searchText.isEmpty {
                            AnyView(ReorderableForEach(
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
                                        showToast: $showToast
                                    )
                                )
                            } moveAction: { from, to in
                                appState.historyState.move(inFolderId: folder.id, from: from, to: to)
                            })
                        } else {
                            AnyView(ForEach(folder.children) { child in
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
                                        showToast: $showToast
                                    )
                                )
                            })
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
                                for id in ids {
                                    if let entry = appState.historyState.findAndRemoveEntry(with: id) {
                                        movedEntries.append(entry)
                                    }
                                }
                                if movedEntries.isEmpty {
                                    self.toastMessage = "Drop failed: Items not found"
                                    self.showToast = true
                                    self.hideToastAfterDelay()
                                    return
                                }
                                let insertIndex = appState.historyState.history.first(where: { $0.id == folder.id })?.childrenForOutline?.count ?? 0
                                appState.historyState.insert(entries: movedEntries, inFolderId: folder.id, at: insertIndex)
                                self.selectedIDs.removeAll()
                                self.toastMessage = "Moved \(movedEntries.count) item(s)"
                                self.showToast = true
                                self.hideToastAfterDelay()
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
                    #if os(iOS)
                    if editMode?.wrappedValue == .active && selectedIDs.contains(entry.id) {
                        Button("Move to Top") {
                            appState.historyState.moveToTop(entriesWithIds: [entry.id], inFolderId: folderId)
                            selectedIDs.removeAll()
                            toastMessage = "Moved to top"
                            showToast = true
                            hideToastAfterDelay()
                        }
                        Button("Move to Bottom") {
                            appState.historyState.moveToBottom(entriesWithIds: [entry.id], inFolderId: folderId)
                            selectedIDs.removeAll()
                            toastMessage = "Moved to bottom"
                            showToast = true
                            hideToastAfterDelay()
                        }
                    }
                    #else
                    if isEditing && selectedIDs.contains(entry.id) {
                        Button("Move to Top") {
                            appState.historyState.moveToTop(entriesWithIds: [entry.id], inFolderId: folderId)
                            selectedIDs.removeAll()
                            toastMessage = "Moved to top"
                            showToast = true
                            hideToastAfterDelay()
                        }
                        Button("Move to Bottom") {
                            appState.historyState.moveToBottom(entriesWithIds: [entry.id], inFolderId: folderId)
                            selectedIDs.removeAll()
                            toastMessage = "Moved to bottom"
                            showToast = true
                            hideToastAfterDelay()
                        }
                    }
                    #endif
                    Button("Rename Folder") {
                        newFolderName = folder.name
                        showRenameAlert = true
                    }
                    Button("Delete Folder") {
                        #if os(iOS)
                        let isMulti = editMode?.wrappedValue == .active && selectedIDs.count > 1 && selectedIDs.contains(folder.id)
                        #else
                        let isMulti = isEditing && selectedIDs.count > 1 && selectedIDs.contains(folder.id)
                        #endif
                        if isMulti {
                            entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                        } else {
                            entriesToDelete = [.folder(folder)]
                        }
                        showDeleteAlert = true
                    }
                }
                .onDrop(of: [.text], delegate: FolderDropDelegate(
                    folder: folder,
                    appState: appState,
                    selectedIDs: $selectedIDs,
                    toastMessage: $toastMessage,
                    showToast: $showToast
                ))
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
            )
        } else {
            AnyView(
                entryRowProvider(entry)
                    .contextMenu {
                        if case .item(let item) = entry {
                            #if os(iOS)
                            if editMode?.wrappedValue == .active && selectedIDs.contains(item.id) {
                                Button("Move to Top") {
                                    appState.historyState.moveToTop(entriesWithIds: [item.id], inFolderId: folderId)
                                    selectedIDs.removeAll()
                                    toastMessage = "Moved to top"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                                Button("Move to Bottom") {
                                    appState.historyState.moveToBottom(entriesWithIds: [item.id], inFolderId: folderId)
                                    selectedIDs.removeAll()
                                    toastMessage = "Moved to bottom"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                            #else
                            if isEditing && selectedIDs.contains(item.id) {
                                Button("Move to Top") {
                                    appState.historyState.moveToTop(entriesWithIds: [item.id], inFolderId: folderId)
                                    selectedIDs.removeAll()
                                    toastMessage = "Moved to top"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                                Button("Move to Bottom") {
                                    appState.historyState.moveToBottom(entriesWithIds: [item.id], inFolderId: folderId)
                                    selectedIDs.removeAll()
                                    toastMessage = "Moved to bottom"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                            #endif
                            Button("Copy Prompt") {
                                copyPromptProvider(item.prompt)
                            }
                            .help("Copy the prompt to clipboard")
                            Button("Delete") {
                                #if os(iOS)
                                let isMulti = editMode?.wrappedValue == .active && selectedIDs.count > 1 && selectedIDs.contains(item.id)
                                #else
                                let isMulti = isEditing && selectedIDs.count > 1 && selectedIDs.contains(item.id)
                                #endif
                                if isMulti {
                                    entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                                } else {
                                    entriesToDelete = [.item(item)]
                                }
                                showDeleteAlert = true
                            }
                        }
                    }
            )
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

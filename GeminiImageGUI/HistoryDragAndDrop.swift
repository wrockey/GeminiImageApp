// HistoryDragAndDrop.swift
import SwiftUI
#if os(macOS)
import AppKit
#endif
 
// Add Reorderable typealias
typealias Reorderable = Identifiable & Equatable
 
// Add ReorderableForEach and related structs
struct ReorderableForEach<Item: Reorderable, Content: View, Preview: View>: View {
    let items: [Item]
    @Binding var active: Item?
    let content: (Item) -> Content
    let preview: ((Item) -> Preview)?
    let moveAction: (IndexSet, Int) -> Void
    let appState: AppState
    let folderId: UUID?
    @Binding var selectedIDs: Set<UUID>
    @Binding var toastMessage: String?
    @Binding var showToast: Bool
    let undoManager: UndoManager?
   
    init(
        _ items: [Item],
        active: Binding<Item?>,
        appState: AppState,
        folderId: UUID?,
        selectedIDs: Binding<Set<UUID>>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        undoManager: UndoManager?,
        @ViewBuilder content: @escaping (Item) -> Content,
        @ViewBuilder preview: @escaping (Item) -> Preview,
        moveAction: @escaping (IndexSet, Int) -> Void
    ) {
        self.items = items
        self._active = active
        self.content = content
        self.preview = preview
        self.moveAction = moveAction
        self.appState = appState
        self.folderId = folderId
        self._selectedIDs = selectedIDs
        self._toastMessage = toastMessage
        self._showToast = showToast
        self.undoManager = undoManager
    }
   
    init(
        _ items: [Item],
        active: Binding<Item?>,
        appState: AppState,
        folderId: UUID?,
        selectedIDs: Binding<Set<UUID>>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        undoManager: UndoManager?,
        @ViewBuilder content: @escaping (Item) -> Content,
        moveAction: @escaping (IndexSet, Int) -> Void
    ) where Preview == EmptyView {
        self.items = items
        self._active = active
        self.content = content
        self.preview = nil
        self.moveAction = moveAction
        self.appState = appState
        self.folderId = folderId
        self._selectedIDs = selectedIDs
        self._toastMessage = toastMessage
        self._showToast = showToast
        self.undoManager = undoManager
    }
   
    var body: some View {
        ForEach(items) { item in
            if let preview = preview {
                contentView(for: item)
                    .onDrag {
                        active = item
                        guard let uuid = item.id as? UUID else {
                            return NSItemProvider()
                        }
                        return NSItemProvider(object: uuid.uuidString as NSString)
                    } preview: {
                        preview(item)
                    }
            } else {
                contentView(for: item)
                    .onDrag {
                        active = item
                        guard let uuid = item.id as? UUID else {
                            return NSItemProvider()
                        }
                        return NSItemProvider(object: uuid.uuidString as NSString)
                    }
            }
        }
    }
   
    private func contentView(for item: Item) -> some View {
        content(item)
            .opacity(active == item && hasChangedLocation ? 0.5 : 1)
            .onDrop(
                of: [.text],
                delegate: ReorderableDragRelocateDelegate(
                    item: item,
                    items: items,
                    active: $active,
                    hasChangedLocation: $hasChangedLocation,
                    appState: appState,
                    folderId: folderId,
                    moveAction: moveAction,
                    selectedIDs: $selectedIDs,
                    toastMessage: $toastMessage,
                    showToast: $showToast,
                    undoManager: undoManager
                )
            )
    }
   
    @State private var hasChangedLocation: Bool = false
}
 
struct ReorderableDragRelocateDelegate<Item: Reorderable>: DropDelegate {
    let item: Item
    let items: [Item]
    @Binding var active: Item?
    @Binding var hasChangedLocation: Bool
    let appState: AppState
    let folderId: UUID?
    let moveAction: (IndexSet, Int) -> Void
    @Binding var selectedIDs: Set<UUID>
    @Binding var toastMessage: String?
    @Binding var showToast: Bool
    let undoManager: UndoManager?
   
    init(
        item: Item,
        items: [Item],
        active: Binding<Item?>,
        hasChangedLocation: Binding<Bool>,
        appState: AppState,
        folderId: UUID?,
        moveAction: @escaping (IndexSet, Int) -> Void,
        selectedIDs: Binding<Set<UUID>>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        undoManager: UndoManager?
    ) {
        self.item = item
        self.items = items
        self._active = active
        self._hasChangedLocation = hasChangedLocation
        self.appState = appState
        self.folderId = folderId
        self.moveAction = moveAction
        self._selectedIDs = selectedIDs
        self._toastMessage = toastMessage
        self._showToast = showToast
        self.undoManager = undoManager
    }
   
    func dropEntered(info: DropInfo) {
        guard let current = active else { return }
        guard let from = items.firstIndex(where: { $0.id == current.id }) else { return }
        guard let to = items.firstIndex(where: { $0.id == item.id }) else { return }
        hasChangedLocation = true
        if from != to {
            moveAction(IndexSet(integer: from), to + (from < to ? 1 : 0))
        }
    }
   
    func dropUpdated(info: DropInfo) -> DropProposal? {
        .init(operation: .move)
    }
   
    func performDrop(info: DropInfo) -> Bool {
        let wasChanged = hasChangedLocation
        hasChangedLocation = false
        active = nil
        selectedIDs.removeAll()
        if wasChanged {
            toastMessage = "Items moved"
            showToast = true
            hideToastAfterDelay()
            return true
        }
        guard let provider = info.itemProviders(for: [.text]).first else {
            toastMessage = "Drop failed: No valid data"
            showToast = true
            hideToastAfterDelay()
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
                let oldHistory = appState.historyState.history
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
                let insertIndex = items.firstIndex(where: { $0.id == item.id }).map { $0 + 1 } ?? items.count
                appState.historyState.insert(entries: movedEntries, inFolderId: folderId, at: insertIndex, into: &snapshot)
                appState.historyState.history = snapshot
                appState.historyState.saveHistory()
                self.selectedIDs.removeAll()
                self.toastMessage = "Moved \(movedEntries.count) item(s)"
                self.showToast = true
                self.hideToastAfterDelay()
                if let undoManager = self.undoManager {
                    let newHistory = appState.historyState.history
                    undoManager.registerUndo(withTarget: appState.historyState) { target in
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
        return true
    }
   
    private func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
}
 
struct FolderDropDelegate: DropDelegate {
    let folder: Folder
    let appState: AppState
    @Binding var selectedIDs: Set<UUID>
    @Binding var toastMessage: String?
    @Binding var showToast: Bool
    let undoManager: UndoManager?
   
    init(
        folder: Folder,
        appState: AppState,
        selectedIDs: Binding<Set<UUID>>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        undoManager: UndoManager?
    ) {
        self.folder = folder
        self.appState = appState
        self._selectedIDs = selectedIDs
        self._toastMessage = toastMessage
        self._showToast = showToast
        self.undoManager = undoManager
    }
   
    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else {
            toastMessage = "Drop failed: No valid data"
            showToast = true
            hideToastAfterDelay()
            return false
        }
        item.loadObject(ofClass: NSString.self) { (string, _) in
            guard let str = string as? String else {
                DispatchQueue.main.async {
                    self.toastMessage = "Drop failed: Invalid data"
                    self.showToast = true
                    self.hideToastAfterDelay()
                }
                return
            }
            let idStrings = str.split(separator: ",").map { String($0) }
            let ids = idStrings.compactMap { UUID(uuidString: $0) }
            guard !ids.isEmpty else {
                DispatchQueue.main.async {
                    self.toastMessage = "Drop failed: No valid items"
                    self.showToast = true
                    self.hideToastAfterDelay()
                }
                return
            }
            guard !ids.contains(folder.id) else {
                DispatchQueue.main.async {
                    self.toastMessage = "Cannot move folder into itself"
                    self.showToast = true
                    self.hideToastAfterDelay()
                }
                return
            }
            DispatchQueue.main.async {
                let oldHistory = appState.historyState.history
                var movedEntries: [HistoryEntry] = []
                var snapshot = appState.historyState.history
                for id in ids {
                    if let movedEntry = appState.historyState.findAndRemoveEntry(id: id, in: &snapshot) {
                        movedEntries.append(movedEntry)
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
                for entry in movedEntries {
                    appState.historyState.addEntry(entry, toFolderWithId: folder.id, into: &snapshot)
                }
                appState.historyState.history = snapshot
                appState.historyState.saveHistory()
                self.selectedIDs.removeAll()
                self.toastMessage = "Moved \(movedEntries.count) item(s) to folder"
                self.showToast = true
                self.hideToastAfterDelay()
                if let undoManager = self.undoManager {
                    let newHistory = appState.historyState.history
                    undoManager.registerUndo(withTarget: appState.historyState) { target in
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
            }
        }
        return true
    }
   
    private func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
}
 
 
extension HistoryState {
 
   
    // Add entry to a specific folder
 }



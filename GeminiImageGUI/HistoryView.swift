import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

struct HistoryView: View {
    @Binding var imageSlots: [ImageSlot]
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undoManager
    @State private var showDeleteAlert: Bool = false
    @State private var entriesToDelete: [HistoryEntry] = []
    @State private var searchText: String = ""
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var fullHistoryItemId: UUID? = nil
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    #if os(iOS)
    @Environment(\.editMode) private var editMode: Binding<EditMode>?
    @State private var showClearHistoryConfirmation: Bool = false
    #endif
    #if os(macOS)
    @State private var isEditing: Bool = false
    @State private var showClearHistoryConfirmation: Bool = false
    #if swift(>=5.7)
    @Environment(\.openWindow) private var openWindow
    #endif
    #endif
    @State private var activeEntry: HistoryEntry? = nil
    @State private var selectedIDs: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    private var filteredHistory: [HistoryEntry] {
        let base = searchText.isEmpty ? appState.historyState.history : filterEntries(appState.historyState.history, with: searchText)
        #if os(macOS)
        return sortedEntries(base)
        #else
        return base
        #endif
    }
    
    private var fileCount: Int {
        let items = entriesToDelete.flatMap { $0.allItems }
        print("fileCount: items = \(items.map { "\($0.id): \($0.imagePath ?? "nil")" })")
        return items.filter { $0.imagePath != nil }.count
    }
    
    private var existingFileCount: Int {
        let items = entriesToDelete.flatMap { $0.allItems }
        return items.filter { $0.fileExists(appState: appState) }.count
    }
    
    private var hasExistingFiles: Bool {
        existingFileCount > 0
    }
    
    private var deleteTitle: String {
        let itemCount = entriesToDelete.flatMap { $0.allItems }.count
        return itemCount == 1 ? "Delete Item" : "Delete \(itemCount) Items"
    }
    
    private var deleteMessage: String {
        var msg = "Are you sure you want to delete from history?"
        if fileCount > 0 {
            let missing = fileCount - existingFileCount
            if missing > 0 {
                msg += "\nNote: \(missing) file\(missing == 1 ? "" : "s") missing or inaccessible."
            }
        }
        return msg
    }
    
    var body: some View {
        content
            #if os(iOS)
            .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
                Button("Clear", role: .destructive) {
                    appState.historyState.clearHistory(undoManager: undoManager)
                    toastMessage = "History cleared"
                    showToast = true
                    hideToastAfterDelay()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all history entries but keep your files intact. Are you sure?")
            }
            #endif
            #if os(macOS)
            .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
                Button("Clear", role: .destructive) {
                    appState.historyState.clearHistory(undoManager: undoManager)
                    toastMessage = "History cleared"
                    showToast = true
                    hideToastAfterDelay()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all history entries but keep your files intact. Are you sure?")
            }
            #endif
            .onChange(of: appState.historyState.history) { _ in
                selectedIDs.removeAll()
                activeEntry = nil
                #if os(iOS)
                if let editMode = editMode {
                    editMode.wrappedValue = .inactive
                }
                #endif
                print("History changed: \(appState.historyState.history.map { $0.id })")
            }
            .sheet(isPresented: $showDeleteAlert) {
                DeleteConfirmationView(
                    title: deleteTitle,
                    message: deleteMessage,
                    hasDeletableFiles: hasExistingFiles,
                    deleteAction: { deleteFiles in
                        appState.historyState.deleteEntries(entriesToDelete, deleteFiles: deleteFiles, undoManager: undoManager)
                        let deletedCount = entriesToDelete.flatMap { $0.allItems }.count
                        toastMessage = deletedCount == 1 ? "Item deleted" : "\(deletedCount) items deleted"
                        showToast = true
                        hideToastAfterDelay()
                        selectedIDs.removeAll()
                    },
                    cancelAction: {}
                )
            }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            historyList
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            overlayContent
        }
    }
    
    private var overlayContent: some View {
        Group {
            #if os(iOS)
            if showToast, let message = toastMessage {
                Text(message)
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .onAppear {
                        hideToastAfterDelay()
                    }
            }
            #else
            if showToast, let message = toastMessage {
                Text(message)
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .onAppear {
                        hideToastAfterDelay()
                    }
            }
            #endif
        }
    }
    
    private func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
    
    private var header: some View {
        #if os(macOS)
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
            }) {
                Image(systemName: "chevron.left")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Collapse history sidebar")
            .accessibilityLabel("Collapse history sidebar")
            
            Text("History")
                .font(.system(.headline, design: .default, weight: .semibold))
                .kerning(0.2)
                .help("View past generated images and videos")
            Button(action: {
                showClearHistoryConfirmation = true
            }) {
                Image(systemName: "trash.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .disabled(filteredHistory.isEmpty)
            .help("Clear all history entries")
            .accessibilityLabel("Clear history")
            
            Spacer()
            
            Button(action: {
                let actionName = undoManager?.undoActionName ?? ""
                undoManager?.undo()
                toastMessage = actionName.isEmpty ? "Action undone" : "Undid \(actionName)"
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "arrow.uturn.left")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .disabled(!(undoManager?.canUndo ?? false))
            .help("Undo last action")
            .accessibilityLabel("Undo")
            
            Button(action: {
                let actionName = undoManager?.redoActionName ?? ""
                undoManager?.redo()
                toastMessage = actionName.isEmpty ? "Action redone" : "Redid \(actionName)"
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "arrow.uturn.right")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .disabled(!(undoManager?.canRedo ?? false))
            .help("Redo last action")
            .accessibilityLabel("Redo")
            
            commonActions
        }
        .padding(.horizontal)
        #else
        HStack(spacing: 8) {
            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .kerning(0.2)
                .help("View past generated images and videos")
            Button(action: {
                showClearHistoryConfirmation = true
            }) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(filteredHistory.isEmpty)
            .help("Clear all history entries")
            .accessibilityLabel("Clear history")
            
            Spacer()
            
            Button(action: {
                let actionName = undoManager?.undoActionName ?? ""
                undoManager?.undo()
                toastMessage = actionName.isEmpty ? "Action undone" : "Undid \(actionName)"
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .disabled(!(undoManager?.canUndo ?? false))
            .help("Undo last action")
            .accessibilityLabel("Undo")
            
            Button(action: {
                let actionName = undoManager?.redoActionName ?? ""
                undoManager?.redo()
                toastMessage = actionName.isEmpty ? "Action redone" : "Redid \(actionName)"
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "arrow.uturn.right")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .disabled(!(undoManager?.canRedo ?? false))
            .help("Redo last action")
            .accessibilityLabel("Redo")
            
            commonActions
            
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Close history view")
            .accessibilityLabel("Close history view")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onDrop(of: [.text], isTargeted: nil) { providers in
            let oldHistory = appState.historyState.history
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
                            print("Drag-and-drop failed to find entry with ID: \(id)")
                        }
                    }
                    if movedEntries.isEmpty {
                        self.toastMessage = "Drop failed: Items not found"
                        self.showToast = true
                        self.hideToastAfterDelay()
                        return
                    }
                    let insertIndex = appState.historyState.history.count
                    appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex, into: &snapshot)
                    appState.historyState.history = snapshot
                    appState.historyState.saveHistory()
                    self.selectedIDs.removeAll()
                    self.toastMessage = "Moved \(movedEntries.count) item(s)"
                    self.showToast = true
                    self.hideToastAfterDelay()
                    if let undoManager {
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
        #endif
    }
    
    private var commonActions: some View {
        Group {
            Button(action: {
                appState.historyState.addFolder(undoManager: undoManager)
                toastMessage = "Folder added"
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "folder.badge.plus")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.blue.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Add new folder")
            .accessibilityLabel("Add folder")
            
            if isEditingBinding.wrappedValue {
                Button(action: {
                    if !selectedIDs.isEmpty {
                        entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                        print("Setting entriesToDelete: \(entriesToDelete.map { $0.id })")
                        showDeleteAlert = true
                    }
                }) {
                    Image(systemName: "trash")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(selectedIDs.isEmpty ? .gray : .red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(selectedIDs.isEmpty)
                .help("Delete selected items")
                .accessibilityLabel("Delete selected items")
                
                #if os(iOS)
                Button(action: {
                    if !selectedIDs.isEmpty {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil, undoManager: undoManager)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay()
                    }
                }) {
                    Image(systemName: "arrow.up.to.line")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(selectedIDs.isEmpty ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(selectedIDs.isEmpty)
                .help("Move selected items to top")
                .accessibilityLabel("Move selected items to top")
                
                Button(action: {
                    if !selectedIDs.isEmpty {
                        appState.historyState.moveToBottom(entriesWithIds: Array(selectedIDs), inFolderId: nil, undoManager: undoManager)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to bottom"
                        showToast = true
                        hideToastAfterDelay()
                    }
                }) {
                    Image(systemName: "arrow.down.to.line")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(selectedIDs.isEmpty ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(selectedIDs.isEmpty)
                .help("Move selected items to bottom")
                .accessibilityLabel("Move selected items to bottom")
                #endif
                
                Button(action: {
                    if !selectedIDs.isEmpty {
                        var addedCount = 0
                        func addRecursively(entry: HistoryEntry) {
                            switch entry {
                            case .item(let item):
                                addToInputImages(item: item)
                                addedCount += 1
                            case .folder(let folder):
                                for child in folder.children {
                                    addRecursively(entry: child)
                                }
                            }
                        }
                        for entry in appState.historyState.findEntries(with: selectedIDs) {
                            addRecursively(entry: entry)
                        }
                        selectedIDs.removeAll()
                        toastMessage = "Added \(addedCount) item\(addedCount == 1 ? "" : "s") to input"
                        showToast = true
                        hideToastAfterDelay()
                    }
                }) {
                    Image(systemName: "plus")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(selectedIDs.isEmpty ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(selectedIDs.isEmpty)
                .help("Add selected images to input")
                .accessibilityLabel("Add selected items to input")
            }
            
            Button(action: {
                isEditingBinding.wrappedValue.toggle()
                if !isEditingBinding.wrappedValue {
                    selectedIDs.removeAll()
                }
            }) {
                Text(isEditingBinding.wrappedValue ? "Done" : "Select")
            }
            .buttonStyle(.borderless)
            .help("Select multiple items")
            .accessibilityLabel("Select multiple items")
        }
    }
    
    private var searchField: some View {
        TextField("Search prompts or dates...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .help("Search history by prompt text or date")
            .accessibilityLabel("Search prompts or dates")
    }
    
    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if filteredHistory.isEmpty {
                    Text("No history yet.")
                        .foregroundColor(.secondary)
                        .help("No generation history available yet")
                        .padding()
                } else {
                    if searchText.isEmpty {
                        #if os(macOS)
                        ForEach(filteredHistory) { entry in
                            TreeNodeView(
                                entry: entry,
                                showDeleteAlert: $showDeleteAlert,
                                entriesToDelete: $entriesToDelete,
                                appState: appState,
                                selectedIDs: $selectedIDs,
                                searchText: $searchText,
                                activeEntry: $activeEntry,
                                entryRowProvider: { AnyView(self.entryRow(for: $0)) },
                                copyPromptProvider: { prompt in
                                    self.copyPromptToClipboard(prompt)
                                    self.toastMessage = "Prompt copied to clipboard"
                                    self.showToast = true
                                    self.hideToastAfterDelay()
                                },
                                folderId: nil,
                                isEditing: isEditingBinding,
                                toastMessage: $toastMessage,
                                showToast: $showToast,
                                addToInputProvider: { item in
                                    self.addToInputImages(item: item)
                                    self.toastMessage = "Item added to input"
                                    self.showToast = true
                                    self.hideToastAfterDelay()
                                },
                                undoManager: undoManager
                            )
                        }
                        #else
                        AnyView(ReorderableForEach(
                            filteredHistory,
                            active: $activeEntry,
                            appState: appState,
                            folderId: nil,
                            selectedIDs: $selectedIDs,
                            toastMessage: $toastMessage,
                            showToast: $showToast,
                            undoManager: undoManager
                        ) { entry in
                            AnyView(
                                TreeNodeView(
                                    entry: entry,
                                    showDeleteAlert: $showDeleteAlert,
                                    entriesToDelete: $entriesToDelete,
                                    appState: appState,
                                    selectedIDs: $selectedIDs,
                                    searchText: $searchText,
                                    activeEntry: $activeEntry,
                                    entryRowProvider: { AnyView(self.entryRow(for: $0)) },
                                    copyPromptProvider: { prompt in
                                        self.copyPromptToClipboard(prompt)
                                        self.toastMessage = "Prompt copied to clipboard"
                                        self.showToast = true
                                        self.hideToastAfterDelay()
                                    },
                                    folderId: nil,
                                    isEditing: isEditingBinding,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast,
                                    addToInputProvider: { item in
                                        self.addToInputImages(item: item)
                                        self.toastMessage = "Item added to input"
                                        self.showToast = true
                                        self.hideToastAfterDelay()
                                    },
                                    undoManager: undoManager
                                )
                            )
                        } moveAction: { from, to in
                            appState.historyState.move(inFolderId: nil, from: from, to: to, undoManager: undoManager)
                        })
                        #endif
                    } else {
                        ForEach(filteredHistory) { entry in
                            TreeNodeView(
                                entry: entry,
                                showDeleteAlert: $showDeleteAlert,
                                entriesToDelete: $entriesToDelete,
                                appState: appState,
                                selectedIDs: $selectedIDs,
                                searchText: $searchText,
                                activeEntry: $activeEntry,
                                entryRowProvider: { AnyView(self.entryRow(for: $0)) },
                                copyPromptProvider: { prompt in
                                    self.copyPromptToClipboard(prompt)
                                    self.toastMessage = "Prompt copied to clipboard"
                                    self.showToast = true
                                    self.hideToastAfterDelay()
                                },
                                folderId: nil,
                                isEditing: isEditingBinding,
                                toastMessage: $toastMessage,
                                showToast: $showToast,
                                addToInputProvider: { item in
                                    self.addToInputImages(item: item)
                                    self.toastMessage = "Item added to input"
                                    self.showToast = true
                                    self.hideToastAfterDelay()
                                },
                                undoManager: undoManager
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            #if os(iOS)
            .onDrop(of: [.text], isTargeted: nil) { providers in
                let oldHistory = appState.historyState.history
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
                                print("Drag-and-drop failed to find entry with ID: \(id)")
                            }
                        }
                        if movedEntries.isEmpty {
                            self.toastMessage = "Drop failed: Items not found"
                            self.showToast = true
                            self.hideToastAfterDelay()
                            return
                        }
                        let insertIndex = appState.historyState.history.count
                        appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex, into: &snapshot)
                        appState.historyState.history = snapshot
                        appState.historyState.saveHistory()
                        self.selectedIDs.removeAll()
                        self.toastMessage = "Moved \(movedEntries.count) item(s)"
                        self.showToast = true
                        self.hideToastAfterDelay()
                        if let undoManager {
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
            #endif
        }
    }
    
    private var isEditingBinding: Binding<Bool> {
        #if os(iOS)
        Binding(
            get: { (editMode?.wrappedValue == .active) ?? false },
            set: { newValue in
                withAnimation {
                    if let editMode = editMode {
                        editMode.wrappedValue = newValue ? .active : .inactive
                    }
                }
            }
        )
        #else
        $isEditing
        #endif
    }
    
    private func findParentFolderId(for itemId: UUID, in entries: [HistoryEntry]) -> UUID? {
        for entry in entries {
            if case .folder(let folder) = entry {
                if folder.children.contains(where: { $0.id == itemId }) {
                    return folder.id
                }
                if let nestedParent = findParentFolderId(for: itemId, in: folder.children) {
                    return nestedParent
                }
            }
        }
        return nil
    }
    
    private func parentFolders(for ids: Set<UUID>) -> Set<UUID?> {
        var parents = Set<UUID?>()
        for id in ids {
            parents.insert(findParentFolderId(for: id, in: appState.historyState.history))
        }
        return parents
    }
    
    private func getMoveDestinations(for ids: Set<UUID>) -> (showHome: Bool, folders: [HistoryState.FolderOption]) {
        let parents = parentFolders(for: ids)
        let hasCommonParent = parents.count == 1
        let commonParentId = hasCommonParent ? parents.first! : nil
        let showHome = !hasCommonParent || commonParentId != nil
        let folders = (hasCommonParent && commonParentId != nil) ? appState.historyState.allFolders().filter { $0.id != commonParentId! } : appState.historyState.allFolders()
        return (showHome, folders)
    }
    
    @ViewBuilder
    private func entryRow(for entry: HistoryEntry) -> some View {
        switch entry {
        case .item(let item):
            itemRow(for: item)
                #if os(iOS)
                .onDrag {
                    var payload: String
                    var idsToDrag: [UUID]
                    if isEditingBinding.wrappedValue && !selectedIDs.isEmpty {
                        idsToDrag = Array(selectedIDs).sorted()
                    } else {
                        idsToDrag = [entry.id]
                    }
                    payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
                    return NSItemProvider(object: payload as NSString)
                }
                #endif
        case .folder(let folder):
            HStack {
                if isEditingBinding.wrappedValue {
                    Image(systemName: selectedIDs.contains(folder.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                }
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.secondary)
                    .help("Folder icon")
                Text(folder.name)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditingBinding.wrappedValue {
                    var allIDs = Set<UUID>()
                    entry.collectAllIDs(into: &allIDs)
                    if selectedIDs.contains(folder.id) {
                        for id in allIDs {
                            selectedIDs.remove(id)
                        }
                    } else {
                        selectedIDs.formUnion(allIDs)
                    }
                }
            }
            #if os(iOS)
            .onDrag {
                var payload: String
                var idsToDrag: [UUID]
                if isEditingBinding.wrappedValue && !selectedIDs.isEmpty {
                    idsToDrag = Array(selectedIDs).sorted()
                } else {
                    idsToDrag = [entry.id]
                }
                payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
                return NSItemProvider(object: payload as NSString)
            }
            #endif
        }
    }
    
    private func itemRow(for item: HistoryItem) -> some View {
        let exists = item.fileExists(appState: appState)
        var creator: String? = nil
        if let mode = item.mode {
            creator = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : (item.workflowName ?? "ComfyUI")
            
            if let idx = item.indexInBatch, let tot = item.totalInBatch {
                creator! += " #\(idx + 1) of \(tot)"
            }
        }
        
        return HStack(spacing: 12) {
            if isEditingBinding.wrappedValue {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 20))
            }
            ZStack {
                LazyThumbnailView(item: item)
                if item.imagePath?.hasSuffix(".mp4") ?? false {
                    Image(systemName: "film.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                        .offset(x: 15, y: 15)
                        .help("Video content")
                        .accessibilityLabel("Video indicator")
                }
            }
            .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.prompt.prefix(50) + (item.prompt.count > 50 ? "..." : ""))
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(exists ? .primary : .secondary)
                    .strikethrough(!exists)
                    .help("Prompt: \(item.prompt)")
                    .accessibilityLabel("Prompt: \(item.prompt)")
                Text(dateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Date: \(dateFormatter.string(from: item.date))")
                if let creator = creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Generated with: \(creator)")
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingBinding.wrappedValue {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            } else {
                #if os(macOS)
                #if swift(>=5.7)
                openWindow(id: "history-viewer", value: item.id)
                #else
                fullHistoryItemId = item.id
                #endif
                #else
                appState.presentedModal = .fullHistoryItem(item.id)
                #endif
            }
        }
        #if os(iOS)
        .onDrag {
            var payload: String
            var idsToDrag: [UUID]
            if isEditingBinding.wrappedValue && !selectedIDs.isEmpty {
                idsToDrag = Array(selectedIDs).sorted()
            } else {
                idsToDrag = [item.id]
            }
            payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
            return NSItemProvider(object: payload as NSString)
        }
        #endif
        .contextMenu {
            Group {
                if !isEditingBinding.wrappedValue {
                    Button("Add to Input") {
                        addToInputImages(item: item)
                        toastMessage = "Item added to input"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Add item to input")
                    Button("Copy Prompt") {
                        copyPromptToClipboard(item.prompt)
                        toastMessage = "Prompt copied to clipboard"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Copy prompt")
                    Button("Delete", role: .destructive) {
                        entriesToDelete = [.item(item)]
                        print("Setting entriesToDelete for single item: \(item.id), imagePath: \(item.imagePath ?? "nil")")
                        showDeleteAlert = true
                    }
                    .accessibilityLabel("Delete item")
                    #if os(macOS)
                    Menu("Move to...") {
                        let (showHome, folders) = getMoveDestinations(for: Set([item.id]))
                        if showHome {
                            Button("Home") {
                                let success = appState.historyState.moveToFolder(entriesWithIds: [item.id], toFolderId: nil, undoManager: undoManager)
                                if success {
                                    selectedIDs.removeAll()
                                    toastMessage = "Moved to home"
                                    showToast = true
                                    hideToastAfterDelay()
                                } else {
                                    toastMessage = "Failed to move to home"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                            .accessibilityLabel("Move item to home")
                        }
                        ForEach(folders) { folderOption in
                            Button(folderOption.name) {
                                let success = appState.historyState.moveToFolder(entriesWithIds: [item.id], toFolderId: folderOption.id, undoManager: undoManager)
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
                            .accessibilityLabel("Move item to folder \(folderOption.name)")
                        }
                    }
                    .disabled(appState.historyState.allFolders().isEmpty && findParentFolderId(for: item.id, in: appState.historyState.history) == nil)
                    .onAppear {
                        print("Context menu for item \(item.id): Move to... menu rendered with \(appState.historyState.allFolders().count) folders")
                    }
                    #endif
                } else if selectedIDs.contains(item.id) {
                    #if os(iOS)
                    Button("Move to Top") {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil, undoManager: undoManager)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to top")
                    Button("Move to Bottom") {
                        appState.historyState.moveToBottom(entriesWithIds: Array(selectedIDs), inFolderId: nil, undoManager: undoManager)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to bottom"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to bottom")
                    #endif
                    #if os(macOS)
                    Menu("Move to...") {
                        let (showHome, folders) = getMoveDestinations(for: selectedIDs)
                        if showHome {
                            Button("Home") {
                                let count = selectedIDs.count
                                let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: nil, undoManager: undoManager)
                                if success {
                                    selectedIDs.removeAll()
                                    toastMessage = count > 1 ? "Moved \(count) items to home" : "Moved to home"
                                    showToast = true
                                    hideToastAfterDelay()
                                } else {
                                    toastMessage = "Failed to move to home"
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                            .accessibilityLabel("Move selected items to home")
                        }
                        ForEach(folders) { folderOption in
                            Button(folderOption.name) {
                                let count = selectedIDs.count
                                let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: folderOption.id, undoManager: undoManager)
                                if success {
                                    selectedIDs.removeAll()
                                    toastMessage = count > 1 ? "Moved \(count) items to \(folderOption.name)" : "Moved to \(folderOption.name)"
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
                    .disabled(appState.historyState.allFolders().isEmpty)
                    .onAppear {
                        print("Context menu for selected item \(item.id): Move to... menu rendered with \(appState.historyState.allFolders().count) folders")
                    }
                    #endif
                    Button("Delete Selected", role: .destructive) {
                        entriesToDelete = appState.historyState.findEntries(with: selectedIDs)
                        showDeleteAlert = true
                    }
                    .accessibilityLabel("Delete selected items")
                }
            }
        }
    }
    
    private func copyPromptToClipboard(_ prompt: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = prompt
        #endif
    }
    
    private func fileExists(for item: HistoryItem) -> Bool {
        item.fileExists(appState: appState)
    }
    
    private func addToInputImages(item: HistoryItem) {
        guard let path = item.imagePath else { return }
        let fileURL = URL(fileURLWithPath: path)
        Task {
            guard let img = await LazyThumbnailView(item: item).loadImage(for: item) else { return }
            var promptNodes: [NodeInfo] = []
            
            if fileURL.pathExtension.lowercased() == "png" {
                if let dir = appState.settings.outputDirectory {
                    do {
                        promptNodes = try withSecureAccess(to: dir) {
                            parsePromptNodes(from: fileURL)
                        }
                    } catch {
                        print("Failed to extract workflow from history PNG: \(error)")
                    }
                } else {
                    promptNodes = parsePromptNodes(from: fileURL)
                }
            }
            
            var newSlot = ImageSlot(path: path, image: img)
            if !promptNodes.isEmpty {
                newSlot.promptNodes = promptNodes.sorted { $0.id < $1.id }
                newSlot.selectedPromptIndex = 0
            }
            await MainActor.run {
                appState.ui.imageSlots.append(newSlot)
            }
        }
    }
    
    private func filterEntries(_ entries: [HistoryEntry], with search: String) -> [HistoryEntry] {
        entries.compactMap { entry in
            switch entry {
            case .item(let item):
                if item.prompt.lowercased().contains(search.lowercased()) ||
                   dateFormatter.string(from: item.date).lowercased().contains(search.lowercased()) {
                    return entry
                } else {
                    return nil
                }
            case .folder(let folder):
                let filteredChildren = filterEntries(folder.children, with: search)
                if !filteredChildren.isEmpty || folder.name.lowercased().contains(search.lowercased()) {
                    var newFolder = folder
                    newFolder.children = filteredChildren
                    return .folder(newFolder)
                } else {
                    return nil
                }
            }
        }
    }
    
    private func sortedEntries(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var folders: [Folder] = []
        var items: [HistoryItem] = []
        for entry in entries {
            switch entry {
            case .folder(var folder):
                folder.children = sortedEntries(folder.children)
                folders.append(folder)
            case .item(let item):
                items.append(item)
            }
        }
        folders.sort { $0.name.lowercased() < $1.name.lowercased() }
        items.sort { $0.date > $1.date }
        return folders.map { .folder($0) } + items.map { .item($0) }
    }
}

struct DeleteConfirmationView: View {
    let title: String
    let message: String
    let hasDeletableFiles: Bool
    let deleteAction: (Bool) -> Void
    let cancelAction: () -> Void
    
    @State private var deleteFiles: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                
                if hasDeletableFiles {
                    Toggle("Also permanently delete the file(s)", isOn: $deleteFiles)
                    Text("File deletion cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Button("Cancel", role: .cancel) {
                    cancelAction()
                    dismiss()
                }
                
                Button("Delete", role: .destructive) {
                    deleteAction(deleteFiles)
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

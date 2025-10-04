//HistoryView.swift
import SwiftUI
#if os(macOS)
import AppKit
#endif
 
struct HistoryView: View {
    @Binding var imageSlots: [ImageSlot]
    @EnvironmentObject var appState: AppState
    @State private var showDeleteAlert: Bool = false
    @State private var entriesToDelete: [HistoryEntry] = []
    @State private var showConfirmFileDelete: Bool = false
    @State private var searchText: String = ""
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var fullHistoryItemId: UUID? = nil
    @State private var showAddedMessage: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    #if os(iOS)
    @Environment(\.editMode) private var editMode: Binding<EditMode>?
    @State private var showClearHistoryConfirmation: Bool = false
    #endif
    #if os(macOS)
    @State private var isEditing: Bool = false
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
        var uniqueItemIDs = Set<UUID>()
   
        func collectUniqueItems(from entries: [HistoryEntry]) {
            for entry in entries {
                switch entry {
                case .item(let item):
                    uniqueItemIDs.insert(item.id)
                case .folder(let folder):
                    collectUniqueItems(from: folder.children)
                }
            }
        }
   
        collectUniqueItems(from: entriesToDelete)
        return uniqueItemIDs.count
    }
 
    private var deleteMessage: String {
        if fileCount == 0 {
            return "Delete from history?"
        } else {
            let imageWord = fileCount == 1 ? "image" : "images"
            return "Delete from history only, or also permanently delete \(fileCount) \(imageWord)?"
        }
    }
   
    private var confirmDeleteMessage: String {
        let totalItems = entriesToDelete.reduce(into: 0) { $0 += $1.imageCount }
        return "Are you sure? \(totalItems) image\(totalItems == 1 ? "" : "s") will be deleted!"
    }
   
    var body: some View {
        content
            #if os(iOS)
            .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
                Button("Clear", role: .destructive) {
                    appState.historyState.history = []
                    appState.historyState.saveHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all history entries but keep your files intact. Are you sure?")
            }
            #endif
    }
 
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            historyList
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        .alert("Delete History Entries", isPresented: $showDeleteAlert) {
            Button("Delete from History Only") {
                deleteEntries(deleteFiles: false)
            }
            if fileCount > 0 {
                Button("Delete History and Files", role: .destructive) {
                    deleteEntries(deleteFiles: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .overlay {
            overlayContent
        }
    }
 
    private var overlayContent: some View {
        Group {
            #if os(iOS)
            if showAddedMessage {
                Text("Image added to input images")
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
            } else if showToast, let message = toastMessage {
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
                showAddedMessage = false
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
                .help("View past generated images and prompts")
           
            Spacer()
           
            commonActions
        }
        .padding(.horizontal)
        #else
        HStack(spacing: 8) {
            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .kerning(0.2)
                .help("View past generated images and prompts")
           
            Spacer()
           
            commonActions
           
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
                    let insertIndex = 0
                    appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex, into: &snapshot)
                    appState.historyState.history = snapshot
                    appState.historyState.saveHistory()
                    self.selectedIDs.removeAll()
                    self.toastMessage = "Moved \(movedEntries.count) item(s) to top"
                    self.showToast = true
                    self.hideToastAfterDelay()
                }
            }
            return true
        }
        #endif
    }
 
    private var commonActions: some View {
        Group {
            Button(action: {
                appState.historyState.addFolder()
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
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil)
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
                        appState.historyState.moveToBottom(entriesWithIds: Array(selectedIDs), inFolderId: nil)
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
                        toastMessage = "Added \(addedCount) image\(addedCount == 1 ? "" : "s") to input"
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
                .accessibilityLabel("Add selected images to input")
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
                                copyPromptProvider: self.copyPromptToClipboard,
                                folderId: nil,
                                isEditing: isEditingBinding,
                                toastMessage: $toastMessage,
                                showToast: $showToast,
                                addToInputProvider: { item in
                                    self.addToInputImages(item: item)
                                    #if os(iOS)
                                    self.showAddedMessage = true
                                    self.hideToastAfterDelay()
                                    #endif
                                }
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
                            showToast: $showToast
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
                                    copyPromptProvider: self.copyPromptToClipboard,
                                    folderId: nil,
                                    isEditing: isEditingBinding,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast,
                                    addToInputProvider: { item in
                                        self.addToInputImages(item: item)
                                        #if os(iOS)
                                        self.showAddedMessage = true
                                        self.hideToastAfterDelay()
                                        #endif
                                    }
                                )
                            )
                        } moveAction: { from, to in
                            appState.historyState.move(inFolderId: nil, from: from, to: to)
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
                                copyPromptProvider: self.copyPromptToClipboard,
                                folderId: nil,
                                isEditing: isEditingBinding,
                                toastMessage: $toastMessage,
                                showToast: $showToast,
                                addToInputProvider: { item in
                                    self.addToInputImages(item: item)
                                    #if os(iOS)
                                    self.showAddedMessage = true
                                    self.hideToastAfterDelay()
                                    #endif
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            #if os(iOS)
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
   
    // Helper to find the parent folder ID of an item
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
        return nil // Item is in root if no parent folder is found
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
            LazyThumbnailView(item: item)
           
            VStack(alignment: .leading, spacing: 4) {
                Text(item.prompt.prefix(50) + (item.prompt.count > 50 ? "..." : ""))
                    .font(.subheadline)
                    .lineLimit(1)
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
                        #if os(iOS)
                        showAddedMessage = true
                        hideToastAfterDelay()
                        #endif
                    }
                    .accessibilityLabel("Add item to input")
                    Button("Copy Prompt") {
                        copyPromptToClipboard(item.prompt)
                    }
                    .accessibilityLabel("Copy prompt")
                    Button("Delete", role: .destructive) {
                        entriesToDelete = [.item(item)]
                        showDeleteAlert = true
                    }
                    .accessibilityLabel("Delete item")
                    #if os(macOS)
                    Menu("Move to...") {
                        // Compute parent folder ID once
                        let parentFolderId = findParentFolderId(for: item.id, in: appState.historyState.history)
                        // Only show "Root" if the item is not in the root
                        if parentFolderId != nil {
                            Button("Root") {
                                let success = appState.historyState.moveToFolder(entriesWithIds: [item.id], toFolderId: nil)
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
                            .accessibilityLabel("Move item to root")
                        }
                        // Filter out the current parent folder
                        ForEach(appState.historyState.allFolders().filter { $0.id != parentFolderId }) { folderOption in
                            Button(folderOption.name) {
                                let success = appState.historyState.moveToFolder(entriesWithIds: [item.id], toFolderId: folderOption.id)
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
                    .disabled(appState.historyState.allFolders().filter { $0.id != findParentFolderId(for: item.id, in: appState.historyState.history) }.isEmpty && findParentFolderId(for: item.id, in: appState.historyState.history) == nil)
                    .onAppear {
                        print("Context menu for item \(item.id): Move to... menu rendered with \(appState.historyState.allFolders().count) folders")
                    }
                    #endif
                } else if selectedIDs.contains(item.id) {
                    #if os(iOS)
                    Button("Move to Top") {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to top")
                    Button("Move to Bottom") {
                        appState.historyState.moveToBottom(entriesWithIds: Array(selectedIDs), inFolderId: nil)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to bottom"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    .accessibilityLabel("Move selected items to bottom")
                    #endif
                    #if os(macOS)
                    Menu("Move to...") {
                        Button("Root") {
                            let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: nil)
                            if success {
                                selectedIDs.removeAll()
                                toastMessage = selectedIDs.count > 1 ? "Moved \(selectedIDs.count) items to root" : "Moved to root"
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
                            Button(folderOption.name) {
                                let success = appState.historyState.moveToFolder(entriesWithIds: Array(selectedIDs), toFolderId: folderOption.id)
                                if success {
                                    selectedIDs.removeAll()
                                    toastMessage = selectedIDs.count > 1 ? "Moved \(selectedIDs.count) items to \(folderOption.name)" : "Moved to \(folderOption.name)"
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
   
    private func deleteEntries(deleteFiles: Bool) {
        if deleteFiles {
            for entry in entriesToDelete {
                deleteFilesRecursively(entry: entry)
            }
        }
   
        var snapshot = appState.historyState.history
        for entry in entriesToDelete {
            _ = appState.historyState.findAndRemoveEntry(id: entry.id, in: &snapshot)
        }
        appState.historyState.history = snapshot
        appState.historyState.saveHistory()
   
        entriesToDelete = []
        selectedIDs.removeAll()
    }
   
    private func deleteFilesRecursively(entry: HistoryEntry) {
        switch entry {
        case .item(let item):
            guard let path = item.imagePath else { return }
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
   
    private func loadHistoryImage(for item: HistoryItem) -> PlatformImage? {
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
   
    private func addToInputImages(item: HistoryItem) {
        guard let img = loadHistoryImage(for: item), let path = item.imagePath else { return }
        let url = URL(fileURLWithPath: path)
        var promptNodes: [NodeInfo] = []
   
        if url.pathExtension.lowercased() == "png" {
            if let dir = appState.settings.outputDirectory {
                do {
                    promptNodes = try withSecureAccess(to: dir) {
                        parsePromptNodes(from: url)
                    }
                } catch {
                    print("Failed to extract workflow from history PNG: \(error)")
                }
            } else {
                promptNodes = parsePromptNodes(from: url)
            }
        }
   
        var newSlot = ImageSlot(path: path, image: img)
        if !promptNodes.isEmpty {
            newSlot.promptNodes = promptNodes.sorted { $0.id < $1.id }
            newSlot.selectedPromptIndex = 0
        }
        appState.ui.imageSlots.append(newSlot)
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

// HistoryView.swift
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
    @Environment(\.editMode) var editMode
    #endif
    #if os(macOS)
    @State private var isEditing: Bool = false
    #if swift(>=5.7) // Ensure macOS 13.0+ for openWindow
    @Environment(\.openWindow) private var openWindow
    #endif
    #endif
    @State private var activeEntry: HistoryEntry? = nil
    @State private var selectedIDs: Set<UUID> = []
  
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
  
    private var filteredHistory: [HistoryEntry] {
        if searchText.isEmpty {
            return appState.historyState.history
        } else {
            return filterEntries(appState.historyState.history, with: searchText)
        }
    }
  
    private var deleteMessage: String {
        entriesToDelete.count > 1 ? "Do you want to delete these entries from history only or also delete the file(s)?" : "Do you want to delete from history only or also delete the file?"
    }
        
    var body: some View {
        content
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
            Button("Delete from History and File", role: .destructive) {
                let totalItems = entriesToDelete.reduce(into: 0) { $0 += $1.imageCount }
                if totalItems > 1 {
                    showConfirmFileDelete = true
                } else {
                    deleteEntries(deleteFiles: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .alert("Confirm Delete Files", isPresented: $showConfirmFileDelete) {
            Button("Yes", role: .destructive) {
                deleteEntries(deleteFiles: true)
            }
            Button("No", role: .cancel) {}
        }
        .overlay {
            overlayContent
        }
    }

    private var overlayContent: some View {
        Group {
            // Prioritize showAddedMessage on iOS
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
                showAddedMessage = false // Ensure both are cleared
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
           
            if isEditing {
                Button(action: {
                    if !selectedIDs.isEmpty {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay() // Ensure toast disappears
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
                        hideToastAfterDelay() // Ensure toast disappears
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
            }
           
            Button(action: {
                isEditing.toggle()
                if !isEditing {
                    selectedIDs.removeAll()
                }
            }) {
                Text(isEditing ? "Done" : "Select")
            }
            .buttonStyle(.borderless)
            .help("Select multiple items")
            .accessibilityLabel("Select multiple items")
           
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
           
        }
        .padding(.horizontal)
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
                    let insertIndex = 0 // Insert at top for header drop
                    appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex)
                    self.selectedIDs.removeAll()
                    self.toastMessage = "Moved \(movedEntries.count) item(s) to top"
                    self.showToast = true
                    self.hideToastAfterDelay()
                }
            }
            return true
        }
        #else
        HStack(spacing: 8) {
            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .kerning(0.2)
                .help("View past generated images and prompts")
           
            if editMode?.wrappedValue == .active {
                Button(action: {
                    if !selectedIDs.isEmpty {
                        appState.historyState.moveToTop(entriesWithIds: Array(selectedIDs), inFolderId: nil)
                        selectedIDs.removeAll()
                        toastMessage = "Moved to top"
                        showToast = true
                        hideToastAfterDelay() // Ensure toast disappears
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
                        hideToastAfterDelay() // Ensure toast disappears
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
            }
           
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
           
            Spacer()
           
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
           
            EditButton()
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
                    let insertIndex = 0 // Insert at top for header drop
                    appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex)
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
                                    isEditing: $isEditing,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast
                                )
                            )
                        } moveAction: { from, to in
                            appState.historyState.move(inFolderId: nil, from: from, to: to)
                        })
                    } else {
                        AnyView(ForEach(filteredHistory) { entry in
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
                                    isEditing: $isEditing,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast
                                )
                            )
                        })
                    }
                }
            }
            .padding(.horizontal)
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
                        let insertIndex = appState.historyState.history.count
                        appState.historyState.insert(entries: movedEntries, inFolderId: nil, at: insertIndex)
                        self.selectedIDs.removeAll()
                        self.toastMessage = "Moved \(movedEntries.count) item(s)"
                        self.showToast = true
                        self.hideToastAfterDelay()
                    }
                }
                return true
            }
        }
    }
  
    @ViewBuilder
    private func entryRow(for entry: HistoryEntry) -> some View {
        switch entry {
        case .item(let item):
            itemRow(for: item)
                .onDrag {
                    var payload: String
                    var idsToDrag: [UUID]
#if os(iOS)
                    if editMode?.wrappedValue == .active && !selectedIDs.isEmpty {
                        idsToDrag = Array(selectedIDs).sorted()
                    } else {
                        idsToDrag = [entry.id]
                    }
#else
                    if isEditing && !selectedIDs.isEmpty {
                        idsToDrag = Array(selectedIDs).sorted()
                    } else {
                        idsToDrag = [entry.id]
                    }
#endif
                    payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
                    return NSItemProvider(object: payload as NSString)
                }
        case .folder(let folder):
            HStack {
#if os(iOS)
                if editMode?.wrappedValue == .active {
                    Image(systemName: selectedIDs.contains(folder.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                }
#else
                if isEditing {
                    Image(systemName: selectedIDs.contains(folder.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 20))
                }
#endif
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.secondary) // Optional: Match thumbnail style
                    .help("Folder icon")
                Text(folder.name)
            }
            .contentShape(Rectangle())
#if os(iOS)
            .onTapGesture {
                if editMode?.wrappedValue == .active {
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
#else
            .onTapGesture {
                if isEditing {
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
#endif
            .onDrag {
                var payload: String
                var idsToDrag: [UUID]
#if os(iOS)
                if editMode?.wrappedValue == .active && !selectedIDs.isEmpty {
                    idsToDrag = Array(selectedIDs).sorted()
                } else {
                    idsToDrag = [entry.id]
                }
#else
                if isEditing && !selectedIDs.isEmpty {
                    idsToDrag = Array(selectedIDs).sorted()
                } else {
                    idsToDrag = [entry.id]
                }
#endif
                payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
                return NSItemProvider(object: payload as NSString)
            }
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
            #if os(iOS)
            if editMode?.wrappedValue == .active {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 20))
            }
            #else
            if isEditing {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 20))
            }
            #endif
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
           
            Button(action: {
                #if os(macOS)
                #if swift(>=5.7) // macOS 13.0+
                openWindow(id: "history-viewer", value: item.id)
                #else
                fullHistoryItemId = item.id
                #endif
                #else
                appState.presentedModal = .fullHistoryItem(item.id)
                #endif
            }) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.blue.opacity(0.8))
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("View full image")
            .accessibilityLabel("View full image")
           
            Button(action: {
                entriesToDelete = [.item(item)]
                showDeleteAlert = true
            }) {
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red.opacity(0.8))
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Delete history item")
            .accessibilityLabel("Delete history item")
           
            Button(action: {
                addToInputImages(item: item)
                #if os(iOS)
                showAddedMessage = true
                hideToastAfterDelay()
                #endif
            }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue.opacity(0.8))
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Add to input images")
            .accessibilityLabel("Add to input images")
        }
        .padding(.vertical, 4)
        #if os(iOS)
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode?.wrappedValue == .active {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            }
        }
        #else
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            }
        }
        #endif
        .onDrag {
            var payload: String
            var idsToDrag: [UUID]
            #if os(iOS)
            if editMode?.wrappedValue == .active && !selectedIDs.isEmpty {
                idsToDrag = Array(selectedIDs).sorted()
            } else {
                idsToDrag = [item.id]
            }
            #else
            if isEditing && !selectedIDs.isEmpty {
                idsToDrag = Array(selectedIDs).sorted()
            } else {
                idsToDrag = [item.id]
            }
            #endif
            payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
            return NSItemProvider(object: payload as NSString)
        }
    }
  
    private func copyPromptToClipboard(_ prompt: String) {
        PlatformPasteboard.clearContents()
        PlatformPasteboard.writeString(prompt)
    }
  
    private func deleteEntries(deleteFiles: Bool) {
        if deleteFiles {
            for entry in entriesToDelete {
                deleteFilesRecursively(entry: entry)
            }
        }
        
        for entry in entriesToDelete {
            _ = appState.historyState.findAndRemoveEntry(with: entry.id)
        }
        
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
                    // Handle error if needed, e.g., print("Failed to delete file: \(error)")
                }
            } else {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    // Handle error if needed
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
  
    // Helper to filter entries recursively
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
}


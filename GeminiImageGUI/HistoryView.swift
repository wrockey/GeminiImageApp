import SwiftUI
#if os(macOS)
import AppKit
#endif

extension UUID: Identifiable {
    public var id: UUID { self }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct HistoryView: View {
    @Binding var imageSlots: [ImageSlot]
    @EnvironmentObject var appState: AppState
    @State private var showDeleteAlert: Bool = false
    @State private var selectedHistoryItem: HistoryItem?
    @State private var showClearHistoryAlert: Bool = false
    @State private var searchText: String = ""
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var fullHistoryItemId: UUID? = nil
    @State private var showAddedMessage: Bool = false
   
    #if os(macOS)
    @available(macOS 13.0, *)
    @Environment(\.openWindow) private var openWindow
    #else
    @Environment(\.dismiss) private var dismiss // ADDED: To dismiss the history sheet on iOS
    #endif
   
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
   
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Reduced spacing to 0 to minimize gaps
            header
            searchField
            historyList
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity) // Added maxWidth: .infinity for better iOS sizing
        .alert("Delete History Item", isPresented: $showDeleteAlert) {
            Button("Delete from History Only") {
                deleteHistoryItem(deleteFile: false)
            }
            Button("Delete from History and File", role: .destructive) {
                deleteHistoryItem(deleteFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message : {
            Text("Do you want to delete from history only or also delete the file?")
        }
        .alert("Clear History", isPresented: $showClearHistoryAlert) {
            Button("Yes", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear the history?")
        }
        #if os(iOS)
        .overlay {
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
            }
        }
        #endif
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

            Button(action: {
                showClearHistoryAlert = true
            }) {
                Image(systemName: "trash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Clear all history")
            .accessibilityLabel("Clear all history")
        }
        .padding(.horizontal)
        #else
        HStack(spacing: 8) {
            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .kerning(0.2)
                .help("View past generated images and prompts")
           
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
           
            Button(action: {
                showClearHistoryAlert = true
            }) {
                Image(systemName: "trash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Clear all history")
            .accessibilityLabel("Clear all history")
           
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
        }
        .padding(.horizontal)
        .padding(.vertical, 8) // Reduced vertical padding to minimize space above
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
        List {
            if filteredHistory.isEmpty {
                Text("No history yet.")
                    .foregroundColor(.secondary)
                    .help("No generation history available yet")
            } else {
                OutlineGroup(filteredHistory, children: \.childrenForOutline) { entry in
                    entryRow(for: entry)
                }
            }
        }
        .listStyle(.plain)
    }
   
    @ViewBuilder
    private func entryRow(for entry: HistoryEntry) -> some View {
        switch entry {
        case .item(let item):
            itemRow(for: item)
                .contextMenu {
                    Button("Delete") {
                        selectedHistoryItem = item
                        showDeleteAlert = true
                    }
                }
                .onDrag {
                    NSItemProvider(object: item.id.uuidString as NSString)
                }
        case .folder(let folder):
            Text(folder.name)
                .contextMenu {
                    Button("Delete Folder") {
                        _ = appState.historyState.findAndRemoveEntry(with: folder.id)
                    }
                }
                .onDrop(of: [.text], delegate: FolderDropDelegate(folder: folder, appState: appState))
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
                if #available(macOS 13.0, *) {
                    openWindow(id: "history-viewer", value: item.id)
                } else {
                    // Fallback for older macOS if needed
                }
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
                selectedHistoryItem = item
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showAddedMessage = false
                    }
                }
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
        .contextMenu {
            Button("Copy Prompt") {
                copyPromptToClipboard(item.prompt)
            }
            .help("Copy the prompt to clipboard")
        }
        .draggable(item.imagePath.map { URL(fileURLWithPath: $0) } ?? URL(string: "")!)
    }
   
    // New custom view for lazy thumbnail loading
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
   
    private func copyPromptToClipboard(_ prompt: String) {
        PlatformPasteboard.clearContents()
        PlatformPasteboard.writeString(prompt)
    }
   
    private func deleteHistoryItem(deleteFile: Bool) {
        guard let item = selectedHistoryItem else { return }
       
        if deleteFile, let path = item.imagePath {
            let fileURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if let dir = appState.settings.outputDirectory {
                do {
                    try withSecureAccess(to: dir) {
                        try fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    // Handle error if needed, but for simplicity, skip alert here
                }
            }
        }
       
        _ = appState.historyState.findAndRemoveEntry(with: item.id)
       
        selectedHistoryItem = nil
    }
   
    private func clearHistory() {
        appState.historyState.history.removeAll()
        appState.historyState.saveHistory()
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

struct FullHistoryItemView: View {
    let initialId: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss // Removed #if os(iOS) to enable on macOS
    @State private var selectedId: UUID? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var previousSelectedId: UUID? = nil
    @State private var showCopiedMessage: Bool = false
    @State private var showAddedMessage: Bool = false
    @State private var previousHistory: [HistoryItem] = []
    @State private var isFullScreen: Bool = false
   
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
   
    private var history: [HistoryItem] {
        flattenHistory(appState.historyState.history).sorted(by: { $0.date > $1.date })
    }
   
    private var currentItem: HistoryItem? {
        history.first { $0.id == selectedId }
    }
   
    private var currentIndex: Int? {
        history.firstIndex { $0.id == selectedId }
    }
   
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                #if os(iOS) || os(macOS)
                if #available(iOS 17.0, macOS 14.0, *) {
                    horizontalScrollView(for: geometry)
                } else {
                    fallbackHorizontalView(for: geometry)
                }
                #endif
            }
            .overlay(alignment: .bottom) {
                if let item = currentItem {
                    bottomOverlay(for: item)
                }
            }
            .overlay(alignment: .topTrailing) {
                closeButton
            }
        }
        .ignoresSafeArea()
        .alert("Delete History Item", isPresented: $showDeleteAlert) {
            Button("Delete from History Only") {
                if let item = currentItem {
                    deleteHistoryItem(item: item, deleteFile: false)
                }
            }
            Button("Delete History and File", role: .destructive) {
                if let item = currentItem {
                    deleteHistoryItem(item: item, deleteFile: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to delete from history only or also delete the file?")
        }
        .overlay {
            if showCopiedMessage {
                Text("Copied to Clipboard")
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .help("Confirmation: Prompt copied to clipboard")
            }
        }
        .overlay {
            if showAddedMessage {
                Text("Image added to input slot")
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .help("Confirmation: Image added to input slot")
            }
        }
        .onAppear {
            selectedId = initialId
            previousHistory = history
            previousSelectedId = nil // Initialize previous
            #if os(macOS)
            updateWindowSize()
            if let window = NSApp.windows.last {
                isFullScreen = window.styleMask.contains(.fullScreen)
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = true
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
                isFullScreen = false
            }
            #endif
        }
        .onChange(of: history) { newHistory in
            if let sid = selectedId, !newHistory.contains(where: { $0.id == sid }) {
                if newHistory.isEmpty {
                    selectedId = nil
                    dismiss()
                } else {
                    let oldSorted = previousHistory
                    if let oldIdx = oldSorted.firstIndex(where: { $0.id == sid }) {
                        let newIdx = min(oldIdx, newHistory.count - 1)
                        selectedId = newHistory[newIdx].id
                    } else {
                        selectedId = newHistory.first?.id
                    }
                }
            }
            previousHistory = newHistory
        }
        .onChange(of: selectedId) { newValue in
            let oldValue = previousSelectedId
            print("Selected ID changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")")
            if let item = history.first(where: { $0.id == newValue }) {
                print("Current prompt: \(item.prompt)")
                print("Current date: \(dateFormatter.string(from: item.date))")
                if let mode = item.mode {
                    let creator: String = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : item.workflowName ?? "ComfyUI"
                    print("Created with: \(creator)")
                }
            } else {
                print("No item found for selected ID")
            }
            previousSelectedId = newValue // Update previous for next change
        }
    }
   
    // NEW: Modern horizontal scroll for iOS 17+/macOS 14+
    @available(iOS 17.0, macOS 14.0, *)
    private func horizontalScrollView(for geometry: GeometryProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(history) { item in
                    HistoryImageDisplay(item: item)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(item.id) // Ensure scrollPosition tracks correctly
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollTargetLayout()
        .scrollPosition(id: $selectedId)
        #if os(macOS)
        .focusable()
        .onKeyPress { press in
            if press.phase == .down {
                if press.key == .leftArrow {
                    if let idx = currentIndex, idx > 0 {
                        selectedId = history[idx - 1].id
                        return .handled
                    }
                } else if press.key == .rightArrow {
                    if let idx = currentIndex, idx < history.count - 1 {
                        selectedId = history[idx + 1].id
                        return .handled
                    }
                }
            }
            return .ignored
        }
        #endif
    }
   
    // NEW: Fallback for older versions
    private func fallbackHorizontalView(for geometry: GeometryProxy) -> some View {
        #if os(iOS)
        TabView(selection: $selectedId) {
            ForEach(history) { item in
                HistoryImageDisplay(item: item)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tag(item.id as UUID?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(history) { item in
                    HistoryImageDisplay(item: item)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        #endif
    }
   
    // NEW: Subview for image/no-image display
    private struct HistoryImageDisplay: View {
        let item: HistoryItem
        @EnvironmentObject var appState: AppState
       
        var body: some View {
            if let img = loadHistoryImage(for: item) {
                Image(platformImage: img)
                    .resizable()
                    .scaledToFit()
                    .shadow(radius: 5)
                    .help("Full view of generated image")
                    .accessibilityLabel("Image generated with prompt: \(item.prompt)")
            } else {
                Text("No image available")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .help("No image available for this history item")
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
    }
   
    // NEW: Extracted bottom overlay
    private func bottomOverlay(for item: HistoryItem) -> some View {
        var creator: String? = nil
        if let mode = item.mode {
            creator = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : item.workflowName ?? "ComfyUI"
            
            if let idx = item.indexInBatch, let tot = item.totalInBatch {
                creator! += " #\(idx + 1) of \(tot)"
            }
        }
        
        return VStack(spacing: 4) {
            VStack(alignment: .center, spacing: 2) {
                HStack(alignment: .center) {
                    Text("Prompt: \(item.prompt)")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .foregroundColor(.black)
                        .help("The prompt used for this image")
                        .accessibilityLabel("Prompt: \(item.prompt)")
                    Button(action: {
                        copyPromptToClipboard(item.prompt)
                        showCopiedMessage = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showCopiedMessage = false
                            }
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue.opacity(0.8))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy prompt to clipboard")
                    .accessibilityLabel("Copy prompt")
                }
                Text("Date: \(dateFormatter.string(from: item.date))")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .help("Date the image was generated")
                if let creator = creator {
                    Text("Created with: \(creator)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .help("Generation mode or workflow used")
                }
            }
            
            HStack {
                Button(action: {
                    if let idx = currentIndex {
                        let newIdx = max(0, idx - 1)
                        selectedId = history[newIdx].id
                    }
                }) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.black)
                }
                .disabled(currentIndex == 0)
                .buttonStyle(.plain)
                .help("Previous image in history")
                .accessibilityLabel("Previous image")
                
                Spacer()
                
                Button(action: {
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete this history item")
                .accessibilityLabel("Delete item")
                
                Spacer()
                
                Button(action: {
                    addToInputImages(item: item)
                    showAddedMessage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showAddedMessage = false
                        }
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Add to input images")
                .accessibilityLabel("Add to input slot")
                
                Spacer()
                
                Button(action: {
                    if let idx = currentIndex {
                        let newIdx = min(history.count - 1, idx + 1)
                        selectedId = history[newIdx].id
                    }
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.black)
                }
                .disabled(currentIndex == history.count - 1)
                .buttonStyle(.plain)
                .help("Next image in history")
                .accessibilityLabel("Next image")
            }
        }
        .padding(8)
        .background(Color.white)
        .frame(maxWidth: .infinity)
    }
   
    // NEW: Extracted close button
    private var closeButton: some View {
        #if os(iOS)
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
        .padding()
        .help("Close full image view")
        .accessibilityLabel("Close")
        #elseif os(macOS)
        Group {
            if isFullScreen {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding()
                .help("Close full image view")
                .accessibilityLabel("Close")
            } else {
                EmptyView()
            }
        }
        #endif
    }
   
   
    private func deleteHistoryItem(item: HistoryItem, deleteFile: Bool) {
        // Compute sorted history and current index before deletion
        let currentHistory = flattenHistory(appState.historyState.history).sorted(by: { $0.date > $1.date })
        guard let oldIdx = currentHistory.firstIndex(where: { $0.id == item.id }) else { return }
       
        if deleteFile, let path = item.imagePath {
            let fileURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if let dir = appState.settings.outputDirectory {
                do {
                    try withSecureAccess(to: dir) {
                        try fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    // Handle error if needed
                }
            }
        }
       
        _ = appState.historyState.findAndRemoveEntry(with: item.id)
       
        // Recompute sorted history after deletion
        let newHistory = flattenHistory(appState.historyState.history).sorted(by: { $0.date > $1.date })
        if newHistory.isEmpty {
            selectedId = nil
        } else {
            let newIdx = min(oldIdx, newHistory.count - 1)
            selectedId = newHistory[newIdx].id
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
    private func copyPromptToClipboard(_ prompt: String) {
        PlatformPasteboard.clearContents()
        PlatformPasteboard.writeString(prompt)
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
   
    private func updateWindowSize() {
        #if os(macOS)
        guard let item = currentItem,
              let platformImage = loadHistoryImage(for: item),
              let window = NSApp.windows.last,
              let screen = NSScreen.main else {
            return
        }
       
        let bottomHeight: CGFloat = 100 // Approximate height for bottom overlay
        let minWidth: CGFloat = 400
        let imageSize = platformImage.size // Assuming .size for NSImage
        var desiredSize = CGSize(width: max(imageSize.width, minWidth), height: imageSize.height + bottomHeight)
       
        // Account for screen visible area (excluding menu bar, dock, etc.)
        let screenSize = screen.visibleFrame.size
        let marginHorizontal: CGFloat = 40 // Small margin for sides
        let marginVertical: CGFloat = 100 // Margin for top/bottom (menu bar, dock)
       
        let maxSize = CGSize(width: screenSize.width - marginHorizontal,
                             height: screenSize.height - marginVertical)
       
        // Calculate scale to fit within max size if needed
        let scale = min(1.0, min(maxSize.width / desiredSize.width, maxSize.height / desiredSize.height))
       
        let windowSize = CGSize(width: desiredSize.width * scale, height: desiredSize.height * scale)
       
        window.setContentSize(windowSize)
        window.center() // Center the window on the screen
        #endif
    }
    
    // Helper to flatten history for FullHistoryItemView
    private func flattenHistory(_ entries: [HistoryEntry]) -> [HistoryItem] {
        var items: [HistoryItem] = []
        for entry in entries {
            switch entry {
            case .item(let item):
                items.append(item)
            case .folder(let folder):
                items.append(contentsOf: flattenHistory(folder.children))
            }
        }
        return items
    }
}

struct FolderDropDelegate: DropDelegate {
    let folder: Folder
    let appState: AppState

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { (string, _) in
            if let idString = string as? String, let id = UUID(uuidString: idString),
               let movedEntry = appState.historyState.findAndRemoveEntry(with: id) {
                DispatchQueue.main.async {
                    appState.historyState.addEntry(movedEntry, toFolderWithId: folder.id)
                }
            }
        }
        return true
    }
}

// HistoryView.swift
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
    
    private var filteredHistory: [HistoryItem] {
        if searchText.isEmpty {
            return appState.historyState.history
        } else {
            return appState.historyState.history.filter { item in
                item.prompt.lowercased().contains(searchText.lowercased()) ||
                dateFormatter.string(from: item.date).lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Reduced spacing to 0 to minimize gaps
            header
            searchField
            historyList
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity) // Added maxWidth: .infinity for better iOS sizing
        .alert("Delete History Item", isPresented: $showDeleteAlert) {
            Button("Delete Prompt Only") {
                deleteHistoryItem(deleteFile: false)
            }
            Button("Delete Prompt and Image File", role: .destructive) {
                deleteHistoryItem(deleteFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message : {
            Text("Do you want to delete just the prompt or also the associated image file?")
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
        .fullScreenCover(item: $fullHistoryItemId) { id in
            FullHistoryItemView(initialId: id)
                .environmentObject(appState)
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
            
            Spacer()
            
            Button(action: {
                showClearHistoryAlert = true
            }) {
                Image(systemName: "trash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Clear all history")
        }
        .padding(.horizontal)
        #else
        HStack(spacing: 8) {

            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .kerning(0.2)
            
            Button(action: {
                showClearHistoryAlert = true
            }) {
                Image(systemName: "trash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Clear all history")
            
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
        }
        .padding(.horizontal)
        .padding(.vertical, 8) // Reduced vertical padding to minimize space above
        #endif
    }
    
    private var searchField: some View {
        TextField("Search prompts or dates...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
    }
    
    private var historyList: some View {
        List {
            if filteredHistory.isEmpty {
                Text("No history yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredHistory.sorted(by: { $0.date > $1.date })) { item in
                    itemRow(for: item)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func itemRow(for item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            LazyThumbnailView(item: item)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.prompt.prefix(50) + (item.prompt.count > 50 ? "..." : ""))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(dateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let mode = item.mode {
                    Text(mode == .gemini ? "Gemini" : (item.workflowName ?? "ComfyUI"))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                fullHistoryItemId = item.id
                #endif
            }) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.blue.opacity(0.8))
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("View full image")
            
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
            
            Button(action: {
                addToInputImages(item: item)
            }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue.opacity(0.8))
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Add to input images")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Prompt") {
                copyPromptToClipboard(item.prompt)
            }
        }
        .draggable(item.imagePath.map { URL(fileURLWithPath: $0) } ?? URL(string: "")!)
    }
    
    // New custom view for lazy thumbnail loading
    struct LazyThumbnailView: View {
        let item: HistoryItem
        @State private var thumbnail: PlatformImage? = nil
        @EnvironmentObject var appState: AppState
        
        var body: some View {
            Group {
                if let img = thumbnail {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
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
        
        if let index = appState.historyState.history.firstIndex(where: { $0.id == item.id }) {
            appState.historyState.history.remove(at: index)
            appState.historyState.saveHistory()
        }
        
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
}

struct FullHistoryItemView: View {
    let initialId: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss // Removed #if os(iOS) to enable on macOS
    @State private var selectedId: UUID? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var previousSelectedId: UUID? = nil
    @State private var showCopiedMessage: Bool = false
    @State private var previousHistory: [HistoryItem] = []
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    private var history: [HistoryItem] {
        appState.historyState.history.sorted(by: { $0.date > $1.date })
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(history) { item in
                                Group {
                                    if let img = loadHistoryImage(for: item) {
                                        Image(platformImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .shadow(radius: 5)
                                    } else {
                                        Text("No image available")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(item.id) // Ensure scrollPosition tracks correctly
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollTargetLayout()
                    .scrollPosition(id: $selectedId)
                } else {
                    #if os(iOS)
                    TabView(selection: $selectedId) {
                        ForEach(history) { item in
                            if let img = loadHistoryImage(for: item) {
                                Image(platformImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .shadow(radius: 5)
                                    .tag(item.id as UUID?)
                            } else {
                                Text("No image available")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .tag(item.id as UUID?)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    #else
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(history) { item in
                                GeometryReader { proxy in
                                    if let img = loadHistoryImage(for: item) {
                                        Image(platformImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .shadow(radius: 5)
                                    } else {
                                        Text("No image available")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    #endif
                }
                #endif
                
            }
            .overlay(alignment: .bottom) {
                if let item = currentItem {
                    VStack(spacing: 4) {
                        VStack(alignment: .center, spacing: 2) {
                            HStack(alignment: .center) {
                                Text("Prompt: \(item.prompt)")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .foregroundColor(.black)
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
                            }
                            Text("Date: \(dateFormatter.string(from: item.date))")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            if let mode = item.mode {
                                Text("Created with: \(mode == .gemini ? "Gemini" : (item.workflowName ?? "ComfyUI"))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
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
                            
                            Spacer()
                            
                            Button(action: {
                                addToInputImages(item: item)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundColor(.blue.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Add to input images")
                            
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
                        }
                    }
                    .padding(8)
                    .background(Color.white)
                    .frame(maxWidth: .infinity)
                }
            }
            #if os(iOS)
            .overlay(alignment: .topTrailing) {
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
            }
            #endif
        }
        .ignoresSafeArea()
        .alert("Delete History Item", isPresented: $showDeleteAlert) {
            Button("Delete Prompt Only") {
                if let item = currentItem {
                    deleteHistoryItem(item: item, deleteFile: false)
                }
            }
            Button("Delete Prompt and Image File", role: .destructive) {
                if let item = currentItem {
                    deleteHistoryItem(item: item, deleteFile: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to delete just the prompt or also the associated image file?")
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
            }
        }
        .onAppear {
            selectedId = initialId
            previousHistory = history
            previousSelectedId = nil // Initialize previous
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
            if #available(iOS 17.0, macOS 14.0, *) {
                // This branch is not needed since the single-param .onChange works on 17+ too, but for clarity
            }
            let oldValue = previousSelectedId
            print("Selected ID changed from \(oldValue?.uuidString ?? "nil") to \(newValue?.uuidString ?? "nil")")
            if let item = history.first(where: { $0.id == newValue }) {
                print("Current prompt: \(item.prompt)")
                print("Current date: \(dateFormatter.string(from: item.date))")
                if let mode = item.mode {
                    print("Created with: \(mode == .gemini ? "Gemini" : (item.workflowName ?? "ComfyUI"))")
                }
            } else {
                print("No item found for selected ID")
            }
            previousSelectedId = newValue // Update previous for next change
        }
    }

    
    private func deleteHistoryItem(item: HistoryItem, deleteFile: Bool) {
        // Compute sorted history and current index before deletion
        let currentHistory = appState.historyState.history.sorted(by: { $0.date > $1.date })
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
        
        if let index = appState.historyState.history.firstIndex(where: { $0.id == item.id }) {
            appState.historyState.history.remove(at: index)
            appState.historyState.saveHistory()
        }
        
        // Recompute sorted history after deletion
        let newHistory = appState.historyState.history.sorted(by: { $0.date > $1.date })
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
}


// HistoryFullView.swift
import SwiftUI
#if os(macOS)
import AppKit
#endif
 
struct FullHistoryItemView: View {
    let initialId: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
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
        flattenHistory(appState.historyState.history)
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
            previousSelectedId = nil
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
            if let item = history.first(where: { $0.id == newValue }) {
                if let mode = item.mode {
                    let creator: String = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : item.workflowName ?? "ComfyUI"
                }
            } else {
            }
            previousSelectedId = newValue
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
                        .id(item.id)
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
        let currentHistory = flattenHistory(appState.historyState.history)
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
                    print("Failed to delete file: \(error)")
                }
            } else {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    print("Failed to delete file: \(error)")
                }
            }
        }
   
        var snapshot = appState.historyState.history
        _ = appState.historyState.findAndRemoveEntry(id: item.id, in: &snapshot)
        appState.historyState.history = snapshot
        appState.historyState.saveHistory()
   
        let newHistory = flattenHistory(appState.historyState.history)
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
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = prompt
        #endif
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
        let imageSize = platformImage.size
        var desiredSize = CGSize(width: max(imageSize.width, minWidth), height: imageSize.height + bottomHeight)
   
        let screenSize = screen.visibleFrame.size
        let marginHorizontal: CGFloat = 40
        let marginVertical: CGFloat = 100
   
        let maxSize = CGSize(width: screenSize.width - marginHorizontal,
                            height: screenSize.height - marginVertical)
   
        let scale = min(1.0, min(maxSize.width / desiredSize.width, maxSize.height / desiredSize.height))
   
        let windowSize = CGSize(width: desiredSize.width * scale, height: desiredSize.height * scale)
   
        window.setContentSize(windowSize)
        window.center()
        #endif
    }
   
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

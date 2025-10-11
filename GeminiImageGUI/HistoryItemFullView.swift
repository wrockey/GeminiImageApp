//HistoryItemFullView.swift
import SwiftUI
import AVKit
import AVFoundation
#if os(macOS)
import AppKit
#endif
 
struct FullHistoryItemView: View {
    let initialId: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedId: UUID? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var previousSelectedId: UUID? = nil
    @State private var showCopiedMessage: Bool = false
    @State private var showAddedMessage: Bool = false
    @State private var previousHistory: [HistoryItem] = []
    @State private var isFullScreen: Bool = false
    @State private var recentlyDeletedId: UUID? = nil
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // Default for videos
    @State private var isVideoPlayable: Bool = false
   
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
   
    private var hasFile: Bool {
        currentItem?.imagePath != nil
    }
   
    private var fileExists: Bool {
        guard let item = currentItem else { return false }
        return item.fileExists(appState: appState)
    }
   
    private var deleteMessage: String {
        var msg = "Are you sure you want to delete this item from history?"
        if hasFile && !fileExists {
            msg += "\nNote: File is missing or inaccessible."
        }
        return msg
    }
   
    var body: some View {
        mainContent
            .ignoresSafeArea()
            .overlay(bottomOverlay, alignment: .bottom)
            .overlay(closeButton, alignment: .topTrailing)
            .overlay(copiedMessageOverlay, alignment: .top)
            .overlay(addedMessageOverlay, alignment: .top)
            .onAppear(perform: onAppear)
            .onChange(of: history, perform: onHistoryChange)
            .onChange(of: selectedId, perform: onSelectedIdChange)
            .onChange(of: currentItem) { _ in
                Task {
                    await loadVideoMetadata()
                }
            }
            .sheet(isPresented: $showDeleteAlert) {
                DeleteConfirmationView(
                    title: "Delete Item",
                    message: deleteMessage,
                    hasDeletableFiles: hasFile && fileExists,
                    deleteAction: { deleteFiles in
                        if let item = currentItem {
                            recentlyDeletedId = item.id
                            deleteHistoryItem(item: item, deleteFile: deleteFiles)
                        }
                    },
                    cancelAction: {}
                )
            }
    }
   
    private var mainContent: some View {
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
        }
    }
   
    @ViewBuilder private var bottomOverlay: some View {
        if let item = currentItem {
            bottomOverlay(for: item)
        } else {
            Color.clear.frame(height: 0)
        }
    }
   
    @ViewBuilder private var closeButton: some View {
        #if os(iOS)
        Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
        .padding()
        .help("Close full view")
        .accessibilityLabel("Close")
        #elseif os(macOS)
        if isFullScreen {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .padding()
            .help("Close full view")
            .accessibilityLabel("Close")
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
        #endif
    }
   
    @ViewBuilder private var copiedMessageOverlay: some View {
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
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showCopiedMessage = false
                        }
                    }
                }
        } else {
            Color.clear.frame(height: 0)
        }
    }
   
    @ViewBuilder private var addedMessageOverlay: some View {
        if showAddedMessage {
            Text("Item added to input slot")
                .font(.headline)
                .padding()
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
                .transition(.opacity)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 50)
                .help("Confirmation: Item added to input slot")
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showAddedMessage = false
                        }
                    }
                }
        } else {
            Color.clear.frame(height: 0)
        }
    }
   
    private func onAppear() {
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
   
    private func onHistoryChange(newHistory: [HistoryItem]) {
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
        } else if let deletedId = recentlyDeletedId, newHistory.contains(where: { $0.id == deletedId }) {
            selectedId = deletedId
            recentlyDeletedId = nil
        }
        previousHistory = newHistory
    }
   
    private func onSelectedIdChange(newValue: UUID?) {
        let oldValue = previousSelectedId
        if let item = history.first(where: { $0.id == newValue }) {
            if let mode = item.mode {
                let creator: String = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : item.workflowName ?? "ComfyUI"
            }
        }
        previousSelectedId = newValue
    }
   
    @available(iOS 17.0, macOS 14.0, *)
    private func horizontalScrollView(for geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(history) { item in
                        HistoryImageDisplay(item: item, isVideoPlayable: $isVideoPlayable, videoAspectRatio: $videoAspectRatio)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedId)
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(selectedId)
                }
            }
            .onChange(of: selectedId) { newId in
                withAnimation {
                    proxy.scrollTo(newId)
                }
            }
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
    }
   
    private func fallbackHorizontalView(for geometry: GeometryProxy) -> some View {
        #if os(iOS)
        TabView(selection: $selectedId) {
            ForEach(history) { item in
                HistoryImageDisplay(item: item, isVideoPlayable: $isVideoPlayable, videoAspectRatio: $videoAspectRatio)
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
                    HistoryImageDisplay(item: item, isVideoPlayable: $isVideoPlayable, videoAspectRatio: $videoAspectRatio)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        #endif
    }
   
    private struct HistoryImageDisplay: View {
        let item: HistoryItem
        @EnvironmentObject var appState: AppState
        @Binding var isVideoPlayable: Bool
        @Binding var videoAspectRatio: CGFloat
        @State private var thumbnail: PlatformImage? = nil
       
        var body: some View {
            Group {
                if let path = item.imagePath, path.hasSuffix(".mp4") {
                    let fileURL = URL(fileURLWithPath: path)
                    if isVideoPlayable && fileExists(item: item) {
                        VideoPlayer(player: AVPlayer(url: fileURL))
                            .aspectRatio(videoAspectRatio, contentMode: .fit)
                            .help("Full view of generated video")
                            .accessibilityLabel("Video generated with prompt: \(item.prompt)")
                    } else {
                        if let img = thumbnail {
                            Image(platformImage: img)
                                .resizable()
                                .scaledToFit()
                                .shadow(radius: 5)
                                .help("Thumbnail of unplayable video")
                                .accessibilityLabel("Unplayable video thumbnail for prompt: \(item.prompt)")
                        } else {
                            Text("Video unavailable")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .help("Video file is missing or unplayable")
                                .accessibilityLabel("Video unavailable")
                        }
                    }
                } else if let img = loadHistoryImage(for: item) {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFit()
                        .shadow(radius: 5)
                        .help("Full view of generated image")
                        .accessibilityLabel("Image generated with prompt: \(item.prompt)")
                } else {
                    Text("No media available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .help("No image or video available for this history item")
                        .accessibilityLabel("No media available")
                }
            }
            .onAppear {
                Task {
                    thumbnail = await loadThumbnail(for: item)
                }
            }
        }
       
        private func loadHistoryImage(for item: HistoryItem) -> PlatformImage? {
            guard let path = item.imagePath, !path.hasSuffix(".mp4") else { return nil }
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
       
        private func loadThumbnail(for item: HistoryItem) async -> PlatformImage? {
            guard let path = item.imagePath, path.hasSuffix(".mp4") else { return nil }
            return await LazyThumbnailView.loadImage(for: item, appState: appState)
        }
       
        private func fileExists(item: HistoryItem) -> Bool {
            item.fileExists(appState: appState)
        }
    }
   
    private func loadVideoMetadata() async {
        guard let item = currentItem, let path = item.imagePath, path.hasSuffix(".mp4") else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            return
        }
        let fileURL = URL(fileURLWithPath: path)
        guard fileExists(item: item) else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            return
        }
       
        let asset = AVAsset(url: fileURL)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                isVideoPlayable = false
                videoAspectRatio = 16.0 / 9.0
                return
            }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let naturalSize = try await tracks.first?.load(.naturalSize) ?? CGSize(width: 16, height: 9)
            isVideoPlayable = true
            videoAspectRatio = naturalSize.width / naturalSize.height
        } catch {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
        }
    }
   
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
                        .foregroundColor(.primary)
                        .help("The prompt used for this item")
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
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy prompt to clipboard")
                    .accessibilityLabel("Copy prompt")
                }
                Text("Date: \(dateFormatter.string(from: item.date))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .help("Date the item was generated")
                if let creator = creator {
                    Text("Created with: \(creator)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .help("Generation mode or model used")
                }
            }
           
            HStack(spacing: 16) {
                // Group 1: Navigation (Previous/Next)
                HStack(spacing: 8) {
                    Button(action: {
                        if let idx = currentIndex {
                            let newIdx = max(0, idx - 1)
                            selectedId = history[newIdx].id
                        }
                    }) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.primary)
                    }
                    .disabled(currentIndex == 0)
                    .buttonStyle(.plain)
                    .help("Previous item in history")
                    .accessibilityLabel("Previous item")
                   
                    Button(action: {
                        if let idx = currentIndex {
                            let newIdx = min(history.count - 1, idx + 1)
                            selectedId = history[newIdx].id
                        }
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.primary)
                    }
                    .disabled(currentIndex == history.count - 1)
                    .buttonStyle(.plain)
                    .help("Next item in history")
                    .accessibilityLabel("Next item")
                }
               
                // Group 2: Video controls or Image actions
                if item.imagePath?.hasSuffix(".mp4") ?? false, isVideoPlayable, fileExists(item: item) {
                    HStack(spacing: 8) {
                        Text("Video Controls") // Placeholder for VideoPlayer's built-in controls
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .help("Video playback controls")
                            .accessibilityLabel("Video playback controls")
                    }
                } else {
                    HStack(spacing: 8) {
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
                    }
                }
               
                // Group 3: Delete, Undo/Redo
                HStack(spacing: 8) {
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
                   
                    Button(action: {
                        undoManager?.undo()
                    }) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!(undoManager?.canUndo ?? false))
                    .help("Undo last action")
                    .accessibilityLabel("Undo")
                   
                    Button(action: {
                        undoManager?.redo()
                    }) {
                        Image(systemName: "arrow.uturn.right")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!(undoManager?.canRedo ?? false))
                    .help("Redo last action")
                    .accessibilityLabel("Redo")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(8)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .frame(maxWidth: .infinity)
    }
   
    private func deleteHistoryItem(item: HistoryItem, deleteFile: Bool) {
        let oldHistory = appState.historyState.history
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
       
        if let undoManager = undoManager {
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
            undoManager.setActionName("Delete Item")
        }
       
        let newHistory = flattenHistory(appState.historyState.history)
        if newHistory.isEmpty {
            selectedId = nil
            dismiss()
        } else {
            let newIdx = min(oldIdx, newHistory.count - 1)
            selectedId = newHistory[newIdx].id
        }
    }
   
    private func loadHistoryImage(for item: HistoryItem) -> PlatformImage? {
        guard let path = item.imagePath, !path.hasSuffix(".mp4") else { return nil }
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
        guard let path = item.imagePath else { return }
        let fileURL = URL(fileURLWithPath: path)
        Task {
            guard let img = await LazyThumbnailView.loadImage(for: item, appState: appState) else { return }
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
   
    private func updateWindowSize() {
        #if os(macOS)
        guard let item = currentItem,
              let window = NSApp.windows.last,
              let screen = NSScreen.main else {
            return
        }
       
        let bottomHeight: CGFloat = 100
        let minWidth: CGFloat = 400
        var desiredSize: CGSize
       
        if item.imagePath?.hasSuffix(".mp4") ?? false, isVideoPlayable {
            desiredSize = CGSize(width: max(videoAspectRatio * 400, minWidth), height: 400 + bottomHeight)
        } else if let platformImage = loadHistoryImage(for: item) {
            let imageSize = platformImage.size
            desiredSize = CGSize(width: max(imageSize.width, minWidth), height: imageSize.height + bottomHeight)
        } else {
            desiredSize = CGSize(width: minWidth, height: 400 + bottomHeight)
        }
       
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
   
    private func fileExists(item: HistoryItem) -> Bool {
        item.fileExists(appState: appState)
    }
}

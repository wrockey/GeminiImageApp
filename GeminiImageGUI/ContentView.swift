// ContentView.swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


extension View {
    func workflowErrorAlert(appState: AppState) -> some View {
        alert("Workflow Error", isPresented: Binding<Bool>(
            get: { appState.generation.workflowError != nil },
            set: { _ in appState.generation.workflowError = nil }
        )) {
            Button("OK") {}
        } message: {
            Text(appState.generation.workflowError ?? "Unknown error")
        }
    }

    func fullImageSheet(showFullImage: Binding<Bool>, outputImage: PlatformImage?) -> some View {
        sheet(isPresented: showFullImage) {
            if let outputImage = outputImage {
                FullImageView(image: outputImage)
            }
        }
    }

    func errorAlert(showErrorAlert: Binding<Bool>, errorMessage: String?) -> some View {
        alert("Error", isPresented: showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    func onboardingSheet(showOnboarding: Binding<Bool>) -> some View {
        sheet(isPresented: showOnboarding) {
            OnboardingView()
        }
    }

#if os(iOS)
func markupSheet(appState: AppState, showMarkupSheet: Binding<Bool>, selectedSlotId: UUID?) -> some View {
    sheet(isPresented: showMarkupSheet) {
        MarkupSheetContent(appState: appState, selectedSlotId: selectedSlotId)
    }
}
#endif
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) private var undoManager
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0.0
    @State private var webSocketTask: URLSessionWebSocketTask? = nil
    @State private var isCancelled: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var showApiKey: Bool = false
    @State private var apiKeyPath: String = ""
    @State private var outputPath: String = ""
    @State private var showOnboarding: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @State private var imageScale: CGFloat = 1.0
    @State private var isTestingApi: Bool = false
    @State private var showFullImage: Bool = false
    @AppStorage("configExpanded") private var configExpanded: Bool = true
    @AppStorage("promptExpanded") private var promptExpanded: Bool = true
    @AppStorage("inputImagesExpanded") private var inputImagesExpanded: Bool = true
    @AppStorage("responseExpanded") private var responseExpanded: Bool = true
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
#else
    @State private var showHistory: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
#endif
    @State private var showAnnotationSheet: Bool = false
    @State private var selectedSlotId: UUID?
    
    private var topColor: Color {
        colorScheme == .light ? Color(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0) : Color(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0)
    }

    private var bottomColor: Color {
        colorScheme == .light ? Color(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 234.0 / 255.0) : Color(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0)
    }

    var body: some View {
        #if os(iOS)
        iOSLayout
            .workflowErrorAlert(appState: appState)
            .fullImageSheet(showFullImage: $showFullImage, outputImage: appState.ui.outputImage)
            .errorAlert(showErrorAlert: $showErrorAlert, errorMessage: errorMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .onAppear {
                performOnAppear()
            }
            .onChange(of: appState.ui.outputImage) { _ in
                imageScale = 1.0
            }
            .markupSheet(appState: appState, showMarkupSheet: $appState.showMarkupSheet, selectedSlotId: selectedSlotId)
        #else
        macOSLayout
            .workflowErrorAlert(appState: appState)
            .fullImageSheet(showFullImage: $showFullImage, outputImage: appState.ui.outputImage)
            .errorAlert(showErrorAlert: $showErrorAlert, errorMessage: errorMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .onAppear {
                performOnAppear()
            }
            .onChange(of: appState.ui.outputImage) { _ in
                imageScale = 1.0
            }
        #endif
    }

#if os(iOS)
@ViewBuilder
    
private var iOSLayout: some View {

    NavigationStack {
        
        ScrollView {
            VStack(spacing: 16) {  // Added VStack for better grouping and spacing
//                Text("Main UI")
//                    .foregroundColor(.primary)
//                    .font(.headline)  // Slightly bolder for hierarchy
                MainFormView(
                    configExpanded: $configExpanded,
                    promptExpanded: $promptExpanded,
                    inputImagesExpanded: $inputImagesExpanded,
                    responseExpanded: $responseExpanded,
                    prompt: $appState.prompt,
                    showApiKey: $showApiKey,
                    apiKeyPath: $apiKeyPath,
                    outputPath: $outputPath,
                    isTestingApi: $isTestingApi,
                    errorMessage: $errorMessage,
                    showErrorAlert: $showErrorAlert,
                    imageScale: $imageScale,
                    showFullImage: $showFullImage,
                    isLoading: isLoading,
                    progress: progress,
                    isCancelled: $isCancelled,
                    onSubmit: submitPrompt,
                    onStop: stopGeneration,
                    onPopOut: {
                        appState.showResponseSheet = true
                    },
                    onAnnotate: { slotId in
                        appState.selectedSlotId = slotId
                        appState.showMarkupSheet = true
                    },
                    onApiKeySelected: handleApiKeySelection,
                    onOutputFolderSelected: handleOutputFolderSelection,
                    onComfyJSONSelected: handleComfyJSONSelection
                )
                .environmentObject(appState)
                .padding(.horizontal, 24)  // Increased horizontal padding for iPad comfort
            }
        }
        .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
        .navigationTitle("Gemini Image")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                toolbarContent
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryView(imageSlots: $appState.ui.imageSlots, columnVisibility: $columnVisibility)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: Binding(get: { appState.showResponseSheet }, set: { appState.showResponseSheet = $0 })) {
            PopOutView()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.showFullHistoryItem != nil },
            set: { if !$0 { appState.showFullHistoryItem = nil } }
        )) {
            if let id = appState.showFullHistoryItem {
                FullHistoryItemView(initialId: id)
                    .environmentObject(appState)
            }
        }
    }
}
#else
    @ViewBuilder
    private var macOSLayout: some View {

        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistoryView(imageSlots: $appState.ui.imageSlots, columnVisibility: $columnVisibility)
                .environmentObject(appState)
        } detail: {
            ScrollView {
                MainFormView(
                    configExpanded: $configExpanded,
                    promptExpanded: $promptExpanded,
                    inputImagesExpanded: $inputImagesExpanded,
                    responseExpanded: $responseExpanded,
                    prompt: $appState.prompt,
                    showApiKey: $showApiKey,
                    apiKeyPath: $apiKeyPath,
                    outputPath: $outputPath,
                    isTestingApi: $isTestingApi,
                    errorMessage: $errorMessage,
                    showErrorAlert: $showErrorAlert,
                    imageScale: $imageScale,
                    showFullImage: $showFullImage,
                    isLoading: isLoading,
                    progress: progress,
                    isCancelled: $isCancelled,
                    onSubmit: submitPrompt,
                    onStop: stopGeneration,
                    onPopOut: {
                        openWindow(id: "response-window")
                    },
                    onAnnotate: { slotId in
                        openWindow(value: slotId)
                    },
                    onApiKeySelected: handleApiKeySelection,
                    onOutputFolderSelected: handleOutputFolderSelection,
                    onComfyJSONSelected: handleComfyJSONSelection
                )
                .environmentObject(appState)
                .padding(.horizontal, 24)  // Add padding for better readability and alignment with iOS
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        
        .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarContent
            }
        }
    }
#endif

    private var toolbarContent: some View {
        Group {
            Button(action: {
                print("Showing api file picker from toolbar")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                    handleApiKeySelection(result)
                }
            }) {
                Image(systemName: "key")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Load API Key")

            Button(action: {
                print("Showing output folder picker from toolbar")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                }
            }) {
                Image(systemName: "folder")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Select Output Folder")

            Button(action: { undoManager?.undo() }) {
                Image(systemName: "arrow.counterclockwise")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Undo")

            Button(action: {
#if os(iOS)
                showHistory.toggle()
#else
                withAnimation(.easeInOut(duration: 0.3)) {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
#endif
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Toggle History Sidebar")
        }
    }

    private func handleOutputFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            print("Selected URLs: \(urls)")
            guard let selectedURL = urls.first else { errorMessage = "No folder selected."
                showErrorAlert = true
                return }
            do {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                #endif
                var bookmarkData: Data?
                #if os(iOS)
                var coordError: NSError?
                var innerCoordError: Error?
                NSFileCoordinator().coordinate(readingItemAt: selectedURL, options: [], error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            bookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        } catch {
                            innerCoordError = error
                        }
                    } else {
                        innerCoordError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                    }
                }
                if let coordError = coordError {
                    throw coordError
                }
                if let innerCoordError = innerCoordError {
                    throw innerCoordError
                }
                guard let bookmarkData = bookmarkData else {
                    throw NSError(domain: "BookmarkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create bookmark"])
                }
                #else
                bookmarkData = try selectedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                #endif
                UserDefaults.standard.set(bookmarkData, forKey: "outputDirBookmark")
                appState.settings.outputDirectory = selectedURL
                outputPath = selectedURL.path
            } catch {
                print("Bookmark error: \(error)")
                errorMessage = "Failed to create bookmark for output folder: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let error):
            print("Selection error: \(error)")
            errorMessage = "Failed to select output folder: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func handleApiKeySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            print("Selected URLs: \(urls)")
            guard let url = urls.first else { errorMessage = "No Api file selected."
                showErrorAlert = true
                return }
            do {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                #endif
                var bookmarkData: Data?
                #if os(iOS)
                var coordError: NSError?
                var innerCoordError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            bookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        } catch {
                            innerCoordError = error
                        }
                    } else {
                        innerCoordError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                    }
                }
                if let coordError = coordError {
                    throw coordError
                }
                if let innerCoordError = innerCoordError {
                    throw innerCoordError
                }
                guard let bookmarkData = bookmarkData else {
                    throw NSError(domain: "BookmarkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create bookmark"])
                }
                #else
                bookmarkData = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                #endif
                UserDefaults.standard.set(bookmarkData, forKey: "apiKeyFileBookmark")
                appState.settings.apiKeyFileURL = url
                apiKeyPath = url.path
                loadApiKeyFromFile()
            } catch {
                print("Bookmark error: \(error)")
                errorMessage = "Failed to open API key file: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let error):
            print("Selection error: \(error)")
            errorMessage = "Failed to select API key file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func handleComfyJSONSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "No file selected."
                showErrorAlert = true
                return
            }
            do {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                #endif
                var bookmarkData: Data?
                #if os(iOS)
                var coordError: NSError?
                var innerCoordError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            bookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        } catch {
                            innerCoordError = error
                        }
                    } else {
                        innerCoordError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                    }
                }
                if let coordError = coordError {
                    throw coordError
                }
                if let innerCoordError = innerCoordError {
                    throw innerCoordError
                }
                guard let bookmarkData = bookmarkData else {
                    throw NSError(domain: "BookmarkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create bookmark"])
                }
                #else
                bookmarkData = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                #endif
                UserDefaults.standard.set(bookmarkData, forKey: "comfyJSONBookmark")
            } catch {
                print("Bookmark error: \(error)")
                errorMessage = "Failed to save bookmark for file: \(error.localizedDescription)"
                showErrorAlert = true
                return
            }
            var loadError: NSError?
            var innerLoadError: Error?
            var json: [String: Any]?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &loadError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        let ext = coordinatedURL.pathExtension.lowercased()
                        if ext == "json" {
                            let data = try Data(contentsOf: coordinatedURL)
                            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        } else if ext == "png" {
                            if let workflowStr = appState.generation.extractWorkflowFromPNG(url: coordinatedURL) {
                                if let data = workflowStr.data(using: .utf8) {
                                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                } else {
                                    innerLoadError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                                }
                            } else {
                                innerLoadError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                            }
                        } else {
                            innerLoadError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type. Please select a JSON or PNG file."])
                        }
                    } catch {
                        innerLoadError = error
                    }
                } else {
                    innerLoadError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                }
            }
            if let loadError = loadError {
                errorMessage = "Failed to load workflow: \(loadError.localizedDescription)"
                showErrorAlert = true
                return
            }
            if let innerLoadError = innerLoadError {
                errorMessage = "Failed to load workflow: \(innerLoadError.localizedDescription)"
                showErrorAlert = true
                return
            }
            guard let json = json else {
                errorMessage = "Invalid workflow."
                showErrorAlert = true
                return
            }
            
            var workflowToUse: [String: Any] = json

            if let nodes = json["nodes"] as? [[String: Any]],
               let linksRaw = json["links"] as? [[Any]] {
                
                // Convert links to map for quick lookup: linkID -> (fromID, fromSlot, toID, toSlot, type)
                var linkMap: [Int: (Int, Int, Int, Int, String)] = [:]
                for link in linksRaw {
                    guard link.count == 6,
                          let linkID = link[0] as? Int,
                          let fromID = link[1] as? Int,
                          let fromSlot = link[2] as? Int,
                          let toID = link[3] as? Int,
                          let toSlot = link[4] as? Int,
                          let type = link[5] as? String else {
                        continue
                    }
                    linkMap[linkID] = (fromID, fromSlot, toID, toSlot, type)
                }
                
                // Build API workflow
                var apiWorkflow: [String: [String: Any]] = [:]
                for node in nodes {
                    guard let id = node["id"] as? Int,
                          let type = node["type"] as? String else {
                        continue
                    }
                    let idStr = String(id)
                    
                    var inputs: [String: Any] = [:]
                    let widgetsValues = node["widgets_values"] as? [Any] ?? []
                    var widgetIdx = 0
                    
                    if let nodeInputs = node["inputs"] as? [[String: Any]] {
                        for nodeInput in nodeInputs {
                            guard let name = nodeInput["name"] as? String else { continue }
                            
                            if let linkID = nodeInput["link"] as? Int,
                               let link = linkMap[linkID] {
                                let fromIDStr = String(link.0)
                                let fromSlot = link.1
                                inputs[name] = [fromIDStr, fromSlot]
                            } else if widgetIdx < widgetsValues.count {
                                inputs[name] = widgetsValues[widgetIdx]
                                widgetIdx += 1
                            }
                        }
                    }
                    
                    // Add any remaining widgets_values if needed (e.g., for properties not in inputs)
                    // But for standard ComfyUI nodes, the above should suffice
                    
                    apiWorkflow[idStr] = ["class_type": type, "inputs": inputs]
                }
                
                workflowToUse = apiWorkflow
                
                // Optional: Log for debugging
                print("Converted full workflow to API format with \(apiWorkflow.count) nodes")
            }

            // Now use workflowToUse instead of json
            if workflowToUse.isEmpty {
                errorMessage = "Invalid or empty workflow after processing."
                showErrorAlert = true
                return
            }

            appState.generation.comfyWorkflow = workflowToUse  // <-- Fixed here
            appState.settings.comfyJSONURL = url
            appState.settings.comfyJSONPath = url.path
            var nodeError: NSError?
            var innerNodeError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &nodeError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    appState.generation.loadWorkflowFromFile(comfyJSONURL: coordinatedURL)
                } else {
                    innerNodeError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                }
            }
            if let nodeError = nodeError {
                errorMessage = "Failed to load workflow nodes: \(nodeError.localizedDescription)"
                showErrorAlert = true
                return
            }
            if let innerNodeError = innerNodeError {
                errorMessage = "Failed to load workflow nodes: \(innerNodeError.localizedDescription)"
                showErrorAlert = true
                return
            }
            if let error = appState.generation.workflowError {
                errorMessage = error
                showErrorAlert = true
            }
            
        case .failure(let error):
            print("Selection error: \(error)")
            errorMessage = "Failed to select workflow file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
        private func saveGeneratedImage(data: Data) -> String? {
        let fileManager = FileManager.default
        var outputDir = appState.settings.outputDirectory
        var useFallback = false
        
        // If no custom dir, use Downloads
        if outputDir == nil {
            outputDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            useFallback = true
        }
        guard let dirURL = outputDir else { return nil }
        
        // Resolve bookmark for custom dir
        var resolvedDir = dirURL
        if !useFallback, let bookmarkData = UserDefaults.standard.data(forKey: "outputDirBookmark") {
            var isStale = false
            do {
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                resolvedDir = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
                
                if isStale || !fileManager.fileExists(atPath: resolvedDir.path) {
                    print("Output dir bookmark stale or invalid; refreshing or falling back to Downloads.")
                    useFallback = true
                    outputDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    resolvedDir = outputDir!
                    UserDefaults.standard.removeObject(forKey: "outputDirBookmark")
                }
            } catch {
                print("Bookmark resolution failed: \(error.localizedDescription). Falling back to Downloads.")
                useFallback = true
                outputDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                resolvedDir = outputDir!
                UserDefaults.standard.removeObject(forKey: "outputDirBookmark")
            }
        }
        
        do {
            // For custom dir, check scoping; Downloads doesn't need it
            var didStart = false
            if !useFallback {
                didStart = resolvedDir.startAccessingSecurityScopedResource()
                if !didStart {
                    print("Failed to start scoping for custom dir; falling back to Downloads.")
                    useFallback = true
                    outputDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    resolvedDir = outputDir!
                }
            }
            defer { if didStart { resolvedDir.stopAccessingSecurityScopedResource() } }
            
            // Check sync status (even for local)
            do {
                let values = try resolvedDir.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                    try fileManager.startDownloadingUbiquitousItem(at: resolvedDir)
                    errorMessage = "Folder syncing—try again soon."
                    showErrorAlert = true
                    return nil
                }
            } catch {
                print("Sync check failed: \(error)")
            }
            
            // List files
            var existingFiles: [URL] = []
            var listError: NSError?
            var innerListError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedDir, options: [], error: &listError) { coordinatedURL in
                do {
                    existingFiles = try fileManager.contentsOfDirectory(at: coordinatedURL, includingPropertiesForKeys: nil)
                } catch {
                    innerListError = error
                }
            }
            if let listError = listError {
                throw listError
            }
            if let innerListError = innerListError {
                throw innerListError
            }
            
            // Generate filename
            let generatedFiles = existingFiles.filter { $0.lastPathComponent.hasPrefix("generated_image_") && $0.pathExtension == "png" }
            let numbers = generatedFiles.compactMap { url in
                Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "generated_image_", with: ""))
            }
            let nextNum = (numbers.max() ?? 0) + 1
            let filename = "generated_image_\(nextNum).png"
            let fileURL = resolvedDir.appendingPathComponent(filename)
            
            // Write file
            var writeError: NSError?
            var innerWriteError: Error?
            let writeOptions: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: fileURL.path) ? .forReplacing : []
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: writeOptions, error: &writeError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL)
                } catch {
                    innerWriteError = error
                }
            }
            if let writeError = writeError {
                throw writeError
            }
            if let innerWriteError = innerWriteError {
                throw innerWriteError
            }
            return fileURL.path
        } catch {
            errorMessage = "Failed to save image: \(error.localizedDescription). Check folder permissions and reselect if needed."
            showErrorAlert = true
            // Emergency temp save
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent("generated_image_\(Date().timeIntervalSince1970).png")
            try? data.write(to: tempURL)
            print("Saved to temp: \(tempURL.path)")
            return tempURL.path
        }
    }
     private func loadApiKeyFromFile() {
        guard let apiFileURL = appState.settings.apiKeyFileURL else { return }
        
        let didStart = apiFileURL.startAccessingSecurityScopedResource()
        defer { if didStart { apiFileURL.stopAccessingSecurityScopedResource() } }
        
        do {
            appState.settings.apiKey = try String(contentsOf: apiFileURL).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = "Failed to load API key from file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func performOnAppear() {
        if !hasLaunchedBefore {
            showOnboarding = true
            hasLaunchedBefore = true
        }
        appState.historyState.loadHistory()
        if let url = appState.settings.apiKeyFileURL {
            apiKeyPath = url.path
        }
        if let url = appState.settings.outputDirectory {
            outputPath = url.path
        }
        if let bookmarkData = UserDefaults.standard.data(forKey: "apiKeyFileBookmark") {
            var isStale = false
            do {
    #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
                if isStale {
                    UserDefaults.standard.removeObject(forKey: "apiKeyFileBookmark")
                    appState.settings.apiKeyFileURL = nil
                    errorMessage = "API key file bookmark is stale. Please reselect the file."
                    showErrorAlert = true
                } else {
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        appState.settings.apiKeyFileURL = resolvedURL
                        loadApiKeyFromFile()
                        apiKeyPath = resolvedURL.path
                    } else {
                        throw NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(resolvedURL.path)"])
                    }
                }
            } catch let err as NSError {
                print("Bookmark resolution error: \(err.localizedDescription) (code: \(err.code), path: \(appState.settings.apiKeyFileURL?.path ?? "none"))")
                if err.code == 4 {
                    errorMessage = "API key file not found or moved. Please reselect the file."
                } else {
                    errorMessage = "Failed to resolve API key file: \(err.localizedDescription)"
                }
                showErrorAlert = true
                UserDefaults.standard.removeObject(forKey: "apiKeyFileBookmark")
                appState.settings.apiKeyFileURL = nil
            }
        }
        if let bookmarkData = UserDefaults.standard.data(forKey: "outputDirBookmark") {
            var isStale = false
            do {
    #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
                if isStale {
                    UserDefaults.standard.removeObject(forKey: "outputDirBookmark")
                    appState.settings.outputDirectory = nil
                    errorMessage = "Output directory bookmark is stale. Please reselect the folder."
                    showErrorAlert = true
                } else {
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        appState.settings.outputDirectory = resolvedURL
                        outputPath = resolvedURL.path
                    } else {
                        throw NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(resolvedURL.path)"])
                    }
                }
            } catch let err as NSError {
                print("Bookmark resolution error: \(err.localizedDescription) (code: \(err.code), path: \(appState.settings.outputDirectory?.path ?? "none"))")
                if err.code == 4 {
                    errorMessage = "Output directory not found or moved. Please reselect the folder."
                } else {
                    errorMessage = "Failed to resolve output directory: \(err.localizedDescription)"
                }
                showErrorAlert = true
                UserDefaults.standard.removeObject(forKey: "outputDirBookmark")
                appState.settings.outputDirectory = nil
            }
        }
        if let bookmarkData = UserDefaults.standard.data(forKey: "comfyJSONBookmark") {
            var isStale = false
            do {
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
                
                // Coordinate access for existence check and loading
                var coordError: NSError?
                var innerCoordError: Error?
                var json: [String: Any]?
                NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        
                        do {
                            // Check existence with scoped access active
                            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                                appState.settings.comfyJSONURL = coordinatedURL
                                appState.settings.comfyJSONPath = coordinatedURL.path
                                
                                // Check sync status (for iCloud/iOS)
                                let values = try coordinatedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                                    try FileManager.default.startDownloadingUbiquitousItem(at: coordinatedURL)
                                    innerCoordError = NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is downloading from provider—try again in a moment."])
                                    return
                                }
                                
                                // Load and parse JSON (handle both JSON and PNG)
                                let ext = coordinatedURL.pathExtension.lowercased()
                                if ext == "json" {
                                    let data = try Data(contentsOf: coordinatedURL)
                                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                } else if ext == "png" {
                                    if let workflowStr = appState.generation.extractWorkflowFromPNG(url: coordinatedURL) {
                                        if let data = workflowStr.data(using: .utf8) {
                                            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                        } else {
                                            innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                                        }
                                    } else {
                                        innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                                    }
                                } else {
                                    innerCoordError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type."])
                                }
                                
                                guard let json = json else {
                                    innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid workflow."])
                                    return
                                }
                                
                                var workflowToUse: [String: Any] = json
                                
                                if let nodes = json["nodes"] as? [[String: Any]],
                                   let linksRaw = json["links"] as? [[Any]] {
                                    
                                    // Convert links to map: linkID -> (fromID, fromSlot, toID, toSlot, type)
                                    var linkMap: [Int: (Int, Int, Int, Int, String)] = [:]
                                    for link in linksRaw {
                                        guard link.count == 6,
                                              let linkID = link[0] as? Int,
                                              let fromID = link[1] as? Int,
                                              let fromSlot = link[2] as? Int,
                                              let toID = link[3] as? Int,
                                              let toSlot = link[4] as? Int,
                                              let type = link[5] as? String else {
                                            continue
                                        }
                                        linkMap[linkID] = (fromID, fromSlot, toID, toSlot, type)
                                    }
                                    
                                    // Build API workflow
                                    var apiWorkflow: [String: [String: Any]] = [:]
                                    for node in nodes {
                                        guard let id = node["id"] as? Int,
                                              let type = node["type"] as? String else {
                                            continue
                                        }
                                        let idStr = String(id)
                                        
                                        var inputs: [String: Any] = [:]
                                        let widgetsValues = node["widgets_values"] as? [Any] ?? []
                                        var widgetIdx = 0
                                        
                                        if let nodeInputs = node["inputs"] as? [[String: Any]] {
                                            for nodeInput in nodeInputs {
                                                guard let name = nodeInput["name"] as? String else { continue }
                                                
                                                if let linkID = nodeInput["link"] as? Int,
                                                   let link = linkMap[linkID] {
                                                    let fromIDStr = String(link.0)
                                                    let fromSlot = link.1
                                                    inputs[name] = [fromIDStr, fromSlot]
                                                } else if widgetIdx < widgetsValues.count {
                                                    inputs[name] = widgetsValues[widgetIdx]
                                                    widgetIdx += 1
                                                }
                                            }
                                        }
                                        
                                        apiWorkflow[idStr] = ["class_type": type, "inputs": inputs]
                                    }
                                    
                                    workflowToUse = apiWorkflow
                                    
                                    print("Converted full workflow to API format with \(apiWorkflow.count) nodes")
                                }
                                
                                if workflowToUse.isEmpty {
                                    innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty workflow after processing."])
                                    return
                                }
                                
                                appState.generation.comfyWorkflow = workflowToUse
                                
                                // Load nodes
                                appState.generation.loadWorkflowFromFile(comfyJSONURL: coordinatedURL)
                                
                                if let error = appState.generation.workflowError {
                                    innerCoordError = NSError(domain: "LoadError", code: 0, userInfo: [NSLocalizedDescriptionKey: error])
                                }
                            } else {
                                innerCoordError = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(coordinatedURL.path)"])
                            }
                        } catch {
                            innerCoordError = error
                        }
                    } else {
                        innerCoordError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                    }
                }
                
                if let coordError = coordError {
                    throw coordError
                }
                if let innerCoordError = innerCoordError {
                    throw innerCoordError
                }
                
                if isStale {
                    #if os(macOS)
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                    #else
                    let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                    #endif
                    var refreshError: NSError?
                    var innerRefreshError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &refreshError) { coordinatedURL in
                        let didStart = coordinatedURL.startAccessingSecurityScopedResource()
                        defer { if didStart { coordinatedURL.stopAccessingSecurityScopedResource() } }
                        do {
                            let newBookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                            UserDefaults.standard.set(newBookmarkData, forKey: "comfyJSONBookmark")
                        } catch {
                            innerRefreshError = error
                        }
                    }
                    if let refreshError = refreshError {
                        print("Coordination error during refresh: \(refreshError)")
                    }
                    if let innerRefreshError = innerRefreshError {
                        print("Failed to refresh bookmark: \(innerRefreshError)")
                    }
                }
            } catch let err as NSError {
                print("Bookmark resolution error: \(err.localizedDescription) (code: \(err.code), path: \(appState.settings.comfyJSONURL?.path ?? "none"))")
                if err.code == 4 {
                    errorMessage = "ComfyUI JSON file not found or moved. Please reselect the file."
                } else {
                    errorMessage = "Failed to resolve or access ComfyUI JSON: \(err.localizedDescription)"
                }
                showErrorAlert = true
                UserDefaults.standard.removeObject(forKey: "comfyJSONBookmark")
                appState.settings.comfyJSONURL = nil
                appState.settings.comfyJSONPath = ""
            }
        }
    }
        
    private func submitPrompt() {
        isLoading = true
        errorMessage = nil
        appState.ui.responseText = ""
        appState.ui.outputImage = nil
        
        Task {
            defer { isLoading = false }
            
            switch appState.settings.mode {
            case .gemini:
                var parts: [Part] = [Part(text: appState.prompt, inlineData: nil)]
                
                for slot in appState.ui.imageSlots {
                    if let image = slot.image, let pngData = image.platformPngData() {
                        let base64 = pngData.base64EncodedString()
                        let inline = InlineData(mimeType: "image/png", data: base64)
                        parts.append(Part(text: nil, inlineData: inline))
                    }
                }
                
                let content = Content(parts: parts)
                let requestBody = GenerateContentRequest(contents: [content])
                
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent") else {
                    errorMessage = "Invalid URL"
                    showErrorAlert = true
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.addValue(appState.settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
                
                do {
                    request.httpBody = try JSONEncoder().encode(requestBody)
                } catch {
                    errorMessage = "Failed to encode request: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                do {
                    let (data, _) = try await URLSession.shared.data(for: request)
                    print(String(data: data, encoding: .utf8) ?? "No data")
                    let response = try JSONDecoder().decode(NewGenerateContentResponse.self, from: data)
                    
                    var textOutput = ""
                    var savedImage: PlatformImage? = nil
                    var savedPath: String? = nil
                    
                    for part in response.candidates.first?.content.parts ?? [] {
                        if let text = part.text {
                            textOutput += text + "\n"
                        } else if let inline = part.inlineData, let imgData = Data(base64Encoded: inline.data) {
                            savedImage = PlatformImage(platformData: imgData)
                            savedPath = saveGeneratedImage(data: imgData)
                            if let saved = savedPath {
                                textOutput += "Image saved to \(saved)\n"
                            }
                        }
                    }
                    
                    appState.ui.responseText = textOutput.isEmpty ? "No text output." : textOutput
                    appState.ui.outputImage = savedImage
                    
                    if savedImage == nil {
                        appState.ui.responseText += "No image generated."
                    }
                    
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: nil)
                    appState.historyState.history.append(newItem)
                    appState.historyState.saveHistory()
                } catch {
                    errorMessage = "API error: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            case .comfyUI:
                guard let workflow = appState.generation.comfyWorkflow else {
                    errorMessage = "No workflow loaded."
                    showErrorAlert = true
                    return
                }
                
                guard let serverURL = URL(string: appState.settings.comfyServerURL) else {
                    errorMessage = "Invalid ComfyUI server URL."
                    showErrorAlert = true
                    return
                }
                
                var mutableWorkflow = workflow
                
                // Generate clientId early for WebSocket
                let clientId = UUID().uuidString
                
                // Append ?clientId to WebSocket URL for progress routing
                let wsBase = appState.settings.comfyServerURL.replacingOccurrences(of: "http", with: "ws") + "/ws?clientId=\(clientId)"
                guard let wsURL = URL(string: wsBase) else {
                    errorMessage = "Invalid WebSocket URL."
                    showErrorAlert = true
                    return
                }
                let session = URLSession(configuration: .default)
                webSocketTask = session.webSocketTask(with: wsURL)
                webSocketTask?.resume()
                isCancelled = false
                
                // Listen for messages in a loop
                Task {
                    while let task = webSocketTask, !isCancelled {
                        do {
                            let message = try await task.receive()
                            switch message {
                            case .string(let text):
                                if let data = text.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let type = json["type"] as? String {
                                    if type == "progress",
                                       let value = json["data"] as? [String: Any],
                                       let current = value["value"] as? Double,
                                       let max = value["max"] as? Double {
                                        await MainActor.run {
                                            progress = current / max
                                        }
                                    } else if type == "executing",
                                              let value = json["data"] as? [String: Any],
                                              let nodeId = value["node"] as? String {
                                        // Optional: Log executing node for more detailed progress
                                        print("Executing node: \(nodeId)")
                                    }
                                }
                            default: break
                            }
                        } catch {
                            await MainActor.run {
                                if !isCancelled {
                                    errorMessage = "WebSocket error: \(error.localizedDescription)"
                                    showErrorAlert = true
                                }
                            }
                            break
                        }
                    }
                }
                
                let promptNodeID = appState.generation.comfyPromptNodeID
                if var node = mutableWorkflow[promptNodeID] as? [String: Any],
                   var inputs = node["inputs"] as? [String: Any] {
                    inputs["text"] = appState.prompt
                    node["inputs"] = inputs
                    mutableWorkflow[promptNodeID] = node
                } else {
                    errorMessage = "Invalid prompt node."
                    showErrorAlert = true
                    return
                }
                
                var uploadedFilename: String? = nil
                if !appState.generation.comfyImageNodeID.isEmpty && !appState.ui.imageSlots.isEmpty,
                   let image = appState.ui.imageSlots.first?.image, let pngData = image.platformPngData() {
                    var uploadRequest = URLRequest(url: serverURL.appendingPathComponent("upload/image"))
                    uploadRequest.httpMethod = "POST"
                    
                    let boundary = "Boundary-\(UUID().uuidString)"
                    uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    
                    var body = Data()
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input.png\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
                    body.append(pngData)
                    body.append("\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    
                    uploadRequest.httpBody = body
                    
                    do {
                        let (data, _) = try await URLSession.shared.data(for: uploadRequest)
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let name = json["name"] as? String {
                            uploadedFilename = name
                        } else {
                            errorMessage = "Failed to upload image."
                            showErrorAlert = true
                            return
                        }
                    } catch {
                        errorMessage = "Upload error: \(error.localizedDescription)"
                        showErrorAlert = true
                        return
                    }
                    
                    let imageNodeID = appState.generation.comfyImageNodeID
                    if var node = mutableWorkflow[imageNodeID] as? [String: Any],
                       var inputs = node["inputs"] as? [String: Any] {
                        inputs["image"] = uploadedFilename
                        node["inputs"] = inputs
                        mutableWorkflow[imageNodeID] = node
                    } else {
                        errorMessage = "Invalid image node."
                        showErrorAlert = true
                        return
                    }
                }
                
                let promptBody: [String: Any] = ["prompt": mutableWorkflow, "client_id": clientId]
                var promptRequest = URLRequest(url: serverURL.appendingPathComponent("prompt"))
                promptRequest.httpMethod = "POST"
                promptRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
                do {
                    promptRequest.httpBody = try JSONSerialization.data(withJSONObject: promptBody)
                } catch {
                    errorMessage = "Failed to encode prompt: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                var promptId: String?
                do {
                    let (data, _) = try await URLSession.shared.data(for: promptRequest)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = json["prompt_id"] as? String {
                        promptId = id
                    } else {
                        errorMessage = "Failed to queue prompt."
                        showErrorAlert = true
                        return
                    }
                } catch {
                    errorMessage = "Prompt queue error: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let promptId = promptId else { return }
                
                var history: [String: Any]? = nil
                while history == nil {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let historyURL = serverURL.appendingPathComponent("history/\(promptId)")
                    var historyRequest = URLRequest(url: historyURL)
                    do {
                        let (data, _) = try await URLSession.shared.data(for: historyRequest)
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let entry = json[promptId] as? [String: Any],
                           let status = entry["status"] as? [String: Any],
                           let completed = status["completed"] as? Bool, completed {
                            history = entry
                        }
                    } catch {}
                }
                
                guard let history = history,
                      let outputs = history["outputs"] as? [String: Any],
                      let outputNode = outputs[appState.generation.comfyOutputNodeID] as? [String: Any],
                      let images = outputNode["images"] as? [[String: Any]],
                      let firstImage = images.first,
                      let filename = firstImage["filename"] as? String,
                      let subfolder = firstImage["subfolder"] as? String,
                      let type = firstImage["type"] as? String else {
                    errorMessage = "No output image found in history."
                    showErrorAlert = true
                    return
                }
                
                var components = URLComponents(url: serverURL.appendingPathComponent("view"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "filename", value: filename),
                    URLQueryItem(name: "subfolder", value: subfolder),
                    URLQueryItem(name: "type", value: type)
                ]
                guard let viewURL = components.url else {
                    errorMessage = "Invalid view URL."
                    showErrorAlert = true
                    return
                }
                
                var viewRequest = URLRequest(url: viewURL)
                do {
                    let (data, _) = try await URLSession.shared.data(for: viewRequest)
                    if let platformImage = PlatformImage(platformData: data) {
                        appState.ui.outputImage = platformImage
                        let savedPath = saveGeneratedImage(data: data)
                        appState.ui.responseText = "Image generated with ComfyUI. Saved to \(savedPath ?? "unknown")"
                        
                        let workflowName = URL(fileURLWithPath: appState.settings.comfyJSONPath).deletingPathExtension().lastPathComponent
                        let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: workflowName)
                        appState.historyState.history.append(newItem)
                        appState.historyState.saveHistory()
                    } else {
                        errorMessage = "Failed to decode image."
                        showErrorAlert = true
                    }
                } catch {
                    errorMessage = "Image fetch error: \(error.localizedDescription)"
                    showErrorAlert = true
                }
                // Set isCancelled before cancelling to suppress error
                isCancelled = true
                webSocketTask?.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil
                progress = 0.0
            }
        }
    }
    
    
    private func resetAppState() {
        appState.prompt = ""
        appState.ui.imageSlots = []
        appState.ui.responseText = ""
        appState.ui.outputImage = nil
        errorMessage = nil
    }
    private func stopGeneration() {
        isCancelled = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        progress = 0.0
        
        guard let serverURL = URL(string: appState.settings.comfyServerURL) else { return }
        var request = URLRequest(url: serverURL.appendingPathComponent("interrupt"))
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    errorMessage = "Stop error: \(error.localizedDescription)"
                    showErrorAlert = true
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    errorMessage = "Generation stopped."
                    showErrorAlert = true
                }
            }
        }.resume()
    }
}

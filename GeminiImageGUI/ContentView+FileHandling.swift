// ContentView+FileHandling.swift
import Foundation

extension ContentView {
    func handleOutputFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            print("Selected URLs: \(urls)")
            guard let selectedURL = urls.first else 
            { errorItem = AlertError(message: "No folder selected.")
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
                errorItem = AlertError(message: "Failed to create bookmark for output folder: \(error.localizedDescription)")
            }
        case .failure(let error):
            print("Selection error: \(error)")
            errorItem = AlertError(message: "Failed to select output folder: \(error.localizedDescription)")
        }
    }
    
    func handleApiKeySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let key = try String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
                appState.settings.apiKey = key
                if KeychainHelper.saveAPIKey(key) {
                    // Optional: successMessage = "API key loaded and stored securely."
                    // showSuccessAlert = true
                } else {
                    errorItem = AlertError(message: "Failed to store API key securely.")
                }
                apiKeyPath = url.path  // Update UI if keeping the display
            } catch {
                errorItem = AlertError(message: "Failed to read API key file: \(error.localizedDescription)")
            }
        case .failure(let error):
            errorItem = AlertError(message: "File selection error: \(error.localizedDescription)")
        }
    }
    
    func saveGeneratedImage(data: Data, prompt: String, mode: GenerationMode, workflowName: String? = nil, modelUsed: String? = nil, batchIndex: Int? = nil, totalInBatch: Int? = nil) -> String? {
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
                    errorItem = AlertError(message: "Folder syncing—try again soon.")
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
            
            // Generate filename with mode-specific extension
            let extensionStr = (mode == .comfyUI) ? "png" : "jpg"
            let generatedFiles = existingFiles.filter { $0.lastPathComponent.hasPrefix("generated_image_") && $0.pathExtension == extensionStr }
            let numbers = generatedFiles.compactMap { url in
                Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "generated_image_", with: ""))
            }
            let nextNum = (numbers.max() ?? 0) + 1
            let filename = "generated_image_\(nextNum).\(extensionStr)"
            let fileURL = resolvedDir.appendingPathComponent(filename)
            
            // NEW: Compute creator using history logic, with fallback for extensibility
            var creatorToUse: String = mode.rawValue.capitalized  // Fallback to mode name (e.g., "Gemini", allows future modes)
            switch mode {
            case .gemini:
                creatorToUse = "Gemini 2.5 Flash"  // Hardcode details if no selectedModel
            case .grok:
                creatorToUse = modelUsed ?? appState.settings.selectedGrokModel
            case .aimlapi:
                creatorToUse = modelUsed ?? appState.settings.selectedAIMLModel
            case .comfyUI:
                creatorToUse = workflowName ?? "ComfyUI"
            }
            if let idx = batchIndex, let tot = totalInBatch {
                creatorToUse += " #\(idx + 1) of \(tot)"
            }
            
            // NEW: Prepare finalData based on mode
            var finalData = data
            if mode == .comfyUI {
                // For ComfyUI: Save PNG as-is (preserves embedded workflow; no addition)
                if !isPNGData(data) {
                    // Rare: If not PNG, convert to PNG without mods
                    if let image = PlatformImage(platformData: data) {
                        finalData = image.platformPngData() ?? data
                    }
                }
            } else {
                // For others: Convert to JPEG and add EXIF comment if prompt non-empty
                if !prompt.isEmpty {
                    finalData = addCommentToJPEG(inputData: data, prompt: prompt, creator: creatorToUse) ?? data
                }
                // Ensure JPEG (convert if needed)
                if !isJPEGData(finalData) {
                    if let image = PlatformImage(platformData: finalData) {
                        finalData = image.platformData(forType: "jpeg", compressionQuality: 0.95) ?? finalData
                    }
                }
            }
            
            // Write file
            var writeError: NSError?
            var innerWriteError: Error?
            let writeOptions: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: fileURL.path) ? .forReplacing : []
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: writeOptions, error: &writeError) { coordinatedURL in
                do {
                    try finalData.write(to: coordinatedURL)
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
            errorItem = AlertError(message: "Failed to save image: \(error.localizedDescription). Check folder permissions and reselect if needed.")
            // Emergency temp save
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent("generated_image_\(Date().timeIntervalSince1970).png")
            try? data.write(to: tempURL)
            print("Saved to temp: \(tempURL.path)")
            return tempURL.path
        }
    }
    
/*    func loadApiKeyFromFile() {
        guard let apiFileURL = appState.settings.apiKeyFileURL else { return }
        
        let didStart = apiFileURL.startAccessingSecurityScopedResource()
        defer { if didStart { apiFileURL.stopAccessingSecurityScopedResource() } }
        
        do {
            appState.settings.apiKey = try String(contentsOf: apiFileURL).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorItem = AlertError(message: "Failed to load API key from file: \(error.localizedDescription)"
        }
    }
 */
}

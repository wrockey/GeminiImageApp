import Foundation

extension ContentView {
    func performOnAppear() {
        // Quick synchronous stuff
        if !hasLaunchedBefore {
            showOnboarding = true
            hasLaunchedBefore = true
        }

        // Heavy stuff async
        Task {
            await loadHeavyResources()
        }
    }

    private func loadHeavyResources() async {
        appState.historyState.loadHistory()

        if let url = appState.settings.outputDirectory {
            DispatchQueue.main.async {
                self.outputPath = url.path
            }
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: "outputDirBookmark") {
            await resolveOutputDirBookmark(bookmarkData: bookmarkData)
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: "comfyJSONBookmark") {
            await resolveComfyJSONBookmark(bookmarkData: bookmarkData)
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: "batchFileBookmark") {
            await resolveBatchFileBookmark(bookmarkData: bookmarkData)
        }
    }

    private func resolveOutputDirBookmark(bookmarkData: Data) async {
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
                DispatchQueue.main.async {
                    self.errorMessage = "Output directory bookmark is stale. Please reselect the folder."
                    self.showErrorAlert = true
                }
            } else {
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    appState.settings.outputDirectory = resolvedURL
                    DispatchQueue.main.async {
                        self.outputPath = resolvedURL.path
                    }
                } else {
                    throw NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(resolvedURL.path)"])
                }
            }
        } catch let err as NSError {
            print("Bookmark resolution error: \(err.localizedDescription) (code: \(err.code), path: \(appState.settings.outputDirectory?.path ?? "none"))")
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "Output directory not found or moved. Please reselect the folder."
            } else {
                errorMsg = "Failed to resolve output directory: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.showErrorAlert = true
            }
            UserDefaults.standard.removeObject(forKey: "outputDirBookmark")
            appState.settings.outputDirectory = nil
        }
    }

    private func resolveComfyJSONBookmark(bookmarkData: Data) async {
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
                        // Now check existence with scoped access active
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
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "ComfyUI JSON file not found or moved. Please reselect the file."
            } else {
                errorMsg = "Failed to resolve or access ComfyUI JSON: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.showErrorAlert = true
            }
            UserDefaults.standard.removeObject(forKey: "comfyJSONBookmark")
            appState.settings.comfyJSONURL = nil
            appState.settings.comfyJSONPath = ""
        }
    }

    private func resolveBatchFileBookmark(bookmarkData: Data) async {
        var isStale = false
        do {
#if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
            let resolveOptions: URL.BookmarkResolutionOptions = []
#endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
            
            var coordError: NSError?
            var innerCoordError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                            appState.batchFileURL = coordinatedURL
                            DispatchQueue.main.async {
                                self.batchFilePath = coordinatedURL.path
                            }
                            
                            let values = try coordinatedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                                try FileManager.default.startDownloadingUbiquitousItem(at: coordinatedURL)
                                innerCoordError = NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is downloading—try again soon."])
                                return
                            }
                            
                            let text = try String(contentsOf: coordinatedURL)
                            appState.batchPrompts = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
                        UserDefaults.standard.set(newBookmarkData, forKey: "batchFileBookmark")
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
            print("Bookmark resolution error for batch file: \(err.localizedDescription)")
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "Batch file not found or moved. Please reselect the file."
            } else {
                errorMsg = "Failed to resolve or access batch file: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
                self.showErrorAlert = true
            }
            UserDefaults.standard.removeObject(forKey: "batchFileBookmark")
            appState.batchFileURL = nil
            DispatchQueue.main.async {
                self.batchFilePath = ""
            }
        }
    }
    
    func resetAppState() {
        appState.prompt = ""
        appState.ui.imageSlots = []
        appState.ui.responseText = ""
        appState.ui.outputImage = nil
        isLoading = false
        progress = 0.0
        isCancelled = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        errorMessage = nil
        apiKeyPath = ""
        outputPath = ""
        batchFilePath = ""
        startPrompt = "1"
        endPrompt = ""
    }
}

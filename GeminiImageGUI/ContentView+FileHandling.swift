// ContentView+FileHandling.swift
import Foundation

extension ContentView {
    func handleOutputFolderSelection(_ result: Result<[URL], Error>) {
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
    
    func handleApiKeySelection(_ result: Result<[URL], Error>) {
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
    
    func saveGeneratedImage(data: Data) -> String? {
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
    
    func loadApiKeyFromFile() {
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
}

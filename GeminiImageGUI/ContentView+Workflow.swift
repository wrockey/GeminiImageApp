// ContentView+Workflow.swift
import Foundation

extension ContentView {
    func handleComfyJSONSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorItem = AlertError(message: "No file selected.", fullMessage: nil)
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
                errorItem = AlertError(message: "Failed to save bookmark for file: \(error.localizedDescription)", fullMessage: nil)
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
                errorItem = AlertError(message: "Failed to load workflow: \(loadError.localizedDescription)", fullMessage: nil)
                return
            }
            if let innerLoadError = innerLoadError {
                errorItem = AlertError(message: "Failed to load workflow: \(innerLoadError.localizedDescription)", fullMessage: nil)
                return
            }
            guard let json = json else {
                errorItem = AlertError(message: "Invalid workflow.", fullMessage: nil)
                return
            }
            
            var workflowToUse: [String: Any] = json

            if let _ = json["nodes"] as? [[String: Any]],
               let _ = json["links"] as? [[Any]] {
                errorItem = AlertError(message: "The selected workflow is not in API format. Please export the workflow in API format from ComfyUI and try again.", fullMessage: nil)
                return
            }

            // Now use workflowToUse instead of json
            if workflowToUse.isEmpty {
                errorItem = AlertError(message: "Invalid or empty workflow after processing.", fullMessage: nil)
                return
            }

                appState.generation.comfyWorkflow = workflowToUse
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
                    errorItem = AlertError(message: "Failed to load workflow nodes: \(nodeError.localizedDescription)", fullMessage: nil)
                    return
                }
                if let innerNodeError = innerNodeError {
                    errorItem = AlertError(message: "Failed to load workflow nodes: \(innerNodeError.localizedDescription)", fullMessage: nil)
                    return
                }
                if let error = appState.generation.workflowError {
                    errorItem = AlertError(message: error, fullMessage: nil)
                }
            
        case .failure(let error):
            print("Selection error: \(error)")
            errorItem = AlertError(message: "Failed to select workflow file: \(error.localizedDescription)", fullMessage: nil)
        }
    }
}

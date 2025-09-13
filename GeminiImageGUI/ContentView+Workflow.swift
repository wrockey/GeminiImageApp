// ContentView+Workflow.swift
import Foundation

extension ContentView {
    func handleComfyJSONSelection(_ result: Result<[URL], Error>) {
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
                
                // Convert links to map for quick lookup: linkID -> [fromID, fromSlot, toID, toSlot, type]
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
}

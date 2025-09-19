// ContentView+Batch.swift
import SwiftUI
import Foundation  // Add other imports as needed

extension ContentView {
    func handleBatchFileSelection(_ result: Result<[URL], Error>) {
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
                UserDefaults.standard.set(bookmarkData, forKey: "batchFileBookmark")
            } catch {
                print("Bookmark error: \(error)")
                errorMessage = "Failed to save bookmark for batch file: \(error.localizedDescription)"
                showErrorAlert = true
                return
            }
            var loadError: NSError?
            var innerLoadError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &loadError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        let text = try String(contentsOf: coordinatedURL)
                        appState.batchPrompts = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        appState.batchFileURL = url
                        batchFilePath = url.path
                    } catch {
                        innerLoadError = error
                    }
                } else {
                    innerLoadError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                }
            }
            if let loadError = loadError {
                errorMessage = "Failed to load batch file: \(loadError.localizedDescription)"
                showErrorAlert = true
                return
            }
            if let innerLoadError = innerLoadError {
                errorMessage = "Failed to load batch file: \(innerLoadError.localizedDescription)"
                showErrorAlert = true
                return
            }
        case .failure(let error):
            print("Selection error: \(error)")
            errorMessage = "Failed to select batch file: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    func batchSubmit() {
        if outputPath.isEmpty {
            pendingAction = batchSubmit
            showSelectFolderAlert = true
            return
        }
        
        // New: Check each prompt in batch for safety
        for prompt in appState.batchPrompts {
            if !ContentView.isPromptSafe(prompt) {
                errorMessage = "One or more prompts contain inappropriate content. Please revise."
                showErrorAlert = true
                return
            }
        }
        
        let start = Int(startPrompt) ?? 1
        let end = Int(endPrompt) ?? appState.batchPrompts.count
        var failures: [(Int, String, String)] = []  // (index, prompt, errorDesc)
        
        isLoading = true
        
        Task {
            for i in start...end {
                guard i-1 < appState.batchPrompts.count else { break }
                appState.prompt = appState.batchPrompts[i-1]
                
                do {
                    try await asyncGenerate()
                } catch let err {
                    failures.append((i, appState.prompt, err.localizedDescription))
                }
            }
            
            isLoading = false
            
            if failures.isEmpty {
                successMessage = "Batch Job Successfully Completed"
                showSuccessAlert = true
            } else {
                let failedText = failures.map { "\($0.0): \($0.1) - \($0.2)" }.joined(separator: "\n")
                errorMessage = "Failed to generate the following prompts:\n\(failedText)"
                showErrorAlert = true
            }
        }
    }
}

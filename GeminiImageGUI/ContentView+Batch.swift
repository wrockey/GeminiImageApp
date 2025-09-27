// ContentView+Batch.swift
import SwiftUI
import Foundation // Add other imports as needed

extension ContentView {
    func handleBatchFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorItem = AlertError(message: "No file selected.")
                return

            }
            do {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope] // Allows read/write
                let bookmarkData = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                var bookmarkData: Data?
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
                #endif
                UserDefaults.standard.set(bookmarkData, forKey: "batchFileBookmark")
            } catch {
                print("Bookmark error: \(error)")
                errorItem = AlertError(message: "Failed to save bookmark for batch file: \(error.localizedDescription)")
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
                errorItem = AlertError(message: "Failed to load batch file: \(loadError.localizedDescription)")
                return
            }
            if let innerLoadError = innerLoadError {
                errorItem = AlertError(message: "Failed to load batch file: \(innerLoadError.localizedDescription)")
                return
            }
        case .failure(let error):
            print("Selection error: \(error)")
            errorItem = AlertError(message: "Failed to select batch file: \(error.localizedDescription)")
        }
    }

    func loadBatchPrompts() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "batchFileBookmark") else { return }
        do {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
            let accessing = resolvedURL.startAccessingSecurityScopedResource()
            defer { if accessing { resolvedURL.stopAccessingSecurityScopedResource() } }
            let content = try String(contentsOf: resolvedURL, encoding: .utf8)
            appState.batchPrompts = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            appState.batchFileURL = resolvedURL
            batchFilePath = resolvedURL.path
        } catch {
            errorItem = AlertError(message: "Failed to load batch file: \(error.localizedDescription)")
        }
    }

    func batchSubmit() {
        if outputPath.isEmpty {
            pendingAction = batchSubmit
            showSelectFolderAlert = true
            return
        }
        
        // Check each prompt in batch for safety
                var offendingPrompts: [(prompt: String, phrases: [String])] = []
                for prompt in appState.batchPrompts {
                    let (isSafe, offendingPhrases) = ContentView.isPromptSafe(prompt)
                    if !isSafe {
                        offendingPrompts.append((prompt: prompt, phrases: offendingPhrases))
                    }
                }
                
                if !offendingPrompts.isEmpty {
                    let errorDetails = offendingPrompts.map { promptInfo in
                        let phrasesList = promptInfo.phrases.joined(separator: ", ")
                        return "Prompt '\(promptInfo.prompt)' contains: \(phrasesList)"
                    }.joined(separator: "\n")
                    errorItem = AlertError(message: "One or more prompts contain inappropriate content:\n\(errorDetails).\nPlease revise and try again.")
                    return
                }
        
        let start = batchStartIndex
        let end = batchEndIndex
        guard start <= end else {
            errorItem = AlertError(message: "Starting prompt must be less than or equal to ending prompt.")
            return
        }
        var failures: [(Int, String, String)] = [] // (index, prompt, errorDesc)
        
        isLoading = true
        
        generationTask = Task {
            defer {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
            
            for i in start...end {
                try Task.checkCancellation()
                
                guard i-1 < appState.batchPrompts.count else { break }
                appState.prompt = appState.batchPrompts[i-1]
                
                do {
                    try await asyncGenerate()
                    // Add a small delay or check for cancellation between generations
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError {
                    // Handle cancellation gracefully
                    break
                } catch {
                    failures.append((i, appState.prompt, error.localizedDescription))
                }
            }
            
            DispatchQueue.main.async {
                if failures.isEmpty {
                    successMessage = "Batch Job Successfully Completed"
                    showSuccessAlert = true
                } else {
                    let failedText = failures.map { "\($0.0): \($0.1) - \($0.2)" }.joined(separator: "\n")
                    errorItem = AlertError(message: "Failed to generate the following prompts:\n\(failedText)")
                }
            }
        }
    }
}



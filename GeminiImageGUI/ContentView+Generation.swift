// ContentView+Generation.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Required for CGImageSource/Destination APIs in stripExif

struct GrokImageResponse: Codable {
    let created: Int?
    let data: [GrokImageData]
}

struct GrokImageData: Codable {
    let b64_json: String?
    let url: String?
    let revised_prompt: String?
}

extension ContentView {
    func submitPrompt() {
        if outputPath.isEmpty {
            pendingAction = submitPrompt
            showSelectFolderAlert = true
            return
        }
        
        // New: Check if prompt is safe
        if !ContentView.isPromptSafe(appState.prompt) {
            errorMessage = "Prompt contains inappropriate content. Please revise and try again."
            showErrorAlert = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        appState.ui.responseText = ""
        appState.ui.outputImage = nil
        
        generationTask = Task {
            defer {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
            
            do {
                try await asyncGenerate()
            } catch is CancellationError {
                // Handle cancellation
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "API error: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    func asyncGenerate() async throws {
        try Task.checkCancellation()
        
        switch appState.settings.mode {
        case .gemini:
            // New: Show consent alert on first Gemini use
            if !UserDefaults.standard.bool(forKey: "hasShownGeminiConsent") {
                let consented = await showGeminiConsentAlert()
                if !consented {
                    throw GenerationError.apiError("User did not consent to data sharing.")
                }
                UserDefaults.standard.set(true, forKey: "hasShownGeminiConsent")
            }
            
            var parts: [Part] = [Part(text: appState.prompt, inlineData: nil)]
            
            for slot in appState.ui.imageSlots {
                if let image = slot.image, let pngData = image.platformPngData() {
                    let safeData = stripExif(from: pngData) ?? pngData // Strip EXIF before sending
                    let base64 = safeData.base64EncodedString()
                    let inline = InlineData(mimeType: "image/png", data: base64)
                    parts.append(Part(text: nil, inlineData: inline))
                }
            }
            
            let content = Content(parts: parts)
            let requestBody = GenerateContentRequest(contents: [content])
            
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent") else {
                throw GenerationError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(appState.settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
            
            request.httpBody = try JSONEncoder().encode(requestBody)
            
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
        case .comfyUI:
            guard let workflow = appState.generation.comfyWorkflow else {
                throw GenerationError.noWorkflow
            }
            
            guard let serverURL = URL(string: appState.settings.comfyServerURL) else {
                throw GenerationError.invalidServerURL
            }
            
            var mutableWorkflow = workflow
            
            // Generate clientId early for WebSocket
            let clientId = UUID().uuidString
            
            // Append ?clientId to WebSocket URL for progress routing
            let wsBase = appState.settings.comfyServerURL.replacingOccurrences(of: "http", with: "ws") + "/ws?clientId=\(clientId)"
            guard let wsURL = URL(string: wsBase) else {
                throw GenerationError.invalidWebSocketURL
            }
            let session = URLSession(configuration: .default)
            webSocketTask = session.webSocketTask(with: wsURL)
            webSocketTask?.resume()
            isCancelled = false
            
            // Listen for messages in a loop
            Task {
                var isComplete = false
                while let task = webSocketTask, !isCancelled {
                    try Task.checkCancellation()
                    
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
                                          let node = value["node"] as? String {
                                    print("Executing node: \(node)")
                                } else if type == "executing",
                                          let value = json["data"] as? [String: Any],
                                          value["node"] == nil { // Completion indicator: node is null
                                    isComplete = true
                                } else if type == "execution_success" { // Alternative completion indicator
                                    isComplete = true
                                }
                            }
                        default: break
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        await MainActor.run {
                            let nsError = error as NSError
                            print("WebSocket error caught: domain=\(nsError.domain), code=\(nsError.code), desc=\(error.localizedDescription), isCancelled=\(isCancelled), isComplete=\(isComplete)")
                            if !((isCancelled || isComplete) && nsError.domain == NSPOSIXErrorDomain && nsError.code == 57) {
                                errorMessage = "WebSocket error: \(error.localizedDescription)"
                                showErrorAlert = true
                            }
                        }
                        break
                    }
                }
            }
            
            let promptNodeID = appState.generation.comfyPromptNodeID
            let selectedPromptText = appState.generation.promptNodes.first(where: { $0.id == promptNodeID })?.promptText ?? ""
            let effectivePrompt = appState.prompt.isEmpty ? selectedPromptText : appState.prompt
            
            if var node = mutableWorkflow[promptNodeID] as? [String: Any],
               var inputs = node["inputs"] as? [String: Any] {
                inputs["text"] = effectivePrompt
                node["inputs"] = inputs
                mutableWorkflow[promptNodeID] = node
            } else {
                throw GenerationError.invalidPromptNode
            }
            
            var uploadedFilename: String? = nil
            if !appState.generation.comfyImageNodeID.isEmpty && !appState.ui.imageSlots.isEmpty,
               let image = appState.ui.imageSlots.first?.image, let pngData = image.platformPngData() {
                let safeData = stripExif(from: pngData) ?? pngData // Strip EXIF before uploading
                var uploadRequest = URLRequest(url: serverURL.appendingPathComponent("upload/image"))
                uploadRequest.httpMethod = "POST"
                
                let boundary = "Boundary-\(UUID().uuidString)"
                uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input.png\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
                body.append(safeData)
                body.append("\r\n".data(using: .utf8)!)
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                uploadRequest.httpBody = body
                
                do {
                    try Task.checkCancellation()
                    let (data, _) = try await URLSession.shared.data(for: uploadRequest)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = json["name"] as? String {
                        uploadedFilename = name
                    } else {
                        throw GenerationError.uploadFailed
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw GenerationError.uploadFailed
                }
                
                let imageNodeID = appState.generation.comfyImageNodeID
                if var node = mutableWorkflow[imageNodeID] as? [String: Any],
                   var inputs = node["inputs"] as? [String: Any] {
                    inputs["image"] = uploadedFilename
                    node["inputs"] = inputs
                    mutableWorkflow[imageNodeID] = node
                } else {
                    throw GenerationError.invalidImageNode
                }
            }
            
            let promptBody: [String: Any] = ["prompt": mutableWorkflow, "client_id": clientId]
            var promptRequest = URLRequest(url: serverURL.appendingPathComponent("prompt"))
            promptRequest.httpMethod = "POST"
            promptRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                promptRequest.httpBody = try JSONSerialization.data(withJSONObject: promptBody)
            } catch {
                throw GenerationError.encodingFailed(error.localizedDescription)
            }
            
            var promptId: String?
            do {
                try Task.checkCancellation()
                let (promptData, _) = try await URLSession.shared.data(for: promptRequest)
                if let json = try? JSONSerialization.jsonObject(with: promptData) as? [String: Any],
                   let id = json["prompt_id"] as? String {
                    promptId = id
                } else {
                    throw GenerationError.queueFailed
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GenerationError.queueFailed
            }
            
            guard let promptId = promptId else { throw GenerationError.queueFailed }
            
            var history: [String: Any]? = nil
            while history == nil {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let historyURL = serverURL.appendingPathComponent("history/\(promptId)")
                var historyRequest = URLRequest(url: historyURL)
                do {
                    try Task.checkCancellation()
                    let (historyData, _) = try await URLSession.shared.data(for: historyRequest)
                    if let json = try? JSONSerialization.jsonObject(with: historyData) as? [String: Any],
                       let entry = json[promptId] as? [String: Any],
                       let status = entry["status"] as? [String: Any],
                       let completed = status["completed"] as? Bool, completed {
                        history = entry
                    }
                } catch is CancellationError {
                    throw CancellationError()
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
                throw GenerationError.noOutputImage
            }
            
            var components = URLComponents(url: serverURL.appendingPathComponent("view"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "filename", value: filename),
                URLQueryItem(name: "subfolder", value: subfolder),
                URLQueryItem(name: "type", value: type)
            ]
            guard let viewURL = components.url else {
                throw GenerationError.invalidViewURL
            }
            
            var viewRequest = URLRequest(url: viewURL)
            do {
                try Task.checkCancellation()
                let (viewData, _) = try await URLSession.shared.data(for: viewRequest)
                if let platformImage = PlatformImage(platformData: viewData) {
                    appState.ui.outputImage = platformImage
                    let savedPath = saveGeneratedImage(data: viewData)
                    appState.ui.responseText = "Image generated with ComfyUI. Saved to \(savedPath ?? "unknown")"
                    
                    let workflowName = URL(fileURLWithPath: appState.settings.comfyJSONPath).deletingPathExtension().lastPathComponent
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: workflowName)
                    appState.historyState.history.append(newItem)
                    appState.historyState.saveHistory()
                } else {
                    throw GenerationError.decodeFailed
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GenerationError.fetchFailed(error.localizedDescription)
            }
            // Set isCancelled before cancelling to suppress error
            isCancelled = true
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            progress = 0.0

        case .grok:
            guard let url = URL(string: "https://api.x.ai/v1/images/generations") else {
                throw GenerationError.invalidURL
            }
            
            var bodyDict: [String: Any] = [
                "model": appState.settings.selectedGrokModel,
                "prompt": appState.prompt,
                "n": 1,
                "response_format": "b64_json"
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(appState.settings.grokApiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            } catch {
                throw GenerationError.encodingFailed(error.localizedDescription)
            }
            
            try Task.checkCancellation()
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GrokImageResponse.self, from: data)
            if let revised = response.data.first?.revised_prompt {
                print("Revised prompt from Grok: \(revised)")
            }
            
            var textOutput = ""
            var savedImage: PlatformImage? = nil
            var savedPath: String? = nil
            
            if let item = response.data.first {
                if let revised = item.revised_prompt {
                    textOutput += "Revised prompt: \(revised)\n"
                }
                
                if let b64 = item.b64_json, let imgData = Data(base64Encoded: b64) {
                    savedImage = PlatformImage(platformData: imgData)
                    savedPath = saveGeneratedImage(data: imgData)
                    if let saved = savedPath {
                        textOutput += "Image saved to \(saved)\n"
                    }
                }
            }
        case .aimlapi:
                    guard let url = URL(string: "https://api.aimlapi.com/v1/images/generations") else {
                        throw GenerationError.invalidURL
                    }
                    
                    let selectedAIMLModel = appState.settings.selectedAIMLModel
                    var bodyDict: [String: Any] = [
                        "model": selectedAIMLModel,
                        "prompt": appState.prompt,
                        "num_images": 1,
                        "sync_mode": true,  // Wait for response
                        "enable_safety_checker": true,
                        "image_size": "square"
                    ]
                    
                    // Optional: Add seed, image_size (e.g., for models requiring it)
                    bodyDict["seed"] = Int(Date().timeIntervalSince1970)
//                    bodyDict["image_size"] = "1024x1024"  // Default; consider making configurable
                    
                    // Image handling for i2i/edit models
                    if !appState.ui.imageSlots.isEmpty && selectedAIMLModel.contains("edit") {
                        var imageUrls: [String] = []
                        for slot in appState.ui.imageSlots {
                            if let image = slot.image, let pngData = image.platformPngData() {
                                let safeData = stripExif(from: pngData) ?? pngData
                                let base64 = safeData.base64EncodedString()
                                imageUrls.append("data:image/png;base64,\(base64)")
                            }
                        }
                        if !imageUrls.isEmpty {
                            bodyDict["image_urls"] = imageUrls  // Up to 10
                        } else {
                            throw GenerationError.noOutputImage  // Require images for edit models
                        }
                    } else if appState.ui.imageSlots.isEmpty && selectedAIMLModel.contains("edit") {
                        appState.ui.responseText += "Edit model selected without images; treating as t2i if possible.\n"
                    } else if !appState.ui.imageSlots.isEmpty && !selectedAIMLModel.contains("edit") {
                        throw GenerationError.apiError("Text-to-image model selected with input images; select an edit/i2i model.")
                    }
            //print bodyDict
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: .prettyPrinted)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("bodyDict as JSON: \(jsonString)")
                }
            } catch {
                print("Failed to serialize bodyDict: \(error)")
            }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
                    
                    do {
                        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
                    } catch {
                        throw GenerationError.encodingFailed(error.localizedDescription)
                    }
                    
                    try Task.checkCancellation()
                    let (data, _) = try await URLSession.shared.data(for: request)
                    print(String(data: data, encoding: .utf8) ?? "No data")  // Add for debugging, like in .gemini
                    
                    let response = try JSONDecoder().decode(GrokImageResponse.self, from: data)  // Compatible; should decode without issues
                    
                    // Complete parsing (copied/adapted from .grok)
                    var textOutput = ""
                    var savedImage: PlatformImage? = nil
                    var savedPath: String? = nil
                    
                    if let item = response.data.first {
                        if let revised = item.revised_prompt {
                            textOutput += "Revised prompt: \(revised)\n"
                        }
                        
                        if let b64 = item.b64_json, let imgData = Data(base64Encoded: b64) {
                            savedImage = PlatformImage(platformData: imgData)
                            savedPath = saveGeneratedImage(data: imgData)
                            if let saved = savedPath {
                                textOutput += "Image saved to \(saved)\n"
                            }
                        } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
                            // Fallback: Download from URL if no b64_json (rare, but handles variations)
                            let (imgData, _) = try await URLSession.shared.data(from: url)
                            savedImage = PlatformImage(platformData: imgData)
                            savedPath = saveGeneratedImage(data: imgData)
                            if let saved = savedPath {
                                textOutput += "Image downloaded and saved to \(saved)\n"
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
                }
            

    }
    
    func stopGeneration() {
        isCancelled = true
        generationTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        progress = 0.0
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
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
    
    private func stripExif(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithData(NSMutableData() as CFMutableData, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil) // Copies without metadata
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (destination as? NSMutableData) as Data?
    }
    
    // New: Show consent alert and await user response
    @MainActor
    private func showGeminiConsentAlert() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(iOS)
            let alert = UIAlertController(
                title: "Data Sharing Notice",
                message: "Prompts and images will be sent to Google for generation. View Google's privacy policy?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "View Privacy Policy", style: .default) { _ in
                if let url = URL(string: "https://policies.google.com/privacy") {
                    UIApplication.shared.open(url)
                }
                continuation.resume(returning: false) // Don't proceed automatically after viewing
            })
            
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            // Present from top VC
            var topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let presentedVC = topVC?.presentedViewController {
                topVC = presentedVC
            }
            topVC?.present(alert, animated: true)
            #elseif os(macOS)
            let alert = NSAlert()
            alert.messageText = "Data Sharing Notice"
            alert.informativeText = "Prompts and images will be sent to Google for generation. View Google's privacy policy?"
            alert.addButton(withTitle: "View Privacy Policy")
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // View Privacy Policy
                if let url = URL(string: "https://policies.google.com/privacy") {
                    NSWorkspace.shared.open(url)
                }
                continuation.resume(returning: false)
            case .alertSecondButtonReturn: // Continue
                continuation.resume(returning: true)
            default: // Cancel
                continuation.resume(returning: false)
            }
            #endif
        }
    }
}

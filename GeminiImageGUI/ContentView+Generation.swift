#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Still needed if other parts use it, but can remove if not

struct ErrorDict: Codable {  // New: For Grok/aimlapi error parsing
    let message: String?
    let type: String?  // Optional, if API provides (e.g., "policy_violation")
    let code: Int?     // Optional error code
}

struct GrokImageResponse: Codable {
    let created: Int?
    let data: [GrokImageData]
    let error: ErrorDict?  // Updated: Now Codable struct
}

struct GrokImageData: Codable {
    let b64_json: String?
    let url: String?
    let revised_prompt: String?
}

struct ImgBBResponse: Codable {
    let data: ImgBBData?
    let success: Bool
    let status: Int
}

struct ImgBBData: Codable {
    let id: String
    let title: String?
    let url: String?  // Public URL to use
    // Other fields if needed
}

extension ContentView {
    func submitPrompt() {
        if outputPath.isEmpty {
            pendingAction = submitPrompt
            showSelectFolderAlert = true
            return
        }
        
        // Check if prompt is safe
        let (isSafe, offendingPhrases) = ContentView.isPromptSafe(appState.prompt)
        if !isSafe {
            let phrasesList = offendingPhrases.joined(separator: ", ")
            errorItem = AlertError(message: "Prompt contains inappropriate content. Offending phrase(s): \(phrasesList). Please revise and try again.", fullMessage: nil)
            return
        }
        
        isLoading = true
        errorItem = nil
        appState.ui.outputImages = []
        appState.ui.outputTexts = []
        appState.ui.outputPaths = []
        appState.ui.currentOutputIndex = 0
        
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
                    if let genError = error as? GenerationError {
                        switch genError {
                        case .queueFailed(let details), .uploadFailed(let details), .fetchFailed(let details):
                            print("Detailed Error Message: \(details)")
                            errorItem = AlertError(message: details, fullMessage: nil)
                        default:
                            errorItem = AlertError(message: error.localizedDescription ?? "Unknown error", fullMessage: nil)
                        }
                    } else {
                        errorItem = AlertError(message: error.localizedDescription ?? "Unknown error", fullMessage: nil)
                    }
                    }
                }
            }
        }
    
    func asyncGenerate() async throws {
            try Task.checkCancellation()
            
            switch appState.settings.mode {
            case .gemini:
                // Show consent alert on first Gemini use
                if !UserDefaults.standard.bool(forKey: "hasShownGeminiConsent") {
                    let consented = await showGeminiConsentAlert()
                    if !consented {
                        throw GenerationError.apiError("User did not consent to data sharing.")
                    }
                    UserDefaults.standard.set(true, forKey: "hasShownGeminiConsent")
                }
                
                var parts: [Part] = [Part(text: appState.prompt, inlineData: nil)]
                
                for slot in appState.ui.imageSlots {
                    if let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "jpeg", isBase64: true, convertToJPG: appState.settings.base64ConvertToJPG, scale50Percent: appState.settings.base64Scale50Percent) {
                        let base64 = processed.data.base64EncodedString()
                        let inline = InlineData(mimeType: processed.mimeType, data: base64)
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
                
                if let candidate = response.candidates.first, let finishReason = candidate.finishReason, finishReason == "SAFETY" {
                        await MainActor.run {
                            appState.ui.outputTexts = ["Generation blocked for safety reasons. Please revise your prompt."]
                            appState.ui.outputImages = []
                            appState.ui.outputPaths = []
                        }
                        throw GenerationError.apiError("Blocked due to safety violation")
                    }
                
                if response.candidates.isEmpty {
                        await MainActor.run {
                            appState.ui.outputTexts = ["Prompt blocked for safety or policy reasons."]
                            appState.ui.outputImages = []
                            appState.ui.outputPaths = []
                        }
                        throw GenerationError.apiError("Prompt blocked")
                    }
                
                var images: [PlatformImage?] = []
                var texts: [String] = []
                var paths: [String?] = []
                
                for part in response.candidates.first?.content.parts ?? [] {
                    var textOutput = ""
                    if let text = part.text {
                        textOutput += text + "\n"
                    } else if let inline = part.inlineData, let imgData = Data(base64Encoded: inline.data) {
                        let image = PlatformImage(platformData: imgData)
                        let path = saveGeneratedImage(data: imgData, prompt: appState.prompt, mode: .gemini)
                        if let saved = path {
                            textOutput += "Image saved to \(saved)\n"
                        }
                        images.append(image)
                        texts.append(textOutput)
                        paths.append(path)
                    }
                }
                
                // If no images but text, add empty image with text (optional; adjust if needed)
                if images.isEmpty && !texts.isEmpty {
                    images.append(nil)
                    paths.append(nil)
                }
                
                await MainActor.run {
                    appState.ui.outputImages = images
                    appState.ui.outputTexts = texts
                    appState.ui.outputPaths = paths
                    appState.ui.currentOutputIndex = 0
                }
                
                // Add to history as separate items
                let batchId = images.count > 1 ? UUID() : nil
                let total = images.count
                for i in 0..<total {
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: texts[i], imagePath: paths[i], date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: nil, batchId: batchId, indexInBatch: i, totalInBatch: total)
                    appState.historyState.history.append(.item(newItem))
                }
                appState.historyState.saveHistory()
                
            case .comfyUI:
                guard let workflow = appState.generation.comfyWorkflow else {
                    throw GenerationError.noWorkflow
                }
                
                guard let serverURL = URL(string: appState.settings.comfyServerURL) else {
                    throw GenerationError.invalidServerURL
                }
                
                var mutableWorkflow = workflow
                
                // NEW: Find sampler node ID (assume first KSampler or similar)
                var samplerNodeID: String? = nil
                for (nodeID, node) in mutableWorkflow {
                    guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                    if classType.contains("KSampler") {  // Adjust if your workflows use other samplers, e.g., "KSamplerAdvanced"
                        samplerNodeID = nodeID
                        break
                    }
                }
                guard let samplerNodeID = samplerNodeID else {
                    throw GenerationError.noSamplerNode
                }
                
                // UPDATED: Always set batch_size to 1 on EmptyLatentImage (if present) to force single per run
                var hasEmptyLatent = false
                for (nodeID, node) in mutableWorkflow {
                    guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                    if classType == "EmptyLatentImage" {
                        if var inputs = nodeDict["inputs"] as? [String: Any] {
                            inputs["batch_size"] = 1  // Force 1 to use loop for batching with new seeds
                            var updatedNode = nodeDict
                            updatedNode["inputs"] = inputs
                            mutableWorkflow[nodeID] = updatedNode
                            hasEmptyLatent = true
                            print("Batch size forced to 1 in node \(nodeID) for per-run seeding")
                            break
                        }
                    }
                }
                if !hasEmptyLatent {
                    print("No EmptyLatentImage node found; assuming i2i or custom workflow. Proceeding with single per run.")
                }
                
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
                
                // Listen for messages in a loop (unchanged)
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
                                    errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
                                }
                            }
                            break
                        }
                    }
                }
                let selectedImageNodes = Array(appState.generation.selectedImageNodeIDs).sorted()
                var uploadedFilenames: [String] = []
                if !selectedImageNodes.isEmpty && !appState.ui.imageSlots.isEmpty {
                    for i in 0..<min(selectedImageNodes.count, appState.ui.imageSlots.count) {
                        let slot = appState.ui.imageSlots[i]
                        if let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "png") {
                            var uploadRequest = URLRequest(url: serverURL.appendingPathComponent("upload/image"))
                            uploadRequest.httpMethod = "POST"
                            
                            let boundary = "Boundary-\(UUID().uuidString)"
                            uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                            
                            var body = Data()
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            let fileExtension = processed.mimeType == "image/jpeg" ? "jpg" : "png"
                            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input_\(i).\(fileExtension)\"\r\n".data(using: .utf8)!)
                            body.append("Content-Type: \(processed.mimeType)\r\n\r\n".data(using: .utf8)!)
                            body.append(processed.data)
                            body.append("\r\n".data(using: .utf8)!)
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                            
                            uploadRequest.httpBody = body
                            
                            do {
                                try Task.checkCancellation()
                                let (data, response) = try await URLSession.shared.data(for: uploadRequest)
                                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                       let name = json["name"] as? String {
                                        uploadedFilenames.append(name)
                                    } else {
                                        let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                                        print("Upload response: \(bodyString)")
                                        throw GenerationError.uploadFailed(bodyString)
                                    }
                                } else {
                                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                                    let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                                    print("Upload failed with status \(statusCode): \(bodyString)")
                                    throw GenerationError.uploadFailed("Status \(statusCode): \(bodyString)")
                                }
                            } catch {
                                print("Upload error: \(error.localizedDescription)")
                                throw error
                            }
                        }
                    }
                    
                    // Inject uploaded filenames into selected nodes
                    for i in 0..<uploadedFilenames.count {
                        let nodeID = selectedImageNodes[i]
                        if var node = mutableWorkflow[nodeID] as? [String: Any],
                           var inputs = node["inputs"] as? [String: Any] {
                            inputs["image"] = uploadedFilenames[i]
                            node["inputs"] = inputs
                            mutableWorkflow[nodeID] = node
                        } else {
                            throw GenerationError.invalidImageNode
                        }
                    }
                }
                
                let promptNodeID = appState.generation.comfyPromptNodeID
                let selectedPromptText = appState.generation.promptNodes.first(where: { $0.id == promptNodeID })?.promptText ?? ""
                let effectivePrompt = appState.prompt.isEmpty ? selectedPromptText : appState.prompt
                
                if var node = mutableWorkflow[promptNodeID] as? [String: Any],
                   var inputs = node["inputs"] as? [String: Any] {
                    var setCount = 0
                    for (key, value) in inputs {
                        if let _ = value as? String {  // Only target string-valued inputs
                            let lowerKey = key.lowercased()
                            if (lowerKey.contains("prompt") && !lowerKey.contains("negativ")) ||
                               lowerKey.contains("text") ||
                               lowerKey.contains("positiv") {
                                inputs[key] = effectivePrompt
                                setCount += 1
                            }
                        }
                    }
                    if setCount == 0 {
                        throw GenerationError.invalidPromptNode  // Or custom: "No injectable prompt key found in node"
                    }
                    node["inputs"] = inputs
                    mutableWorkflow[promptNodeID] = node
                } else {
                    throw GenerationError.invalidPromptNode
                }
                
                // NEW: Arrays for multiples (moved up)
                var outputImages: [PlatformImage?] = []
                var outputTexts: [String] = []
                var outputPaths: [String?] = []
                
                // NEW: Loop for each batch item
                let batchSize = appState.settings.comfyBatchSize
                let workflowName = URL(fileURLWithPath: appState.settings.comfyJSONPath).deletingPathExtension().lastPathComponent  // MOVED UP: Define before loop
                for batchIndex in 0..<batchSize {
                    try Task.checkCancellation()
                    
                    // Clone workflow for this run to avoid mutating shared state
                    var runWorkflow = mutableWorkflow
                    
                    // Set new random seed in sampler
                    let newSeed = Int.random(in: 0...Int.max)  // Or use UInt64 if your sampler expects it
                    if var samplerNode = runWorkflow[samplerNodeID] as? [String: Any],
                       var inputs = samplerNode["inputs"] as? [String: Any] {
                        inputs["seed"] = newSeed  // Or "noise_seed" if using KSamplerAdvanced
                        samplerNode["inputs"] = inputs
                        runWorkflow[samplerNodeID] = samplerNode
                        print("Set new seed \(newSeed) for batch item \(batchIndex + 1)")
                    }
                    
                    // Queue prompt (adapted from existing)
                    let promptBody: [String: Any] = ["prompt": runWorkflow, "client_id": clientId]
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
                        let (promptData, response) = try await URLSession.shared.data(for: promptRequest)
                        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                            if let json = try? JSONSerialization.jsonObject(with: promptData) as? [String: Any],
                               let id = json["prompt_id"] as? String {
                                promptId = id
                            } else {
                                let bodyString = String(data: promptData, encoding: .utf8) ?? "No body"
                                print("Queue prompt response: \(bodyString)")
                                throw GenerationError.queueFailed(bodyString)
                            }
                        } else {
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            let bodyString = String(data: promptData, encoding: .utf8) ?? "No body"
                            print("Queue prompt failed with status \(statusCode): \(bodyString)")
                            throw GenerationError.queueFailed("Queue prompt failed with status \(statusCode): \(bodyString)")
                        }
                    } catch {
                        print("Queue prompt error: \(error.localizedDescription)")
                        throw error
                    }
                    
                    guard let promptId = promptId else { throw GenerationError.queueFailed("No prompt ID") }
                    
                    // Wait for history (adapted from existing)
                    var history: [String: Any]? = nil
                    while history == nil {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        let historyURL = serverURL.appendingPathComponent("history/\(promptId)")
                        var historyRequest = URLRequest(url: historyURL)
                        do {
                            try Task.checkCancellation()
                            let (historyData, response) = try await URLSession.shared.data(for: historyRequest)
                            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                                if let json = try? JSONSerialization.jsonObject(with: historyData) as? [String: Any],
                                   let entry = json[promptId] as? [String: Any],
                                   let status = entry["status"] as? [String: Any],
                                   let completed = status["completed"] as? Bool, completed {
                                    history = entry
                                }
                            } else {
                                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                                let bodyString = String(data: historyData, encoding: .utf8) ?? "No body"
                                print("History fetch failed with status \(statusCode): \(bodyString)")
                            }
                        } catch {
                            print("History fetch error: \(error.localizedDescription)")
                        }
                    }
                    
                    guard let unwrappedHistory = history else {
                        throw GenerationError.noOutputImage
                    }
                    guard let outputs = unwrappedHistory["outputs"] as? [String: Any],
                          let outputNode = outputs[appState.generation.comfyOutputNodeID] as? [String: Any],
                          let images = outputNode["images"] as? [[String: Any]] else {
                        throw GenerationError.noOutputImage
                    }
                    
                    print("Fetched images count for batch \(batchIndex + 1): \(images.count)")  // Debug
                    
                    // Fetch image (expect 1 per run)
                    guard let imageDict = images.first else { continue }  // Skip if no image
                    guard let filename = imageDict["filename"] as? String,
                          let subfolder = imageDict["subfolder"] as? String,
                          let type = imageDict["type"] as? String else { continue }
                    
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
                        let (viewData, response) = try await URLSession.shared.data(for: viewRequest)
                        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                            if let platformImage = PlatformImage(platformData: viewData) {
                                let savedPath = saveGeneratedImage(data: viewData, prompt: effectivePrompt, mode: .comfyUI, workflowName: workflowName, batchIndex: batchIndex, totalInBatch: batchSize)
                                outputImages.append(platformImage)
                                outputTexts.append("Batch image \(batchIndex + 1) generated with ComfyUI (seed: \(newSeed)). Saved to \(savedPath ?? "unknown")")
                                outputPaths.append(savedPath)
                                
                                // NEW: Update UI incrementally after each image (shows in response section as they generate)
                                await MainActor.run {
                                    appState.ui.outputImages = outputImages
                                    appState.ui.outputTexts = outputTexts
                                    appState.ui.outputPaths = outputPaths
                                    appState.ui.currentOutputIndex = outputImages.count - 1  // Optional: Switch to the latest one
                                    print("Updated UI with \(outputImages.count) images so far")  // Debug: Confirm in console
                                }
                            } else {
                                throw GenerationError.decodeFailed
                            }
                        } else {
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            let bodyString = String(data: viewData, encoding: .utf8) ?? "No body"
                            print("Image view failed with status \(statusCode): \(bodyString)")
                            throw GenerationError.fetchFailed("Status \(statusCode): \(bodyString)")
                        }
                    } catch {
                        print("Image view error: \(error.localizedDescription)")
                        throw error
                    }
                }
                
                // Remove the old bulk UI set (now handled incrementally)
                
                // Add to history
                let batchId = outputImages.count > 1 ? UUID() : nil
                let total = outputImages.count
                for i in 0..<total {
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: outputTexts[i], imagePath: outputPaths[i], date: Date(), mode: appState.settings.mode, workflowName: workflowName, modelUsed: nil, batchId: batchId, indexInBatch: i, totalInBatch: total)
                    appState.historyState.history.append(.item(newItem))
                }
                appState.historyState.saveHistory()
                
                // Cleanup (unchanged)
                isCancelled = true
                webSocketTask?.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil
                progress = 0.0
                
            case .grok:
                // Show consent alert on first Grok use
                if !UserDefaults.standard.bool(forKey: "hasShownGrokConsent") {
                    let consented = await showGrokConsentAlert()
                    if !consented {
                        throw GenerationError.apiError("User did not consent to data sharing.")
                    }
                    UserDefaults.standard.set(true, forKey: "hasShownGrokConsent")
                }
                
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
                if let error = response.error {
                        var message = error.message ?? "Unknown error"
                        if message.lowercased().contains("policy") || message.lowercased().contains("safety") || message.lowercased().contains("violation") {
                            message += " (Likely safety/content violation)"
                            await MainActor.run {
                                appState.ui.outputTexts = ["Generation blocked for content policy violation: \(message)"]
                                appState.ui.outputImages = []
                                appState.ui.outputPaths = []
                            }
                            throw GenerationError.apiError("Blocked due to policy violation")
                        } else {
                            await MainActor.run {
                                appState.ui.outputTexts = ["API Error: \(message)"]
                                appState.ui.outputImages = []
                                appState.ui.outputPaths = []
                            }
                            throw GenerationError.apiError(message)
                        }
                    }
                
                var images: [PlatformImage?] = []
                var texts: [String] = []
                var paths: [String?] = []
                
                let total = response.data.count  // MOVED UP: Define before loop
                for (i, item) in response.data.enumerated() {
                    var textOutput = ""
                    if let revised = item.revised_prompt {
                        textOutput += "Revised prompt: \(revised)\n"
                    }
                    
                    var imgData: Data?
                    if let b64 = item.b64_json {
                        imgData = Data(base64Encoded: b64)
                    } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        imgData = data
                    }
                    
                    if let data = imgData {
                        let image = PlatformImage(platformData: data)
                        let path = saveGeneratedImage(data: data, prompt: appState.prompt, mode: .grok, modelUsed: appState.settings.selectedGrokModel, batchIndex: i, totalInBatch: total)
                        if let saved = path {
                            textOutput += "Image saved to \(saved)\n"
                        }
                        images.append(image)
                        texts.append(textOutput)
                        paths.append(path)
                    } else {
                        images.append(nil)
                        paths.append(nil)
                        texts.append(textOutput.isEmpty ? "No output for item \(i+1)" : textOutput)
                    }
                }
                
                await MainActor.run {
                    appState.ui.outputImages = images
                    appState.ui.outputTexts = texts
                    appState.ui.outputPaths = paths
                    appState.ui.currentOutputIndex = 0
                }
                
                let batchId = images.count > 1 ? UUID() : nil
                for i in 0..<total {
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: texts[i], imagePath: paths[i], date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: appState.settings.selectedGrokModel, batchId: batchId, indexInBatch: i, totalInBatch: total)
                    appState.historyState.history.append(.item(newItem))
                }
                appState.historyState.saveHistory()
                
            case .aimlapi:
                // Show consent alert on first AI/ML API use
                if !UserDefaults.standard.bool(forKey: "hasShownAIMLConsent") {
                    let consented = await showAIMLConsentAlert()
                    if !consented {
                        throw GenerationError.apiError("User did not consent to data sharing.")
                    }
                    UserDefaults.standard.set(true, forKey: "hasShownAIMLConsent")
                }
                
                guard let model = appState.currentAIMLModel else {
                    throw GenerationError.apiError("Invalid model selected.")
                }
                
                // Validate images
                if model.isI2I && appState.ui.imageSlots.isEmpty {
                    throw GenerationError.apiError("Image required for image-to-image model.")
                }
                if appState.ui.imageSlots.count > model.maxInputImages {
                    throw GenerationError.apiError("Too many images for model (max: \(model.maxInputImages)).")
                }
                if !appState.ui.imageSlots.isEmpty && !model.isI2I {
                    throw GenerationError.apiError("Text-to-image model selected with input images; select an i2i model.")
                }
                
                guard let url = URL(string: "https://api.aimlapi.com/v1/images/generations") else {
                    throw GenerationError.invalidURL
                }
                
                var bodyDict: [String: Any] = [
                    "model": appState.settings.selectedAIMLModel,
                    "prompt": appState.prompt,
                    "num_images": appState.settings.aimlAdvancedParams.numImages ?? 1,
                    "sync_mode": true,
                    "enable_safety_checker": appState.settings.aimlAdvancedParams.enableSafetyChecker ?? true
                ]
                
                // Inject advanced params if supported
                if let strength = appState.settings.aimlAdvancedParams.strength, model.supportedParams.contains(.strength) {
                    bodyDict["strength"] = strength
                }
                if let steps = appState.settings.aimlAdvancedParams.numInferenceSteps, model.supportedParams.contains(.numInferenceSteps) {
                    bodyDict["num_inference_steps"] = steps
                }
                if let guidance = appState.settings.aimlAdvancedParams.guidanceScale, model.supportedParams.contains(.guidanceScale) {
                    bodyDict["guidance_scale"] = guidance
                }
                if let negative = appState.settings.aimlAdvancedParams.negativePrompt, model.supportedParams.contains(.negativePrompt) {
                    bodyDict["negative_prompt"] = negative
                }
                if let seed = appState.settings.aimlAdvancedParams.seed, model.supportedParams.contains(.seed) {
                    bodyDict["seed"] = seed
                }
                // Model-specific, e.g., watermark
                if let watermark = appState.settings.aimlAdvancedParams.watermark, model.supportedParams.contains(.watermark) {
                    bodyDict["watermark"] = watermark
                }
                if let enhance = appState.settings.aimlAdvancedParams.enhancePrompt, model.supportedParams.contains(.enhancePrompt) {
                    bodyDict["enhance_prompt"] = enhance
                }
                
                // Image handling with ImgBB preference
                var imageInputs: [String] = []
                let useImgBB = appState.preferImgBBForImages && model.acceptsPublicURL
                
                for slot in appState.ui.imageSlots {
                    guard let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "jpeg", isBase64: appState.settings.imageSubmissionMethod == .base64, convertToJPG: appState.settings.base64ConvertToJPG, scale50Percent: appState.settings.base64Scale50Percent)
                    else {
                        continue
                    }
                    if useImgBB {
                        guard !appState.settings.imgbbApiKey.isEmpty else {
                            throw GenerationError.apiError("ImgBB API key required for public image upload.")
                        }
                        
                        guard let uploadURL = URL(string: "https://api.imgbb.com/1/upload?key=\(appState.settings.imgbbApiKey)&expiration=600") else {
                            throw GenerationError.invalidURL
                        }
                        
                        var uploadRequest = URLRequest(url: uploadURL)
                        uploadRequest.httpMethod = "POST"
                        
                        let boundary = "Boundary-\(UUID().uuidString)"
                        uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                        
                        var body = Data()
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        body.append("Content-Disposition: form-data; name=\"image\"\r\n\r\n".data(using: .utf8)!)
                        body.append(processed.data.base64EncodedString().data(using: .utf8)!)
                        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                        
                        uploadRequest.httpBody = body
                        
                        let (uploadData, _) = try await URLSession.shared.data(for: uploadRequest)
                        let uploadResponse = try JSONDecoder().decode(ImgBBResponse.self, from: uploadData)
                        
                        guard let imagePublicUrl = uploadResponse.data?.url else {
                            throw GenerationError.apiError("Failed to upload image to public host.")
                        }
                        imageInputs.append(imagePublicUrl)
                    } else if model.acceptsBase64 {
                        let base64 = processed.data.base64EncodedString()
                        imageInputs.append("data:\(processed.mimeType);base64,\(base64)")
                    } else {
                        throw GenerationError.apiError("Model does not support image format.")
                    }
                }
                
                if model.isI2I && !imageInputs.isEmpty {
                    if model.acceptsMultiImages {
                        bodyDict[model.imageInputParam] = imageInputs
                    } else {
                        bodyDict[model.imageInputParam] = imageInputs.first!
                    }
                }
                
                // Resolution/size
                if model.supportsCustomResolution {
                    bodyDict["image_size"] = [
                        "width": appState.settings.selectedImageWidth,
                        "height": appState.settings.selectedImageHeight
                    ]
                } else {
                    bodyDict["image_size"] = appState.settings.selectedImageSize
                }
                
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
                print(String(data: data, encoding: .utf8) ?? "No data")
                let response = try JSONDecoder().decode(GrokImageResponse.self, from: data)
                
                if let error = response.error {
                    var message = error.message ?? "Unknown error"
                    if message.lowercased().contains("safety") || message.lowercased().contains("violation") || message.lowercased().contains("content policy") {
                        message += " (Likely safety/content violation)"
                    }
                    await MainActor.run {
                        appState.ui.outputTexts = ["API Error: \(message)"]
                        appState.ui.outputImages = []
                        appState.ui.outputPaths = []
                    }
                    throw GenerationError.apiError(message)
                }
                
                var images: [PlatformImage?] = []
                var texts: [String] = []
                var paths: [String?] = []
                
                let total = response.data.count  // MOVED UP: Define before loop
                for (i, item) in response.data.enumerated() {
                    var textOutput = ""
                    if let revised = item.revised_prompt {
                        textOutput += "Revised prompt: \(revised)\n"
                    }
                    
                    var imgData: Data?
                    if let b64 = item.b64_json {
                        imgData = Data(base64Encoded: b64)
                    } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        imgData = data
                    }
                    
                    if let data = imgData {
                        let image = PlatformImage(platformData: data)
                        let path = saveGeneratedImage(data: data, prompt: appState.prompt, mode: .aimlapi, modelUsed: appState.settings.selectedAIMLModel, batchIndex: i, totalInBatch: total)
                        if let saved = path {
                            textOutput += "Image saved to \(saved)\n"
                        }
                        images.append(image)
                        texts.append(textOutput)
                        paths.append(path)
                    } else {
                        images.append(nil)
                        paths.append(nil)
                        texts.append(textOutput.isEmpty ? "No output for item \(i+1)" : textOutput)
                    }
                }
                
                await MainActor.run {
                    appState.ui.outputImages = images
                    appState.ui.outputTexts = texts
                    appState.ui.outputPaths = paths
                    appState.ui.currentOutputIndex = 0
                }
                
                let batchId = images.count > 1 ? UUID() : nil
                for i in 0..<total {
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: texts[i], imagePath: paths[i], date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: appState.settings.selectedAIMLModel, batchId: batchId, indexInBatch: i, totalInBatch: total)
                    appState.historyState.history.append(.item(newItem))
                }
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
                    errorItem = AlertError(message: "Stop error: \(error.localizedDescription)", fullMessage: nil)
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    errorItem = AlertError(message: "Generation stopped.", fullMessage: nil)
                }
            }
        }.resume()
    }
}


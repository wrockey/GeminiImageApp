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
            errorItem = AlertError(message: "Prompt contains inappropriate content. Offending phrase(s): \(phrasesList). Please revise and try again.")
            return
        }
        
        isLoading = true
        errorItem = nil
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
                    errorItem = AlertError(message: "API error: \(error.localizedDescription)")
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
                if let image = slot.image, let processed = processImageForUpload(image: image) {
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
                    DispatchQueue.main.async {
                        appState.ui.responseText = "Generation blocked for safety reasons. Please revise your prompt."
                    }
                    throw GenerationError.apiError("Blocked due to safety violation")
                }
            
            if response.candidates.isEmpty {
                    DispatchQueue.main.async {
                        appState.ui.responseText = "Prompt blocked for safety or policy reasons."
                    }
                    throw GenerationError.apiError("Prompt blocked")
                }
            
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
            
            let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: nil)
            appState.historyState.history.append(newItem)
            appState.historyState.saveHistory()
        case .comfyUI:
            // Existing ComfyUI logic (unchanged, as it's not AI/ML specific)
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
                                errorItem = AlertError(message: "WebSocket error: \(error.localizedDescription)")
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
               let slot = appState.ui.imageSlots.first,
               let image = slot.image,
               let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "png") {
                var uploadRequest = URLRequest(url: serverURL.appendingPathComponent("upload/image"))
                uploadRequest.httpMethod = "POST"
                
                let boundary = "Boundary-\(UUID().uuidString)"
                uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                let fileExtension = processed.mimeType == "image/jpeg" ? "jpg" : "png"
                body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input.\(fileExtension)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(processed.mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(processed.data)
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
                    let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: workflowName, modelUsed: nil)
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
                        DispatchQueue.main.async {
                            appState.ui.responseText = "Generation blocked for content policy violation: \(message)"
                        }
                        throw GenerationError.apiError("Blocked due to policy violation")
                    } else {
                        DispatchQueue.main.async {
                            appState.ui.responseText = "API Error: \(message)"
                        }
                        throw GenerationError.apiError(message)
                    }
                }
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
            
            appState.ui.responseText = textOutput.isEmpty ? "No text output." : textOutput
            appState.ui.outputImage = savedImage
            
            if savedImage == nil {
                appState.ui.responseText += "No image generated."
            }
            
            let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: appState.settings.selectedGrokModel)
            appState.historyState.history.append(newItem)
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
                guard let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "jpeg") else { continue }
                
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
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            print(String(data: data, encoding: .utf8) ?? "No data")
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                await MainActor.run {
                    appState.ui.responseText = "API Error: Invalid response type"
                }
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                let response = try JSONDecoder().decode(GrokImageResponse.self, from: data)
                
                if let error = response.error {
                    var message = error.message ?? "Unknown error"
                    if message.lowercased().contains("safety") || message.lowercased().contains("violation") || message.lowercased().contains("content policy") {
                        message += " (Likely safety/content violation)"
                    }
                    await MainActor.run {
                        appState.ui.responseText = "API Error: \(message)"
                    }
                    throw GenerationError.apiError(message)
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
                    } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
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
                
                let newItem = HistoryItem(prompt: appState.prompt, responseText: appState.ui.responseText, imagePath: savedPath, date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: appState.settings.selectedAIMLModel)
                appState.historyState.history.append(newItem)
                appState.historyState.saveHistory()
            } else {
                // Handle API error
                var errorMessage = "API Error: Status code \(httpResponse.statusCode)"
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let message = errorJson["message"] as? String {
                        errorMessage = "API Error: \(message)"
                        if message.lowercased().contains("safety") || message.lowercased().contains("violation") || message.lowercased().contains("content policy") {
                            errorMessage += " (Likely safety/content violation)"
                        }
                    }
                    if let meta = errorJson["meta"] as? [String: Any],
                       let fieldErrors = meta["fieldErrors"] as? [String: [String]] {
                        let messages = fieldErrors.flatMap { (field, errs) in
                            errs.map { "\(field): \($0)" }
                        }.joined(separator: "\n")
                        if !messages.isEmpty {
                            errorMessage += "\n\(messages)"
                        }
                    } else if let errorStr = errorJson["error"] as? String {
                        errorMessage = "API Error: \(errorStr)"
                    }
                }
                await MainActor.run {
                    appState.ui.responseText = errorMessage
                }
                throw GenerationError.apiError(errorMessage)
            }
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
                    errorItem = AlertError(message: "Stop error: \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    errorItem = AlertError(message: "Generation stopped.")
                }
            }
        }.resume()
    }
}

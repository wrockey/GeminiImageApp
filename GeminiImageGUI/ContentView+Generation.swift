// ContentView+Generation.swift
import Foundation

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
        
        Task {
            defer { isLoading = false }
            
            do {
                try await asyncGenerate()
            } catch {
                errorMessage = "API error: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    func asyncGenerate() async throws {
        switch appState.settings.mode {
        case .gemini:
            var parts: [Part] = [Part(text: appState.prompt, inlineData: nil)]
            
            for slot in appState.ui.imageSlots {
                if let image = slot.image, let pngData = image.platformPngData() {
                    let base64 = pngData.base64EncodedString()
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
                                          value["node"] == nil {  // Completion indicator: node is null
                                    isComplete = true
                                } else if type == "execution_success" {  // Alternative completion indicator
                                    isComplete = true
                                }
                            }
                        default: break
                        }
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
                var uploadRequest = URLRequest(url: serverURL.appendingPathComponent("upload/image"))
                uploadRequest.httpMethod = "POST"
                
                let boundary = "Boundary-\(UUID().uuidString)"
                uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input.png\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
                body.append(pngData)
                body.append("\r\n".data(using: .utf8)!)
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                uploadRequest.httpBody = body
                
                do {
                    let (data, _) = try await URLSession.shared.data(for: uploadRequest)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = json["name"] as? String {
                        uploadedFilename = name
                    } else {
                        throw GenerationError.uploadFailed
                    }
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
                let (promptData, _) = try await URLSession.shared.data(for: promptRequest)
                if let json = try? JSONSerialization.jsonObject(with: promptData) as? [String: Any],
                   let id = json["prompt_id"] as? String {
                    promptId = id
                } else {
                    throw GenerationError.queueFailed
                }
            } catch {
                throw GenerationError.queueFailed
            }
            
            guard let promptId = promptId else { throw GenerationError.queueFailed }
            
            var history: [String: Any]? = nil
            while history == nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let historyURL = serverURL.appendingPathComponent("history/\(promptId)")
                var historyRequest = URLRequest(url: historyURL)
                do {
                    let (historyData, _) = try await URLSession.shared.data(for: historyRequest)
                    if let json = try? JSONSerialization.jsonObject(with: historyData) as? [String: Any],
                       let entry = json[promptId] as? [String: Any],
                       let status = entry["status"] as? [String: Any],
                       let completed = status["completed"] as? Bool, completed {
                        history = entry
                    }
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
            } catch {
                throw GenerationError.fetchFailed(error.localizedDescription)
            }
            // Set isCancelled before cancelling to suppress error
            isCancelled = true
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            progress = 0.0
        }
    }
    
    func stopGeneration() {
        isCancelled = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        progress = 0.0
        
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
}

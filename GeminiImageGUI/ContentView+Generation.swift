import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import AVFoundation

struct ErrorDict: Codable {
    let message: String?
    let type: String?
    let code: Int?
}

struct GrokImageResponse: Codable {
    let created: Int?
    let data: [GrokImageData]
    let error: ErrorDict?
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
    let url: String?
}

struct AIMLVideoGenerationResponse: Codable {
    let generation_id: String?
    let error: ErrorDict?
}

struct AIMLVideoPollResponse: Codable {
    let id: String
    let status: String
    let video: AIMLVideoURL?
    let error: ErrorDict?
}

struct AIMLVideoURL: Codable {
    let url: String
}

extension ContentView {
    func submitPrompt() {
        if outputPath.isEmpty {
            pendingAction = submitPrompt
            showSelectFolderAlert = true
            return
        }
        
        let (isSafe, offendingPhrases) = ContentView.isPromptSafe(appState.prompt)
        if !isSafe {
            let phrasesList = offendingPhrases.joined(separator: ", ")
            errorItem = AlertError(message: "Prompt contains inappropriate content. Offending phrase(s): \(phrasesList). Please revise and try again.", fullMessage: nil)
            return
        }
        
        switch appState.settings.mode {
        case .gemini:
            guard !appState.settings.apiKey.isEmpty else {
                errorItem = AlertError(message: "Gemini API key is missing.", fullMessage: nil)
                return
            }
        case .grok:
            guard !appState.settings.grokApiKey.isEmpty else {
                errorItem = AlertError(message: "Grok API key is missing.", fullMessage: nil)
                return
            }
        case .aimlapi:
            guard !appState.settings.aimlapiKey.isEmpty else {
                errorItem = AlertError(message: "AI/ML API key is missing.", fullMessage: nil)
                return
            }
        default:
            break
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
                        case .queueFailed, .uploadFailed, .fetchFailed:
                            print("Detailed Error Message: \(genError.details ?? "")")
                            let summary = (genError.details ?? "").contains("missing") ? "ComfyUI error: Workflow issue (e.g., missing nodes)." : "ComfyUI request failed."
                            errorItem = AlertError(message: summary, fullMessage: genError.details)
                        default:
                            errorItem = AlertError(message: genError.errorDescription ?? "Unknown error", fullMessage: genError.details)
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
            if !(await showPrivacyNotice(for: .gemini)) {
                throw GenerationError.apiError("User declined privacy notice.")
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw GenerationError.apiError("Status \(status): \(bodyString)")
            }
            
            print(String(data: data, encoding: .utf8) ?? "No data")
            let responseDecoded = try JSONDecoder().decode(NewGenerateContentResponse.self, from: data)
            
            if let candidate = responseDecoded.candidates.first, let finishReason = candidate.finishReason, finishReason == "SAFETY" {
                await MainActor.run {
                    appState.ui.outputTexts = ["Generation blocked for safety reasons. Please revise your prompt."]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                throw GenerationError.apiError("Blocked due to safety violation")
            }
            
            if responseDecoded.candidates.isEmpty {
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
            
            for part in responseDecoded.candidates.first?.content.parts ?? [] {
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
            // ... (rest of .comfyUI code unchanged)
            
        case .grok:
            if !(await showPrivacyNotice(for: .grok)) {
                throw GenerationError.apiError("User declined privacy notice.")
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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw GenerationError.apiError("Status \(status): \(bodyString)")
            }
            
            let responseDecoded = try JSONDecoder().decode(GrokImageResponse.self, from: data)
            if let error = responseDecoded.error {
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
            
            let total = responseDecoded.data.count
            for (i, item) in responseDecoded.data.enumerated() {
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
            if !(await showPrivacyNotice(for: .aimlapi)) {
                throw GenerationError.apiError("User declined privacy notice.")
            }
            
            guard let model = appState.currentAIMLModel else {
                throw GenerationError.apiError("Invalid model selected.")
            }
            
            if model.isI2I && appState.ui.imageSlots.isEmpty {
                throw GenerationError.apiError("Image required for image-to-image model.")
            }
            if appState.ui.imageSlots.count > model.maxInputImages {
                throw GenerationError.apiError("Too many images for model (max: \(model.maxInputImages)).")
            }
            if !appState.ui.imageSlots.isEmpty && !model.isI2I {
                throw GenerationError.apiError("Text-to-image model selected with input images; select an i2i model.")
            }
            
            if appState.settings.isVideoMode {
                // Video generation logic
                let parts = appState.settings.selectedAIMLModel.split(separator: "/")
                guard parts.count >= 2 else {
                    throw GenerationError.apiError("Invalid model format for video generation.")
                }
                let provider = String(parts[0])
                let modelName = parts[1...].joined(separator: "/")
                
                let urlString = "https://api.aimlapi.com/v2/generate/video/\(provider)/generation"
                guard let url = URL(string: urlString) else {
                    throw GenerationError.invalidURL
                }
                
                // Build prompt, appending camera controls for prompt-based models (e.g., Sora, MiniMax)
                var prompt = appState.prompt
                let info = CameraControlInfo.infoForModel(id: model.id)
                let isPromptBasedCameraControl = info.format.contains("prompt-based") && model.supportedParams.contains(.cameraControl)
                if isPromptBasedCameraControl, let camera = appState.settings.aimlAdvancedParams.cameraControl, !camera.isEmpty {
                    // Append camera controls to prompt for models like Sora, MiniMax
                    if let cameraDict = try? JSONSerialization.jsonObject(with: camera.data(using: .utf8)!) as? [String: String] {
                        let cameraDesc = cameraDict.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                        prompt += ", camera: \(cameraDesc)"
                    }
                }
                
                var bodyDict: [String: Any] = [
                    "model": modelName,
                    "prompt": prompt,
                    "sync_mode": true,
                    "enable_safety_checker": appState.settings.aimlAdvancedParams.enableSafetyChecker ?? true
                ]
                
                // Add advanced video params if supported
                if let negative = appState.settings.aimlAdvancedParams.negativePrompt, model.supportedParams.contains(.negativePrompt) {
                    bodyDict["negative_prompt"] = negative
                }
                if let guidance = appState.settings.aimlAdvancedParams.guidanceScale, model.supportedParams.contains(.guidanceScale) {
                    bodyDict["cfg_scale"] = guidance
                }
                if let duration = appState.settings.aimlAdvancedParams.duration, model.supportedParams.contains(.duration) {
                    bodyDict["duration"] = duration
                }
                if let aspect = appState.settings.aimlAdvancedParams.aspectRatio, model.supportedParams.contains(.aspectRatio) {
                    bodyDict["aspect_ratio"] = aspect
                }
                if let frameRate = appState.settings.aimlAdvancedParams.frameRate, model.supportedParams.contains(.frameRate) {
                    bodyDict["frame_rate"] = frameRate
                }
                if let stylePreset = appState.settings.aimlAdvancedParams.stylePreset, model.supportedParams.contains(.stylePreset) {
                    bodyDict["style_preset"] = stylePreset
                }
                if let enhance = appState.settings.aimlAdvancedParams.enhancePrompt, model.supportedParams.contains(.enhancePrompt) {
                    bodyDict["enhance_prompt"] = enhance
                }
                if let camera = appState.settings.aimlAdvancedParams.cameraControl, model.supportedParams.contains(.cameraControl), !camera.isEmpty {
                    // Validate JSON
                    if let data = camera.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
                        bodyDict["camera_control"] = camera
                    } else {
                        throw GenerationError.apiError("Invalid camera_control JSON format")
                    }
                }
                
                // For image-to-video
                var imageInputs: [String] = []
                let useImgBB = appState.preferImgBBForImages && model.acceptsPublicURL
                
                for slot in appState.ui.imageSlots {
                    guard let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "jpeg", isBase64: appState.settings.imageSubmissionMethod == .base64, convertToJPG: appState.settings.base64ConvertToJPG, scale50Percent: appState.settings.base64Scale50Percent) else {
                        continue
                    }
                    if useImgBB {
                        guard !appState.settings.imgbbApiKey.isEmpty else {
                            throw GenerationError.apiError("ImgBB API key required for public image upload.")
                        }
                        if !(await showPrivacyNotice(for: .imgbb)) {
                            throw GenerationError.apiError("User declined ImgBB privacy notice.")
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
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw GenerationError.apiError("Status \(status): \(bodyString)")
                }
                print(String(data: data, encoding: .utf8) ?? "No data")
                
                let responseDecoded = try JSONDecoder().decode(AIMLVideoGenerationResponse.self, from: data)
                
                if let error = responseDecoded.error {
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
                
                guard let genId = responseDecoded.generation_id else {
                    throw GenerationError.apiError("No generation ID returned")
                }
                
                let pollUrlString = "https://api.aimlapi.com/v2/generate/video/\(provider)/generation?generation_id=\(genId)"
                guard let pollUrl = URL(string: pollUrlString) else {
                    throw GenerationError.invalidURL
                }
                
                var status = ""
                var videoUrlStr: String?
                let startTime = Date()
                while status != "completed" && Date().timeIntervalSince(startTime) < 1200 {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                    
                    var pollRequest = URLRequest(url: pollUrl)
                    pollRequest.httpMethod = "GET"
                    pollRequest.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
                    
                    let (pollData, pollResponse) = try await URLSession.shared.data(for: pollRequest)
                    guard let httpPollResponse = pollResponse as? HTTPURLResponse,
                          (200...299).contains(httpPollResponse.statusCode) else {
                        let bodyString = String(data: pollData, encoding: .utf8) ?? "No body"
                        let status = (pollResponse as? HTTPURLResponse)?.statusCode ?? -1
                        throw GenerationError.apiError("Poll status \(status): \(bodyString)")
                    }
                    
                    let pollDecoded = try JSONDecoder().decode(AIMLVideoPollResponse.self, from: pollData)
                    
                    if let error = pollDecoded.error {
                        throw GenerationError.apiError(error.message ?? "Poll error")
                    }
                    
                    status = pollDecoded.status
                    if status == "completed" {
                        videoUrlStr = pollDecoded.video?.url
                    } else if status == "failed" {
                        throw GenerationError.apiError("Video generation failed")
                    }
                }
                
                guard let videoUrlStr = videoUrlStr, let videoUrl = URL(string: videoUrlStr) else {
                    throw GenerationError.apiError("No video URL returned or timeout")
                }
                
                let (videoData, _) = try await URLSession.shared.data(from: videoUrl)
                
                let path = saveGeneratedMedia(data: videoData, prompt: appState.prompt, mode: .aimlapi, modelUsed: appState.settings.selectedAIMLModel, isVideo: true)
                
                await MainActor.run {
                    appState.ui.outputImages = [nil]
                    appState.ui.outputTexts = ["Video saved to \(path ?? "unknown")"]
                    appState.ui.outputPaths = [path]
                    appState.ui.currentOutputIndex = 0
                }
                
                let newItem = HistoryItem(prompt: appState.prompt, responseText: "Video generated", imagePath: path, date: Date(), mode: appState.settings.mode, workflowName: nil, modelUsed: appState.settings.selectedAIMLModel, batchId: nil, indexInBatch: nil, totalInBatch: nil)
                appState.historyState.history.append(.item(newItem))
                appState.historyState.saveHistory()
                
            } else {
                // Image generation logic
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
                if let watermark = appState.settings.aimlAdvancedParams.watermark, model.supportedParams.contains(.watermark) {
                    bodyDict["watermark"] = watermark
                }
                if let enhance = appState.settings.aimlAdvancedParams.enhancePrompt, model.supportedParams.contains(.enhancePrompt) {
                    bodyDict["enhance_prompt"] = enhance
                }
                
                var imageInputs: [String] = []
                let useImgBB = appState.preferImgBBForImages && model.acceptsPublicURL
                
                for slot in appState.ui.imageSlots {
                    guard let image = slot.image, let processed = processImageForUpload(image: image, originalData: slot.originalData, format: "jpeg", isBase64: appState.settings.imageSubmissionMethod == .base64, convertToJPG: appState.settings.base64ConvertToJPG, scale50Percent: appState.settings.base64Scale50Percent) else {
                        continue
                    }
                    if useImgBB {
                        guard !appState.settings.imgbbApiKey.isEmpty else {
                            throw GenerationError.apiError("ImgBB API key required for public image upload.")
                        }
                        if !(await showPrivacyNotice(for: .imgbb)) {
                            throw GenerationError.apiError("User declined ImgBB privacy notice.")
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
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw GenerationError.apiError("Status \(status): \(bodyString)")
                }
                print(String(data: data, encoding: .utf8) ?? "No data")
                let responseDecoded = try JSONDecoder().decode(GrokImageResponse.self, from: data)
                
                if let error = responseDecoded.error {
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
                
                let total = responseDecoded.data.count
                for (i, item) in responseDecoded.data.enumerated() {
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
                        let path = saveGeneratedMedia(data: data, prompt: appState.prompt, mode: .aimlapi, modelUsed: appState.settings.selectedAIMLModel, batchIndex: i, totalInBatch: total, isVideo: false)
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
    
    @MainActor
    func showPrivacyNotice(for service: PrivacyService) async -> Bool {
        let key = "dontShow\(service.rawValue.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: ""))Privacy"
        if UserDefaults.standard.bool(forKey: key) {
            return true
        }
        
        return await withCheckedContinuation { continuation in
            self.onPrivacyComplete = { consented, dontShow in
                if let complete = self.onPrivacyComplete {
                    self.onPrivacyComplete = nil
                    if dontShow {
                        UserDefaults.standard.set(true, forKey: key)
                    }
                    continuation.resume(returning: consented)
                    DispatchQueue.main.async {
                        self.privacyServiceToShow = nil
                    }
                }
            }
            self.privacyServiceToShow = service
        }
    }
    
    func saveGeneratedMedia(data: Data, prompt: String, mode: GenerationMode, modelUsed: String? = nil, batchIndex: Int? = nil, totalInBatch: Int? = nil, isVideo: Bool = false) -> String? {
        guard let dir = appState.settings.outputDirectory else { return nil }
        
        let timestamp = Date().timeIntervalSince1970
        let safePrompt = prompt.prefix(50).replacingOccurrences(of: "/", with: "-")
        var fileName = "\(safePrompt)_\(timestamp)"
        if let model = modelUsed { fileName += "_\(model.replacingOccurrences(of: "/", with: "-"))" }
        if let idx = batchIndex, let tot = totalInBatch { fileName += "_\(idx+1)of\(tot)" }
        fileName += isVideo ? ".mp4" : ".png"
        
        let fileURL = dir.appendingPathComponent(fileName)
        
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: dir, options: .forReplacing, error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                do {
                    try data.write(to: fileURL)
                } catch {
                    print("Failed to save file: \(error)")
                }
            }
        }
        if let coordError = coordError {
            print("Coordination error during save: \(coordError.localizedDescription)")
            return nil
        }
        return fileURL.path
    }
}

struct DetailedErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Error Details")
                .font(.title2)
                .bold()
            
            ScrollView {
                Text(prettyPrintJSON(message) ?? message)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 400)
            
            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func prettyPrintJSON(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension View {
    func withSecureAccess<T>(to url: URL, body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}

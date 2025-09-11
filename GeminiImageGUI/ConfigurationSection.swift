// ConfigurationSection.swift
import SwiftUI

struct ConfigurationSection: View {
    @Binding var showApiKey: Bool
    @Binding var apiKeyPath: String
    @Binding var outputPath: String
    @Binding var isTestingApi: Bool
    @Binding var errorMessage: String?
    @Binding var showErrorAlert: Bool
    let onApiKeySelected: (Result<[URL], Error>) -> Void
    let onOutputFolderSelected: (Result<[URL], Error>) -> Void
    let onComfyJSONSelected: (Result<[URL], Error>) -> Void
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $appState.settings.mode) {
                Text("Gemini").tag(GenerationMode.gemini)
                Text("ComfyUI").tag(GenerationMode.comfyUI)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            
            if appState.settings.mode == .gemini {
                geminiConfiguration
            } else {
                comfyUIConfiguration
            }
            
            HStack {
                Text("Output Folder:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                #if os(iOS)
                Text(outputPath.isEmpty ? "No folder selected" : URL(fileURLWithPath: outputPath).lastPathComponent)
                #else
                Text(outputPath.isEmpty ? "No folder selected" : outputPath)
                #endif
                Button("Browse") {
                    print("Showing output folder picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                        onOutputFolderSelected(result)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue.opacity(0.8))
                .font(.system(.body, design: .rounded, weight: .medium))
                .shadow(color: .black.opacity(0.1), radius: 1)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)  // Left-justify output folder row
        }
    }
    
    @ViewBuilder
    private var geminiConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {  // Align to left
            HStack {
                Text("API Key File:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                #if os(iOS)
                Text(apiKeyPath.isEmpty ? "No file selected" : URL(fileURLWithPath: apiKeyPath).lastPathComponent)
                #else
                Text(apiKeyPath.isEmpty ? "No file selected" : apiKeyPath)
                #endif
                Button("Browse") {
                    print("Showing api file picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                        onApiKeySelected(result)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue.opacity(0.8))
                .font(.system(.body, design: .rounded, weight: .medium))
                .shadow(color: .black.opacity(0.1), radius: 1)
            }
            
            HStack {
                Text("API Key:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                Group {
                    if showApiKey {
                        TextField("API Key", text: $appState.settings.apiKey)
                    } else {
                        SecureField("API Key", text: $appState.settings.apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .autocorrectionDisabled()
                Toggle(isOn: $showApiKey) {
                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                        .symbolRenderingMode(.hierarchical)
                }
                .toggleStyle(.button)
                .help("Toggle API Key Visibility")
                
                Button("Test API") {
                    testApiKey()
                }
                .buttonStyle(.bordered)
                .tint(.blue.opacity(0.8))
                .font(.system(.body, design: .rounded, weight: .medium))
                .shadow(color: .black.opacity(0.1), radius: 1)
                .disabled(appState.settings.apiKey.isEmpty || isTestingApi)
            }
        }
    }
    
    @ViewBuilder
    private var comfyUIConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {  // Align to left
            HStack {
                Text("Server URL:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("http://localhost:8188", text: $appState.settings.comfyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    .autocorrectionDisabled()
            }
            
            HStack {
                Text("Workflow JSON or PNG:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                #if os(iOS)
                Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : URL(fileURLWithPath: appState.settings.comfyJSONPath).lastPathComponent)
                #else
                Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : appState.settings.comfyJSONPath)
                #endif
                Button("Browse") {
                    print("Showing json file picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.json, .png], allowsMultiple: false, canChooseDirectories: false) { result in
                        onComfyJSONSelected(result)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue.opacity(0.8))
                .font(.system(.body, design: .rounded, weight: .medium))
                .shadow(color: .black.opacity(0.1), radius: 1)
            }
            
            if !appState.generation.promptNodes.isEmpty {
                HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                    Text("Prompt Node:")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.generation.comfyPromptNodeID) {
                        ForEach(appState.generation.promptNodes) { node in
                            Text(node.label).tag(node.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            if !appState.generation.imageNodes.isEmpty {
                HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                    Text("Image Node:")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.generation.comfyImageNodeID) {
                        ForEach(appState.generation.imageNodes) { node in
                            Text(node.label).tag(node.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            if !appState.generation.outputNodes.isEmpty {
                HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                    Text("Output Node:")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $appState.generation.comfyOutputNodeID) {
                        ForEach(appState.generation.outputNodes) { node in
                            Text(node.label).tag(node.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    private func testApiKey() {
        isTestingApi = true
        errorMessage = nil
        
        Task {
            defer { isTestingApi = false }
            
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent") else {
                errorMessage = "Invalid URL"
                showErrorAlert = true
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(appState.settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
            
            let requestBody = GenerateContentRequest(contents: [Content(parts: [Part(text: "Test prompt", inlineData: nil)])])
            
            do {
                request.httpBody = try JSONEncoder().encode(requestBody)
            } catch {
                errorMessage = "Failed to encode test request: \(error.localizedDescription)"
                showErrorAlert = true
                return
            }
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    errorMessage = "API test successful!"
                    showErrorAlert = true
                } else {
                    errorMessage = "API test failed. Check your key."
                    showErrorAlert = true
                }
            } catch {
                errorMessage = "Test error: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
}

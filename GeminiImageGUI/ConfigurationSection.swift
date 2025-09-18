// ConfigurationSection.swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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
    
    @State private var showSuccessAlert: Bool = false
    @State private var successMessage: String = ""
    @State private var showCopiedMessage: Bool = false
    @State private var showServerSuccessAlert: Bool = false
    @State private var showServerErrorAlert: Bool = false
    @State private var serverErrorMessage: String = ""
    @State private var isTestingServer: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $appState.settings.mode) {
                Text("Gemini").tag(GenerationMode.gemini)
                Text("ComfyUI").tag(GenerationMode.comfyUI)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            .help("Select the generation mode: Gemini or ComfyUI")
            .accessibilityLabel("Generation mode selector")
            
            if appState.settings.mode == .gemini {
                geminiConfiguration
            } else {
                comfyUIConfiguration
            }
            
            HStack {
                Text("Output Folder:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("Select the folder where generated images will be saved")
                #if os(iOS)
                Text(outputPath.isEmpty ? "No folder selected" : URL(fileURLWithPath: outputPath).lastPathComponent)
                    .help("Currently selected output folder")
                #else
                Text(outputPath.isEmpty ? "No folder selected" : outputPath)
                    .help("Currently selected output folder")
                #endif
                Button(action: {
                    print("Showing output folder picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                        onOutputFolderSelected(result)
                    }
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Browse to select an output folder")
                .accessibilityLabel("Browse output folder")
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)  // Left-align output folder row
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .alert("Server Available", isPresented: $showServerSuccessAlert) {
            Button("OK") {}
        } message: {
            Text("The ComfyUI server is reachable and responding.")
        }
        .alert("Server Error", isPresented: $showServerErrorAlert) {
            Button("OK") {}
        } message: {
            Text(serverErrorMessage)
        }
    }
    
    @ViewBuilder
    private var geminiConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {  // Align to left
            HStack {
                Text("API Key File:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("Select a file containing your API key")
                #if os(iOS)
                Text(apiKeyPath.isEmpty ? "No file selected" : URL(fileURLWithPath: apiKeyPath).lastPathComponent)
                    .help("Currently selected API key file")
                #else
                Text(apiKeyPath.isEmpty ? "No file selected" : apiKeyPath)
                    .help("Currently selected API key file")
                #endif
                Button(action: {
                    print("Showing api file picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                        onApiKeySelected(result)
                    }
                }) {
                    Image(systemName: "doc")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Browse to select an API key file")
                .accessibilityLabel("Browse API key file")
            }
            
            HStack {
                Text("API Key:")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("Enter your API key here")
                Group {
                    if showApiKey {
                        TextField("Enter or paste API key", text: $appState.settings.apiKey)
                            .help("Visible API key input")
                    } else {
                        SecureField("Enter or paste API key", text: $appState.settings.apiKey)
                            .help("Hidden API key input")
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .autocorrectionDisabled()
                .accessibilityLabel("API key input")
                
                Toggle(isOn: $showApiKey) {
                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                        .symbolRenderingMode(.hierarchical)
                }
                .toggleStyle(.button)
                .help("Toggle API Key Visibility")
                .accessibilityLabel("Toggle API key visibility")
                
                Button(action: {
                    testApiKey()
                }) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .disabled(appState.settings.apiKey.isEmpty || isTestingApi)
                .help("Test the entered API key")
                .accessibilityLabel("Test API key")
            }
        }
    }
    
    @ViewBuilder
    private var comfyUIConfiguration: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {  // Align to left
                HStack {
                    Text("Server URL:")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                        .help("Enter the URL of your ComfyUI server")
                    TextField("e.g., http://localhost:8188", text: $appState.settings.comfyServerURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                        .autocorrectionDisabled()
                        .frame(width: 250)  // Decreased length to roughly fit http:// with IP and port
                        .help("Server URL, e.g., http://localhost:8188")
                        .accessibilityLabel("ComfyUI server URL")
                    Button(action: {
                        testServer()
                    }) {
                        Image(systemName: isTestingServer ? "arrow.clockwise.circle" : "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isTestingServer || appState.settings.comfyServerURL.isEmpty)
                    .help("Check if the ComfyUI server is available")
                    .accessibilityLabel("Test server connection")
                }
                
                HStack {
                    Text("Workflow JSON or PNG:")
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundColor(.secondary)
                        .help("Select a JSON or PNG file for the workflow")
                    #if os(iOS)
                    Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : URL(fileURLWithPath: appState.settings.comfyJSONPath).lastPathComponent)
                        .help("Currently selected workflow file")
                    #else
                    Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : appState.settings.comfyJSONPath)
                        .help("Currently selected workflow file")
                    #endif
                    Button(action: {
                        print("Showing json file picker")
                        PlatformFilePicker.presentOpenPanel(allowedTypes: [.json, .png], allowsMultiple: false, canChooseDirectories: false) { result in
                            onComfyJSONSelected(result)
                        }
                    }) {
                        Image(systemName: "doc")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Browse to select a workflow JSON or PNG file")
                    .accessibilityLabel("Browse workflow file")
                }
                
                if !appState.generation.promptNodes.isEmpty {
                    HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                        Text("Prompt Node:")
                            .font(.system(.subheadline, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                            .help("Select the prompt node from the workflow")
                        Picker("", selection: $appState.generation.comfyPromptNodeID) {
                            ForEach(appState.generation.promptNodes) { node in
                                Text(node.label).tag(node.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Choose the prompt node")
                        .accessibilityLabel("Prompt node selector")
                        
                        Button(action: {
                            if let selectedNode = appState.generation.promptNodes.first(where: { $0.id == appState.generation.comfyPromptNodeID }) {
                                copyToClipboard(selectedNode.promptText ?? "")
                                withAnimation {
                                    showCopiedMessage = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showCopiedMessage = false
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .help("Copy prompt text to clipboard")
                        .accessibilityLabel("Copy prompt text")
                    }
                }
                
                if !appState.generation.imageNodes.isEmpty {
                    HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                        Text("Image Node:")
                            .font(.system(.subheadline, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                            .help("Select the image node from the workflow")
                        Picker("", selection: $appState.generation.comfyImageNodeID) {
                            ForEach(appState.generation.imageNodes) { node in
                                Text(node.label).tag(node.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Choose the image node")
                        .accessibilityLabel("Image node selector")
                    }
                }
                
                if !appState.generation.outputNodes.isEmpty {
                    HStack(alignment: .center, spacing: 8) {  // HStack for label + picker side-by-side
                        Text("Output Node:")
                            .font(.system(.subheadline, design: .default, weight: .medium))
                            .foregroundColor(.secondary)
                            .help("Select the output node from the workflow")
                        Picker("", selection: $appState.generation.comfyOutputNodeID) {
                            ForEach(appState.generation.outputNodes) { node in
                                Text(node.label).tag(node.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .help("Choose the output node")
                        .accessibilityLabel("Output node selector")
                    }
                }
            }
            
            if showCopiedMessage {
                Text("Copied to Clipboard")
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .help("Confirmation that text was copied to clipboard")
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
                    successMessage = "API test successful!"
                    showSuccessAlert = true
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
    
    private func testServer() {
        isTestingServer = true
        serverErrorMessage = ""
        
        Task {
            defer { isTestingServer = false }
            
            let baseURL = appState.settings.comfyServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/object_info") else {
                serverErrorMessage = "Invalid server URL"
                showServerErrorAlert = true
                return
            }
            
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    showServerSuccessAlert = true
                } else {
                    serverErrorMessage = "Server responded with status: \( (response as? HTTPURLResponse)?.statusCode ?? 0 )"
                    showServerErrorAlert = true
                }
            } catch {
                serverErrorMessage = "Failed to connect: \(error.localizedDescription)"
                showServerErrorAlert = true
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
}

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
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @State private var showSuccessAlert: Bool = false
    @State private var successMessage: String = ""
    @State private var showCopiedMessage: Bool = false
    @State private var showServerSuccessAlert: Bool = false
    @State private var showServerErrorAlert: Bool = false
    @State private var serverErrorMessage: String = ""
    @State private var isTestingServer: Bool = false
    @State private var showGrokApiKey: Bool = false  // Added: For Grok key visibility toggle
    
    private var isCompact: Bool {
        sizeClass == .compact
    }
    
    private var labelFont: Font {
        .system(.subheadline, design: .default, weight: .medium)
    }
    
    private var textFont: Font {
        .system(size: isCompact ? 13 : 15, weight: .medium, design: .monospaced)
    }
    
    private var pickerFont: Font {
        .system(size: isCompact ? 12 : 14)
    }
    
    init(
        showApiKey: Binding<Bool>,
        apiKeyPath: Binding<String>,
        outputPath: Binding<String>,
        isTestingApi: Binding<Bool>,
        errorMessage: Binding<String?>,
        showErrorAlert: Binding<Bool>,
        onApiKeySelected: @escaping (Result<[URL], Error>) -> Void,
        onOutputFolderSelected: @escaping (Result<[URL], Error>) -> Void,
        onComfyJSONSelected: @escaping (Result<[URL], Error>) -> Void
    ) {
        _showApiKey = showApiKey
        _apiKeyPath = apiKeyPath
        _outputPath = outputPath
        _isTestingApi = isTestingApi
        _errorMessage = errorMessage
        _showErrorAlert = showErrorAlert
        self.onApiKeySelected = onApiKeySelected
        self.onOutputFolderSelected = onOutputFolderSelected
        self.onComfyJSONSelected = onComfyJSONSelected
    }
    
    var body: some View {
        VStack(spacing: isCompact ? 12 : 16) {
            Picker("Mode", selection: $appState.settings.mode) {
                Text("Gemini").tag(GenerationMode.gemini)
                Text("ComfyUI").tag(GenerationMode.comfyUI)
                Text("Grok").tag(GenerationMode.grok)  // Added: Option for Grok
            }
            .pickerStyle(.segmented)
            .padding(.bottom, isCompact ? 4 : 8)
            .help("Select the generation mode: Gemini, ComfyUI, or Grok")
            .accessibilityLabel("Generation mode selector")
            
            switch appState.settings.mode {
            case .gemini:
                geminiConfiguration
            case .comfyUI:
                comfyUIConfiguration
            case .grok:
                grokConfiguration  // Added: New case for Grok
            }
            
            outputFolderSection
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
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }
    
    @ViewBuilder
    private var outputFolderSection: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Folder:")
                        .font(labelFont)
                        .foregroundColor(.secondary)
                        .help("Select the folder where generated images will be saved")
                    HStack(spacing: isCompact ? 8 : 16) {
                        #if os(iOS)
                        Text(outputPath.isEmpty ? "No folder selected" : URL(fileURLWithPath: outputPath).lastPathComponent)
                            .font(textFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("Currently selected output folder")
                        #else
                        Text(outputPath.isEmpty ? "No folder selected" : outputPath)
                            .font(textFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("Currently selected output folder")
                        #endif
                        Button(action: {
                            print("Showing output folder picker")
                            PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                                onOutputFolderSelected(result)
                            }
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: isCompact ? 14 : 16))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help("Browse to select an output folder")
                        .accessibilityLabel("Browse output folder")
                    }
                }
            } else {
                HStack(spacing: isCompact ? 8 : 16) {
                    Text("Output Folder:")
                        .font(labelFont)
                        .foregroundColor(.secondary)
                        .help("Select the folder where generated images will be saved")
                    #if os(iOS)
                    Text(outputPath.isEmpty ? "No folder selected" : URL(fileURLWithPath: outputPath).lastPathComponent)
                        .font(textFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("Currently selected output folder")
                    #else
                    Text(outputPath.isEmpty ? "No folder selected" : outputPath)
                        .font(textFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("Currently selected output folder")
                    #endif
                    Button(action: {
                        print("Showing output folder picker")
                        PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                            onOutputFolderSelected(result)
                        }
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: isCompact ? 14 : 16))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Browse to select an output folder")
                    .accessibilityLabel("Browse output folder")
                }
            }
        }
        .padding(.top, isCompact ? 4 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)  // Left-align output folder row
    }
    
    @ViewBuilder
    private var geminiConfiguration: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {  // Align to left
            geminiApiKeyRow
        }
    }
    
    @ViewBuilder
    private var geminiApiKeyRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("API Key:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Enter your API key here")
            Group {
                if showApiKey {
                    TextField("Enter or paste API key", text: $appState.settings.apiKey)
                        .onChange(of: appState.settings.apiKey) { newValue in
                            handleAPIKeyChange(newValue)
                        }
                        .help("Visible API key input")
                } else {
                    SecureField("Enter or paste API key", text: $appState.settings.apiKey)
                        .onChange(of: appState.settings.apiKey) { newValue in
                            handleAPIKeyChange(newValue)
                        }
                        .help("Hidden API key input")
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(textFont)
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
                pasteToApiKey()
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Paste API key from clipboard")
            .accessibilityLabel("Paste API key")
            
            Button(action: {
                testApiKey()
            }) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(appState.settings.apiKey.isEmpty || isTestingApi)
            .help("Test the entered API key")
            .accessibilityLabel("Test API key")
        }
    }
    
    // Added: Grok configuration (similar to Gemini)
    @ViewBuilder
    private var grokConfiguration: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {  // Align to left
            grokApiKeyRow
            grokModelRow
        }
    }
    
    @ViewBuilder
    private var grokApiKeyRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Grok API Key:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Enter your Grok API key here")
            Group {
                if showGrokApiKey {
                    TextField("Enter or paste Grok API key", text: $appState.settings.grokApiKey)
                        .onChange(of: appState.settings.grokApiKey) { newValue in
                            handleGrokAPIKeyChange(newValue)
                        }
                        .help("Visible Grok API key input")
                } else {
                    SecureField("Enter or paste Grok API key", text: $appState.settings.grokApiKey)
                        .onChange(of: appState.settings.grokApiKey) { newValue in
                            handleGrokAPIKeyChange(newValue)
                        }
                        .help("Hidden Grok API key input")
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(textFont)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
            .autocorrectionDisabled()
            .accessibilityLabel("Grok API key input")
            
            Toggle(isOn: $showGrokApiKey) {
                Image(systemName: showGrokApiKey ? "eye.slash" : "eye")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help("Toggle Grok API Key Visibility")
            .accessibilityLabel("Toggle Grok API key visibility")
            
            Button(action: {
                pasteToGrokApiKey()
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Paste Grok API key from clipboard")
            .accessibilityLabel("Paste Grok API key")
            
            Button(action: {
                testGrokApiKey()
            }) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(appState.settings.grokApiKey.isEmpty || isTestingApi)
            .help("Test the entered Grok API key")
            .accessibilityLabel("Test Grok API key")
        }
    }
    
    @ViewBuilder
    private var grokModelRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Model:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select the Grok model")
            Picker("", selection: $appState.settings.selectedGrokModel) {
                Text("grok-2-image-1212").tag("grok-2-image-1212")
            }
            .pickerStyle(.menu)
            .help("Choose the Grok model for generation")
            .accessibilityLabel("Grok model selector")
        }
    }
    
    @ViewBuilder
    private var comfyUIConfiguration: some View {
        ZStack {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {  // Align to left
                comfyServerURLRow
                comfyWorkflowRow
                if !appState.generation.promptNodes.isEmpty {
                    comfyPromptNodeRow
                }
                if !appState.generation.imageNodes.isEmpty {
                    comfyImageNodeRow
                }
                if !appState.generation.outputNodes.isEmpty {
                    comfyOutputNodeRow
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
    
    @ViewBuilder
    private var comfyServerURLRow: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Enter the URL of your ComfyUI server")
                TextField("e.g., http://localhost:8188", text: $appState.settings.comfyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(textFont)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity)
                    .help("Server URL, e.g., http://localhost:8188")
                    .accessibilityLabel("ComfyUI server URL")
            }
            HStack {
                Spacer()
                Button(action: {
                    testServer()
                }) {
                    Image(systemName: isTestingServer ? "arrow.clockwise.circle" : "checkmark.circle")
                        .font(.system(size: isCompact ? 14 : 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .disabled(isTestingServer || appState.settings.comfyServerURL.isEmpty)
                .help("Check if the ComfyUI server is available")
                .accessibilityLabel("Test server connection")
            }
        } else {
            HStack(spacing: isCompact ? 8 : 16) {
                Text("Server URL:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Enter the URL of your ComfyUI server")
                TextField("e.g., http://localhost:8188", text: $appState.settings.comfyServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(textFont)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    .autocorrectionDisabled()
                    .frame(width: isCompact ? 200 : 250)  // Decreased length to roughly fit http:// with IP and port
                    .help("Server URL, e.g., http://localhost:8188")
                    .accessibilityLabel("ComfyUI server URL")
                Button(action: {
                    testServer()
                }) {
                    Image(systemName: isTestingServer ? "arrow.clockwise.circle" : "checkmark.circle")
                        .font(.system(size: isCompact ? 14 : 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .disabled(isTestingServer || appState.settings.comfyServerURL.isEmpty)
                .help("Check if the ComfyUI server is available")
                .accessibilityLabel("Test server connection")
            }
        }
    }
    
    @ViewBuilder
    private var comfyWorkflowRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Workflow JSON or PNG:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select a JSON or PNG file for the workflow")
            #if os(iOS)
            Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : URL(fileURLWithPath: appState.settings.comfyJSONPath).lastPathComponent)
                .font(textFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Currently selected workflow file")
            #else
            Text(appState.settings.comfyJSONPath.isEmpty ? "No file selected" : appState.settings.comfyJSONPath)
                .font(textFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Currently selected workflow file")
            #endif
            Button(action: {
                print("Showing json file picker")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.json, .png], allowsMultiple: false, canChooseDirectories: false) { result in
                    onComfyJSONSelected(result)
                }
            }) {
                Image(systemName: "doc")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Browse to select a workflow JSON or PNG file")
            .accessibilityLabel("Browse workflow file")
        }
    }
    
    @ViewBuilder
    private var comfyPromptNodeRow: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the prompt node from the workflow")
                HStack(spacing: isCompact ? 4 : 8) {
                    Picker("", selection: $appState.generation.comfyPromptNodeID) {
                        ForEach(appState.generation.promptNodes) { node in
                            Text(node.label)
                                .font(pickerFont)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .tag(node.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
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
        } else {
            HStack(alignment: .center, spacing: isCompact ? 4 : 8) {  // HStack for label + picker side-by-side
                Text("Prompt Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the prompt node from the workflow")
                Picker("", selection: $appState.generation.comfyPromptNodeID) {
                    ForEach(appState.generation.promptNodes) { node in
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(node.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: isCompact ? 150 : .infinity)
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
    }
    
    @ViewBuilder
    private var comfyImageNodeRow: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 4) {
                Text("Image Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the image node from the workflow")
                Picker("", selection: $appState.generation.comfyImageNodeID) {
                    ForEach(appState.generation.imageNodes) { node in
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(node.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .help("Choose the image node")
                .accessibilityLabel("Image node selector")
            }
        } else {
            HStack(alignment: .center, spacing: isCompact ? 4 : 8) {  // HStack for label + picker side-by-side
                Text("Image Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the image node from the workflow")
                Picker("", selection: $appState.generation.comfyImageNodeID) {
                    ForEach(appState.generation.imageNodes) { node in
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(node.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: isCompact ? 150 : .infinity)
                .help("Choose the image node")
                .accessibilityLabel("Image node selector")
            }
        }
    }
    
    @ViewBuilder
    private var comfyOutputNodeRow: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 4) {
                Text("Output Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the output node from the workflow")
                Picker("", selection: $appState.generation.comfyOutputNodeID) {
                    ForEach(appState.generation.outputNodes) { node in
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(node.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .help("Choose the output node")
                .accessibilityLabel("Output node selector")
            }
        } else {
            HStack(alignment: .center, spacing: isCompact ? 4 : 8) {  // HStack for label + picker side-by-side
                Text("Output Node:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select the output node from the workflow")
                Picker("", selection: $appState.generation.comfyOutputNodeID) {
                    ForEach(appState.generation.outputNodes) { node in
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(node.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: isCompact ? 150 : .infinity)
                .help("Choose the output node")
                .accessibilityLabel("Output node selector")
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
    
    private func testGrokApiKey() {
        isTestingApi = true
        errorMessage = nil
        
        Task {
            defer { isTestingApi = false }
            
            guard let url = URL(string: "https://api.x.ai/v1/models") else {
                errorMessage = "Invalid URL"
                showErrorAlert = true
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(appState.settings.grokApiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    successMessage = "Grok API test successful!"
                    showSuccessAlert = true
                } else {
                    errorMessage = "Grok API test failed. Check your key."
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
    
    private func handleAPIKeyChange(_ newValue: String) {
        if newValue.isEmpty {
            KeychainHelper.deleteAPIKey()
        } else if KeychainHelper.saveAPIKey(newValue) {
            // Optional: Add a saved message if desired
        } else {
            errorMessage = "Failed to securely store API key."
            showErrorAlert = true
        }
    }
    
    private func handleGrokAPIKeyChange(_ newValue: String) {
        if newValue.isEmpty {
            KeychainHelper.deleteGrokAPIKey()
        } else if KeychainHelper.saveGrokAPIKey(newValue) {
            // Optional: Add a saved message if desired
        } else {
            errorMessage = "Failed to securely store Grok API key."
            showErrorAlert = true
        }
    }
    
    private func pasteToApiKey() {
        var pastedText: String? = nil
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pastedText = pasteboard.string(forType: .string)
        #elseif os(iOS)
        pastedText = UIPasteboard.general.string
        #endif
        
        if let text = pastedText {
            appState.settings.apiKey = text
        }
    }
    
    private func pasteToGrokApiKey() {
        var pastedText: String? = nil
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pastedText = pasteboard.string(forType: .string)
        #elseif os(iOS)
        pastedText = UIPasteboard.general.string
        #endif
        
        if let text = pastedText {
            appState.settings.grokApiKey = text
        }
    }
}

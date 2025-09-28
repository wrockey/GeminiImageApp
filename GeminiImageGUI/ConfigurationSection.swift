import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// New struct for response parsing (add at top or in separate file)
struct AIMLModelsResponse: Codable {
    let object: String
    let data: [AIMLModelEntry]
}

struct AIMLModelEntry: Codable {
    let id: String
    // Add other fields if needed: type, info, features
}

struct ConfigurationSection: View {
    @Binding var showApiKey: Bool
    @Binding var apiKeyPath: String
    @Binding var outputPath: String
    @Binding var isTestingApi: Bool
    @Binding var errorItem: AlertError?
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
    @State private var showGrokApiKey: Bool = false
    @State private var showAIMLApiKey: Bool = false
    @State private var showImgBBApiKey: Bool = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var showAdvanced: Bool = false
    @State private var showHelp: Bool = false
    
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
        errorItem: Binding<AlertError?>,
        onApiKeySelected: @escaping (Result<[URL], Error>) -> Void,
        onOutputFolderSelected: @escaping (Result<[URL], Error>) -> Void,
        onComfyJSONSelected: @escaping (Result<[URL], Error>) -> Void
    ) {
        _showApiKey = showApiKey
        _apiKeyPath = apiKeyPath
        _outputPath = outputPath
        _isTestingApi = isTestingApi
        self._errorItem = errorItem
        self.onApiKeySelected = onApiKeySelected
        self.onOutputFolderSelected = onOutputFolderSelected
        self.onComfyJSONSelected = onComfyJSONSelected
    }
    
    private var mainContent: some View {
        VStack(spacing: isCompact ? 12 : 16) {
            Picker("Mode", selection: $appState.settings.mode) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, isCompact ? 4 : 8)
            .help("Select the generation mode")
            .accessibilityLabel("Generation mode selector")
            
            switch appState.settings.mode {
            case .gemini:
                geminiConfiguration
            case .comfyUI:
                comfyUIConfiguration
            case .grok:
                grokConfiguration
            case .aimlapi:
                aimlConfiguration
            }
            
            outputFolderSection
        }
    }
    
    var body: some View {
        mainContent
            .onChange(of: appState.settings.mode) { newMode in
                if newMode == .aimlapi && !appState.settings.aimlapiKey.isEmpty {
                    fetchAvailableModels()
                }
            }
            .onChange(of: appState.settings.selectedAIMLModel) { _ in
                if !appState.canAddImages {
                    appState.ui.imageSlots.removeAll()
                }
                // Reset advanced params to defaults
                appState.settings.aimlAdvancedParams = ModelParameters()
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
            .errorAlert(errorItem: $errorItem)
            .sheet(isPresented: $showAdvanced) {
                if let model = appState.currentAIMLModel {
                    AdvancedAIMLSettingsView(model: model, params: $appState.settings.aimlAdvancedParams)
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpView(mode: appState.settings.mode)
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
                .fixedSize() // Prevents label wrapping
            Picker("", selection: $appState.settings.selectedGrokModel) {
                Text("grok-2-image-1212")
                    .font(textFont)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .tag("grok-2-image-1212")
            }
            .pickerStyle(.menu)
            .frame(width: 200) // Maintains wider picker
            .help("Choose the Grok model for generation")
            .accessibilityLabel("Grok model selector")
        }
    }
    
    @ViewBuilder
    private var aimlConfiguration: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
            aimlApiKeyRow
            aimlImgBBApiKeyRow
            aimlModelRow
            if appState.currentAIMLModel?.supportsCustomResolution ?? false {
                aimlResolutionRow
            } else {
                aimlImageSizeRow
            }
            Button("Advanced Settings") {
                showAdvanced = true
            }
            .disabled(appState.currentAIMLModel == nil)
            .help("Configure model-specific parameters")
            
            if appState.preferImgBBForImages {
                Text("Using ImgBB for image uploads (public URLs).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let model = appState.currentAIMLModel, model.isI2I {
                Text("Using base64 for images; add ImgBB key for public URLs (recommended for large images).")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    @ViewBuilder
    private var aimlApiKeyRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("AI/ML API Key:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Enter your aimlapi.com API key")
            Group {
                if showAIMLApiKey {
                    TextField("Enter or paste AI/ML API key", text: $appState.settings.aimlapiKey)
                        .onChange(of: appState.settings.aimlapiKey) { newValue in
                            handleAIMLAPIKeyChange(newValue)
                            if !newValue.isEmpty {
                                fetchAvailableModels()
                            }
                        }
                        .help("Visible AI/ML API key input")
                } else {
                    SecureField("Enter or paste AI/ML API key", text: $appState.settings.aimlapiKey)
                        .onChange(of: appState.settings.aimlapiKey) { newValue in
                            handleAIMLAPIKeyChange(newValue)
                            if !newValue.isEmpty {
                                fetchAvailableModels()
                            }
                        }
                        .help("Hidden AI/ML API key input")
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(textFont)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
            .autocorrectionDisabled()
            .accessibilityLabel("AI/ML API key input")
            
            Toggle(isOn: $showAIMLApiKey) {
                Image(systemName: showAIMLApiKey ? "eye.slash" : "eye")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help("Toggle AI/ML API Key Visibility")
            .accessibilityLabel("Toggle AI/ML API key visibility")
            
            Button(action: {
                pasteToAIMLApiKey()
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Paste AI/ML API key from clipboard")
            .accessibilityLabel("Paste AI/ML API key")
            
            Button(action: {
                testAIMLApiKey()
            }) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(appState.settings.aimlapiKey.isEmpty || isTestingApi)
            .help("Test the entered AI/ML API key")
            .accessibilityLabel("Test AI/ML API key")
            
            Button(action: {
                fetchAvailableModels()
            }) {
                Text(isFetchingModels ? "Fetching..." : "Fetch Models")
                    .font(.system(size: isCompact ? 12 : 14))
            }
            .buttonStyle(.bordered)
            .disabled(appState.settings.aimlapiKey.isEmpty || isFetchingModels)
            .help("Fetch available image models from AI/ML API")
        }
    }
    
    @ViewBuilder
    private var aimlImgBBApiKeyRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("ImgBB API Key:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Enter your ImgBB API key for image uploads (required for some models, enables public URLs for all i2i)")
            Group {
                if showImgBBApiKey {
                    TextField("Enter or paste ImgBB API key", text: $appState.settings.imgbbApiKey)
                        .onChange(of: appState.settings.imgbbApiKey) { newValue in
                            handleImgBBAPIKeyChange(newValue)
                        }
                        .help("Visible ImgBB API key input")
                } else {
                    SecureField("Enter or paste ImgBB API key", text: $appState.settings.imgbbApiKey)
                        .onChange(of: appState.settings.imgbbApiKey) { newValue in
                            handleImgBBAPIKeyChange(newValue)
                        }
                        .help("Hidden ImgBB API key input")
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(textFont)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
            .autocorrectionDisabled()
            .accessibilityLabel("ImgBB API key input")
            
            Toggle(isOn: $showImgBBApiKey) {
                Image(systemName: showImgBBApiKey ? "eye.slash" : "eye")
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.button)
            .help("Toggle ImgBB API Key Visibility")
            .accessibilityLabel("Toggle ImgBB API key visibility")
            
            Button(action: {
                pasteToImgBBApiKey()
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("Paste ImgBB API key from clipboard")
            .accessibilityLabel("Paste ImgBB API key")
        }
    }
    
    @ViewBuilder
    private var aimlModelRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Model:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select an AI/ML image model")
                .fixedSize()
            if availableModels.isEmpty {
                Text("No models fetched")
                    .foregroundColor(.gray)
            } else {
                Picker("", selection: $appState.settings.selectedAIMLModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model)
                            .font(textFont)
                            .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 300)  // Wider for long IDs
                .help("Available t2i/i2i models from AI/ML API")
                .accessibilityLabel("AI/ML model selector")
            }
        }
    }
    
    @ViewBuilder
    private var aimlImageSizeRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Image Size:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select the output image aspect ratio")
                .fixedSize()
            Picker("", selection: $appState.settings.selectedImageSize) {
                Text("Square HD").tag("square_hd")
                Text("Square").tag("square")
                Text("Portrait 4:3").tag("portrait_4_3")
                Text("Portrait 16:9").tag("portrait_16_9")
                Text("Landscape 4:3").tag("landscape_4_3")
                Text("Landscape 16:9").tag("landscape_16_9")
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .help("Choose the size; model-dependent")
            .accessibilityLabel("Image size selector")
        }
    }
    
    @ViewBuilder
    private var aimlResolutionRow: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            Text("Resolution:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select a common resolution (multiples of 32)")
                .fixedSize()
            Picker("", selection: $appState.settings.selectedResolutionString) {
                Text("512 x 512").tag("512x512")
                Text("1024 x 1024").tag("1024x1024")
                Text("2048 x 2048").tag("2048x2048")
                Text("1024 x 768 (Landscape 4:3)").tag("1024x768")
                Text("768 x 1024 (Portrait 4:3)").tag("768x1024")
                Text("1024 x 576 (Landscape 16:9)").tag("1024x576")
                Text("576 x 1024 (Portrait 16:9)").tag("576x1024")
                Text("1536 x 864 (Landscape 16:9 HD)").tag("1536x864")
                Text("1920 x 1088 (Full HD Landscape 16:9)").tag("1920x1088")
                Text("1088 x 1920 (Full HD Portrait 16:9)").tag("1088x1920")
                Text("3840 x 2176 (4K UHD Landscape 16:9)").tag("3840x2176")
                Text("2176 x 3840 (4K UHD Portrait 16:9)").tag("2176x3840")
                Text("4096 x 4096 (4K Square)").tag("4096x4096")
            }
            .pickerStyle(.menu)
            .frame(width: 300)  // Increased width to accommodate longer labels
            .help("Choose resolution; model-dependent, multiples of 32")
            .accessibilityLabel("Resolution selector")
            .onChange(of: appState.settings.selectedResolutionString) { newValue in
                let parts = newValue.split(separator: "x")
                let trimmedParts = parts.map { $0.trimmingCharacters(in: .whitespaces) }
                if trimmedParts.count == 2,
                   let width = Int(trimmedParts[0]),
                   let height = Int(trimmedParts[1]) {
                    appState.settings.selectedImageWidth = width
                    appState.settings.selectedImageHeight = height
                }
            }
            .onAppear {
                if appState.settings.selectedResolutionString.isEmpty {
                    appState.settings.selectedResolutionString = "2048x2048"
                }
            }
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
        errorItem = nil
        
        Task {
            defer { isTestingApi = false }
            
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image-preview:generateContent") else {
                errorItem = AlertError(message: "Invalid URL")
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
                errorItem = AlertError(message: "Failed to encode test request: \(error.localizedDescription)")
                return
            }
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    successMessage = "API test successful!"
                    showSuccessAlert = true
                } else {
                    errorItem = AlertError(message: "API test failed. Check your key.")
                }
            } catch {
                errorItem = AlertError(message: "Test error: \(error.localizedDescription)")
            }
        }
    }
    
    private func testGrokApiKey() {
        isTestingApi = true
        errorItem = nil
        
        Task {
            defer { isTestingApi = false }
            
            guard let url = URL(string: "https://api.x.ai/v1/models") else {
                errorItem = AlertError(message: "Invalid URL")
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
                    errorItem = AlertError(message: "Grok API test failed. Check your key.")
                }
            } catch {
                errorItem = AlertError(message: "Test error: \(error.localizedDescription)")
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
            errorItem = AlertError(message: "Failed to securely store API key.")
        }
    }
    
    private func handleGrokAPIKeyChange(_ newValue: String) {
        if newValue.isEmpty {
            KeychainHelper.deleteGrokAPIKey()
        } else if KeychainHelper.saveGrokAPIKey(newValue) {
            // Optional: Add a saved message if desired
        } else {
            errorItem = AlertError(message: "Failed to securely store Grok API key.")
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
    
    private func handleAIMLAPIKeyChange(_ newValue: String) {
        if newValue.isEmpty {
            KeychainHelper.deleteAIMLAPIKey()
        } else if KeychainHelper.saveAIMLAPIKey(newValue) {
            // Optional: Add saved message
        } else {
            errorItem = AlertError(message: "Failed to securely store AI/ML API key.")
        }
    }
    
    private func pasteToAIMLApiKey() {
        var pastedText: String? = nil
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pastedText = pasteboard.string(forType: .string)
#elseif os(iOS)
        pastedText = UIPasteboard.general.string
#endif
        
        if let text = pastedText {
            appState.settings.aimlapiKey = text
        }
    }
    
    private func testAIMLApiKey() {
        isTestingApi = true
        errorItem = nil
        
        Task {
            defer { isTestingApi = false }
            
            let baseURL = "https://api.aimlapi.com/v1/models"
            guard let url = URL(string: "\(baseURL)/models") else {  // Test endpoint (lists models)
                errorItem = AlertError(message: "Invalid URL")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    successMessage = "AI/ML API test successful!"
                    showSuccessAlert = true
                } else {
                    errorItem = AlertError(message: "AI/ML API test failed. Check your key.")
                }
            } catch {
                errorItem = AlertError(message: "Test error: \(error.localizedDescription)")
            }
        }
    }
    
    // New: Handle ImgBB API key change
    private func handleImgBBAPIKeyChange(_ newValue: String) {
        if newValue.isEmpty {
            KeychainHelper.deleteImgBBAPIKey()
        } else if KeychainHelper.saveImgBBAPIKey(newValue) {
            // Optional: Add saved message
        } else {
            errorItem = AlertError(message: "Failed to securely store ImgBB API key.")
        }
    }
    
    // New: Paste to ImgBB API key
    private func pasteToImgBBApiKey() {
        var pastedText: String? = nil
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pastedText = pasteboard.string(forType: .string)
#elseif os(iOS)
        pastedText = UIPasteboard.general.string
#endif
        
        if let text = pastedText {
            appState.settings.imgbbApiKey = text
        }
    }
    private func fetchAvailableModels() {
        // Existing... but filter with ModelRegistry if needed
        guard !appState.settings.aimlapiKey.isEmpty else {
            errorItem = AlertError(message: "Enter API key first")
            return
        }
        
        isFetchingModels = true
        errorItem = nil
        
        Task {
            defer { isFetchingModels = false }
            
            guard let url = URL(string: "https://api.aimlapi.com/models") else {
                errorItem = AlertError(message: "Invalid URL")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(AIMLModelsResponse.self, from: data)
                
                // Filter for image models (adjust keywords)
                let imageModels = response.data.filter { entry in
                    let lowerID = entry.id.lowercased()
                    return !lowerID.contains("video") && (
                        lowerID.contains("image") || lowerID.contains("t2i") || lowerID.contains("i2i") ||
                        lowerID.contains("diffusion") || lowerID.contains("seedream") || lowerID.contains("flux") ||
                        lowerID.contains("edit") || lowerID.contains("generation") || lowerID.contains("dall")
                    )
                }.map { $0.id }.sorted()
                
                await MainActor.run {
                    availableModels = imageModels
                    if !imageModels.isEmpty && appState.settings.selectedAIMLModel.isEmpty {
                        appState.settings.selectedAIMLModel = imageModels.first!
                    }
                    if imageModels.isEmpty {
                        errorItem = AlertError(message: "No image models found")
                    }
                }
            } catch {
                await MainActor.run {
                    errorItem = AlertError(message: "Fetch error: \(error.localizedDescription)")
                }
            }
        }
    }
}

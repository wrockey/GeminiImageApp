import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
 
let openGeneralSettingsNotification = Notification.Name("OpenGeneralSettings")
 
struct IdentifiableData: Identifiable, Codable, Hashable {
    var id: UUID
    let data: Data
 
    enum CodingKeys: String, CodingKey {
        case id
        case data
    }
 
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
    }
 
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        data = try container.decode(Data.self, forKey: .data)
    }
 
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(data)
    }
 
    static func == (lhs: IdentifiableData, rhs: IdentifiableData) -> Bool {
        return lhs.id == rhs.id && lhs.data == rhs.data
    }
 
    init(data: Data) {
        self.id = UUID()
        self.data = data
    }
}
 
enum PresentedModal: Identifiable {
    case history
    case responseSheet
    case fullHistoryItem(UUID)
    case markupSlot(UUID)
    case textEditor(IdentifiableData)
    case advancedSettings
 
    var id: String {
        switch self {
        case .history: return "history"
        case .responseSheet: return "responseSheet"
        case .fullHistoryItem(let uuid): return "fullHistoryItem_\(uuid.uuidString)"
        case .markupSlot(let uuid): return "markupSlot_\(uuid.uuidString)"
        case .textEditor(let data): return "textEditor_\(data.id.uuidString)"
        case .advancedSettings: return "advancedSettings"
        }
    }
}
 
enum GenerationError: LocalizedError {
    case invalidURL
    case encodingFailed(String)
    case apiError(String)
    case noWorkflow
    case invalidServerURL
    case invalidWebSocketURL
    case invalidPromptNode
    case noOutputImage
    case decodeFailed
    case fetchFailed(String)
    case invalidViewURL
    case invalidImageNode
    case noSamplerNode
    case uploadFailed(String)
    case queueFailed(String)
 
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL. Please check your configuration and ensure the endpoint is correct."
        case .encodingFailed(let details):
            return "Failed to encode request data: \(details). Verify your input (e.g., prompt or images) and try again."
        case .apiError(let message):
            return "API request failed: \(message). Check your API key, network connection, or quota limits."
        case .noWorkflow:
            return "No ComfyUI workflow loaded. Please select a valid JSON or PNG workflow file in the configuration section."
        case .invalidServerURL:
            return "Invalid ComfyUI server URL. Ensure it starts with http:// or https:// and points to your running server (e.g., http://localhost:8188)."
        case .invalidWebSocketURL:
            return "Invalid WebSocket URL for progress updates. Verify your server URL and ensure the ComfyUI server is accessible."
        case .invalidPromptNode:
            return "Invalid prompt node in workflow. Select a different prompt node or reload the workflow."
        case .noOutputImage:
            return "No output image generated. Verify your workflow has a valid output node (e.g., SaveImage) and try again."
        case .decodeFailed:
            return "Failed to decode generated image. The output may be corrupted—check your workflow or server logs."
        case .fetchFailed(let details):
            return "Failed to fetch image from server: \(details). Ensure the server is responsive and the output node is configured correctly."
        case .invalidViewURL:
            return "Invalid URL for viewing generated image. Check your server configuration."
        case .invalidImageNode:
            return "Invalid image input node in workflow. Select a different image node or ensure your workflow supports image inputs."
        case .noSamplerNode:
            return "No sampler node (e.g., KSampler) found in workflow. Please use a workflow that includes a sampler for generation."
        case .uploadFailed(let message):
            return "Image upload failed: \(message)"
        case .queueFailed(let message):
            return "Prompt queue failed: \(message)"
        }
    }
}
 
extension View {
    func workflowErrorAlert(appState: AppState) -> some View {
        alert("Workflow Error", isPresented: Binding<Bool>(
            get: { appState.generation.workflowError != nil },
            set: { _ in appState.generation.workflowError = nil }
        )) {
            Button("OK") {}
        } message: {
            Text(appState.generation.workflowError ?? "Unknown error")
        }
        .accessibilityLabel("Workflow Error Alert")
    }
 
 
    func successAlert(showSuccessAlert: Binding<Bool>, successMessage: String) -> some View {
        alert("Success", isPresented: showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .accessibilityLabel("Success Alert")
    }
 
    func onboardingSheet(showOnboarding: Binding<Bool>) -> some View {
        sheet(isPresented: showOnboarding) {
            OnboardingView()
        }
        .accessibilityLabel("Onboarding Sheet")
    }
 
    func helpSheet(showHelp: Binding<Bool>, mode: GenerationMode) -> some View {
        sheet(isPresented: showHelp) {
            HelpView(mode: mode)
        }
        .accessibilityLabel("Help Sheet")
    }
 
    func selectFolderAlert(isPresented: Binding<Bool>, selectHandler: @escaping () -> Void) -> some View {
        alert("Select Output Folder", isPresented: isPresented) {
            Button("Select Folder") {
                selectHandler()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please select an output folder before submitting the prompt.")
        }
        .accessibilityLabel("Select Output Folder Alert")
    }
}
 
struct AlertError: Identifiable {
    let id = UUID()
    let message: String
    let fullMessage: String?
}
 
struct DetailedError: Identifiable {
    let id = UUID()
    let message: String
}
 
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State var isLoading: Bool = false
    @State var progress: Double = 0.0
    @State var webSocketTask: URLSessionWebSocketTask? = nil
    @State var isCancelled: Bool = false
    @State var errorItem: AlertError? = nil
    @State var showApiKey: Bool = false
    @State var apiKeyPath: String = ""
    @State var outputPath: String = ""
    @State var showOnboarding: Bool = false
    @State var imageScale: CGFloat = 1.0
    @State var isTestingApi: Bool = false
    @State var showAnnotationSheet: Bool = false
    @State var selectedSlotId: UUID?
    @State var batchFilePath: String = ""
    @State var batchStartIndex: Int = 1
    @State var batchEndIndex: Int = 1
    @State var successMessage: String = ""
    @State var showSuccessAlert: Bool = false
    @State var showHelp: Bool = false
    @State var showSelectFolderAlert: Bool = false
    @State var pendingAction: (() -> Void)? = nil
    @State var generationTask: Task<Void, Error>? = nil
    @State var promptTextView: (any PlatformTextView)? = nil
    @State private var showGeneralOptions = false
    @State private var detailedError: DetailedError? = nil
 
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @AppStorage("configExpanded") private var configExpanded: Bool = true
    @AppStorage("promptExpanded") private var promptExpanded: Bool = true
    @AppStorage("inputImagesExpanded") private var inputImagesExpanded: Bool = true
    @AppStorage("responseExpanded") private var responseExpanded: Bool = true
    @State private var showTextEditorBookmark: IdentifiableData? = nil
 
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #else
    @State private var showHistory: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #endif
 
    private var topColor: Color {
        colorScheme == .light ? Color(white: 0.98) : Color(white: 0.1)
    }
 
    private var bottomColor: Color {
        colorScheme == .light ? Color(white: 0.95) : Color(white: 0.15)
    }
 
    #if os(iOS)
    @ViewBuilder
    private var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MainFormView(
                        configExpanded: $configExpanded,
                        promptExpanded: $promptExpanded,
                        inputImagesExpanded: $inputImagesExpanded,
                        responseExpanded: $responseExpanded,
                        prompt: $appState.prompt,
                        showApiKey: $showApiKey,
                        apiKeyPath: $apiKeyPath,
                        outputPath: $outputPath,
                        isTestingApi: $isTestingApi,
                        errorItem: $errorItem,
                        imageScale: $imageScale,
                        promptTextView: $promptTextView,
                        isLoading: isLoading,
                        progress: progress,
                        isCancelled: $isCancelled,
                        onSubmit: submitPrompt,
                        onStop: stopGeneration,
                        onPopOut: {
                            appState.presentedModal = .responseSheet
                        },
                        onAnnotate: { slotId in
                            appState.presentedModal = .markupSlot(slotId)
                        },
                        onApiKeySelected: handleApiKeySelection,
                        onOutputFolderSelected: handleOutputFolderSelection,
                        onComfyJSONSelected: handleComfyJSONSelection,
                        onBatchFileSelected: handleBatchFileSelection,
                        onBatchSubmit: batchSubmit,
                        onEditBatchFile: {
                            if batchFilePath.isEmpty {
                                appState.presentedModal = .textEditor(IdentifiableData(data: Data()))
                            } else if let bookmarkData = UserDefaults.standard.data(forKey: "batchFileBookmark") {
                                do {
                                    var isStale = false
                                    let options: URL.BookmarkResolutionOptions = []
                                    let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
                                    if resolvedURL.startAccessingSecurityScopedResource() {
                                        defer { resolvedURL.stopAccessingSecurityScopedResource() }
                                        if FileManager.default.fileExists(atPath: resolvedURL.path) {
                                            appState.presentedModal = .textEditor(IdentifiableData(data: bookmarkData))
                                        } else {
                                            clearBatchFile()
                                            appState.presentedModal = .textEditor(IdentifiableData(data: Data()))
                                        }
                                    } else {
                                        clearBatchFile()
                                        appState.presentedModal = .textEditor(IdentifiableData(data: Data()))
                                    }
                                } catch {
                                    clearBatchFile()
                                    appState.presentedModal = .textEditor(IdentifiableData(data: Data()))
                                }
                            } else {
                                errorItem = AlertError(message: "Failed to access batch file. Please check your file permissions or select a new file.", fullMessage: nil)
                            }
                        },
                        batchFilePath: $batchFilePath,
                        batchStartIndex: $batchStartIndex,
                        batchEndIndex: $batchEndIndex
                    )
                    .environmentObject(appState)
                    .padding(.horizontal, 20)
                }
            }
            .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
            .navigationTitle("")
            .toolbar {
                toolbar
            }
            .fullScreenCover(item: $appState.presentedModal) { modal in
                switch modal {
                case .history:
                    HistoryView(imageSlots: $appState.ui.imageSlots, columnVisibility: $columnVisibility)
                        .environmentObject(appState)
                case .responseSheet:
                    PopOutView()
                        .environmentObject(appState)
                case .fullHistoryItem(let id):
                    FullHistoryItemView(initialId: id)
                        .environmentObject(appState)
                case .markupSlot(let slotId):
                    if let index = appState.ui.imageSlots.firstIndex(where: { $0.id == slotId }),
                      let image = appState.ui.imageSlots[index].image {
                        let path = appState.ui.imageSlots[index].path
                        let fileURL = URL(fileURLWithPath: path)
                        let lastComponent = fileURL.lastPathComponent
                        let components = lastComponent.components(separatedBy: ".")
                        let baseFileName = components.count > 1 ? components.dropLast().joined(separator: ".") : (lastComponent.isEmpty ? "image" : lastComponent)
                        let fileExtension = components.count > 1 ? components.last! : "png"
                        MarkupView(image: image, baseFileName: baseFileName, fileExtension: fileExtension) { updatedImage in
                            appState.ui.imageSlots[index].image = updatedImage
                        }
                        .navigationTitle("Annotate Image")
                    }
                case .textEditor(let identifiable):
                    TextEditorView(bookmarkData: identifiable.data, batchFilePath: $batchFilePath)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .environmentObject(appState)
                case .advancedSettings:
                    AdvancedAIMLSettingsView(model: appState.currentAIMLModel ?? AIMLModel(id: "", isI2I: false, maxInputImages: 0, supportedParams: [], supportsCustomResolution: false, defaultImageSize: "", imageInputParam: "", acceptsMultiImages: false, acceptsBase64: false, acceptsPublicURL: false, maxWidth: nil, maxHeight: nil), params: $appState.settings.aimlAdvancedParams)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
    #endif
 
    var body: some View {
        #if os(iOS)
        iOSLayout
            .workflowErrorAlert(appState: appState)
            .errorAlert(errorItem: $errorItem, detailedError: $detailedError)
            .successAlert(showSuccessAlert: $showSuccessAlert, successMessage: successMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .helpSheet(showHelp: $showHelp, mode: appState.settings.mode)
            .selectFolderAlert(isPresented: $showSelectFolderAlert) {
                print("Showing output folder picker from alert")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                    if !outputPath.isEmpty {
                        pendingAction?()
                        pendingAction = nil
                    }
                }
            }
            .sheet(item: $showTextEditorBookmark) { identifiable in
                TextEditorView(bookmarkData: identifiable.data, batchFilePath: $batchFilePath)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(appState)
            }
            .onReceive(NotificationCenter.default.publisher(for: .batchFileUpdated)) { _ in
                loadBatchPrompts()
            }
            .onAppear {
                performOnAppear()
                validateBatchFileBookmark()
            }
            .onChange(of: appState.ui.outputImages) { _ in
                imageScale = 1.0
            }
            .onReceive(NotificationCenter.default.publisher(for: openGeneralSettingsNotification)) { _ in
                showGeneralOptions = true
            }
            .sheet(isPresented: $showGeneralOptions) {
                GeneralOptionsView(isPresented: $showGeneralOptions)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(appState)
            }
            .sheet(item: $detailedError) { detail in
                DetailedErrorView(message: detail.message) {
                    detailedError = nil
                }
            }
        #else
        macOSLayout
            .workflowErrorAlert(appState: appState)
            .errorAlert(errorItem: $errorItem, detailedError: $detailedError)
            .successAlert(showSuccessAlert: $showSuccessAlert, successMessage: successMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .helpSheet(showHelp: $showHelp, mode: appState.settings.mode)
            .selectFolderAlert(isPresented: $showSelectFolderAlert) {
                print("Showing output folder picker from alert")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                    if !outputPath.isEmpty {
                        pendingAction?()
                        pendingAction = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .batchFileUpdated)) { _ in
                loadBatchPrompts()
            }
            .onAppear {
                performOnAppear()
                validateBatchFileBookmark()
            }
            .onChange(of: appState.ui.outputImages) { _ in
                imageScale = 1.0
            }
            .onChange(of: appState.generation.selectedImageNodeIDs) { _ in
                let maxSlots = appState.maxImageSlots
                if appState.ui.imageSlots.count > maxSlots {
                    appState.ui.imageSlots.removeLast(appState.ui.imageSlots.count - maxSlots)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: openGeneralSettingsNotification)) { _ in
                showGeneralOptions = true
            }
            .sheet(isPresented: $showGeneralOptions) {
                GeneralOptionsView(isPresented: $showGeneralOptions)
                    .frame(minWidth: 450, maxWidth: .infinity, minHeight: 200, idealHeight: .infinity, maxHeight: .infinity)
                    .environmentObject(appState)
            }
            .sheet(item: $detailedError) { detail in
                DetailedErrorView(message: detail.message) {
                    detailedError = nil
                }
            }
        #endif
    }
 
    #if os(macOS)
    @ViewBuilder
    private var macOSLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistoryView(imageSlots: $appState.ui.imageSlots, columnVisibility: $columnVisibility)
                .environmentObject(appState)
        } detail: {
            ScrollView {
                MainFormView(
                    configExpanded: $configExpanded,
                    promptExpanded: $promptExpanded,
                    inputImagesExpanded: $inputImagesExpanded,
                    responseExpanded: $responseExpanded,
                    prompt: $appState.prompt,
                    showApiKey: $showApiKey,
                    apiKeyPath: $apiKeyPath,
                    outputPath: $outputPath,
                    isTestingApi: $isTestingApi,
                    errorItem: $errorItem,
                    imageScale: $imageScale,
                    promptTextView: $promptTextView,
                    isLoading: isLoading,
                    progress: progress,
                    isCancelled: $isCancelled,
                    onSubmit: submitPrompt,
                    onStop: stopGeneration,
                    onPopOut: {
                        openWindow(id: "response-window")
                    },
                    onAnnotate: { slotId in
                        openWindow(value: slotId)
                    },
                    onApiKeySelected: handleApiKeySelection,
                    onOutputFolderSelected: handleOutputFolderSelection,
                    onComfyJSONSelected: handleComfyJSONSelection,
                    onBatchFileSelected: handleBatchFileSelection,
                    onBatchSubmit: batchSubmit,
                    onEditBatchFile: {
                        if batchFilePath.isEmpty {
                            openWindow(id: "text-editor", value: Data())
                        } else if let bookmarkData = UserDefaults.standard.data(forKey: "batchFileBookmark") {
                            do {
                                var isStale = false
                                let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
                                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
                                if resolvedURL.startAccessingSecurityScopedResource() {
                                    defer { resolvedURL.stopAccessingSecurityScopedResource() }
                                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                                        openWindow(id: "text-editor", value: bookmarkData)
                                    } else {
                                        clearBatchFile()
                                        openWindow(id: "text-editor", value: Data())
                                    }
                                } else {
                                    clearBatchFile()
                                    openWindow(id: "text-editor", value: Data())
                                }
                            } catch {
                                clearBatchFile()
                                openWindow(id: "text-editor", value: Data())
                            }
                        } else {
                            errorItem = AlertError(message: "Failed to access batch file. Please check your file permissions or select a new file.", fullMessage: nil)
                        }
                    },
                    batchFilePath: $batchFilePath,
                    batchStartIndex: $batchStartIndex,
                    batchEndIndex: $batchEndIndex
                )
                .environmentObject(appState)
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarContent
            }
        }
    }
    #endif
 
    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            toolbarContent
        }
    }
    #endif
 
    private var toolbarContent: some View {
        Group {
 
 
            Button(action: { showGeneralOptions = true }) {
                Image(systemName: "gear")
            }
            .help("General Settings")
            .accessibilityLabel("General Settings")
            .accessibilityHint("Opens the general settings page.")
 
            Button(action: {
                #if os(iOS)
                appState.presentedModal = .history
                #else
                withAnimation(.easeInOut(duration: 0.3)) {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
                #endif
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Toggle History Sidebar")
            .accessibilityLabel("Toggle History")
            .accessibilityHint("Shows or hides the history sidebar.")
 
            Button(action: {
                showHelp = true
            }) {
                Image(systemName: "questionmark.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Help & Guide")
            .accessibilityLabel("Help")
            .accessibilityHint("Opens the help and guide sheet.")
 
            onboardingButton
            billingButton
        }
    }
 
    @ViewBuilder
    private var onboardingButton: some View {
        Button(action: {
            showOnboarding = true
        }) {
            Image(systemName: "info.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .help("Show onboarding guide")
        .accessibilityLabel("Onboarding")
        .accessibilityHint("Opens the onboarding guide.")
    }
 
    @ViewBuilder
    private var billingButton: some View {
        if appState.settings.mode == .gemini {
            Button(action: openBillingConsole) {
                Image(systemName: "dollarsign.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Open Gemini Billing Console")
            .accessibilityLabel("Billing")
            .accessibilityHint("Opens the Gemini billing console in a browser.")
        } else if appState.settings.mode == .grok {
            Button(action: openGrokBillingConsole) {
                Image(systemName: "dollarsign.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Open Grok Billing Console")
            .accessibilityLabel("Billing")
            .accessibilityHint("Opens the Grok billing console in a browser.")
        } else if appState.settings.mode == .aimlapi {
            Button(action: openAIMLBillingConsole) {
                Image(systemName: "dollarsign.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Open AI/ML API Billing Console")
            .accessibilityLabel("Billing")
            .accessibilityHint("Opens the AI/ML API billing console in a browser.")
        }
    }
 
    private func openBillingConsole() {
        if let url = URL(string: "https://console.cloud.google.com/billing") {
            PlatformBrowser.open(url: url)
        }
    }
 
    private func openGrokBillingConsole() {
        if let url = URL(string: "https://console.x.ai") {
            PlatformBrowser.open(url: url)
        }
    }
 
    private func openAIMLBillingConsole() {
        if let url = URL(string: "https://aimlapi.com/app/billing") {
            PlatformBrowser.open(url: url)
        }
    }
 
    private func validateBatchFileBookmark() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "batchFileBookmark") {
            do {
                var isStale = false
                #if os(macOS)
                let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let options: URL.BookmarkResolutionOptions = []
                #endif
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
                if resolvedURL.startAccessingSecurityScopedResource() {
                    defer { resolvedURL.stopAccessingSecurityScopedResource() }
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        batchFilePath = resolvedURL.path
                    } else {
                        clearBatchFile()
                    }
                } else {
                    clearBatchFile()
                }
            } catch {
                clearBatchFile()
            }
        }
    }
 
    private func clearBatchFile() {
        batchFilePath = ""
        appState.batchPrompts = []
        UserDefaults.standard.removeObject(forKey: "batchFileBookmark")
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


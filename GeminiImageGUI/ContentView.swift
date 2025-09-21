// contentview.swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
 
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
 
    func fullImageSheet(showFullImage: Binding<Bool>, outputImage: PlatformImage?) -> some View {
        sheet(isPresented: showFullImage) {
            if let outputImage = outputImage {
                FullImageView(image: outputImage)
            }
        }
        .accessibilityLabel("Full Image View Sheet")
    }
 
    func errorAlert(showErrorAlert: Binding<Bool>, errorMessage: String?) -> some View {
        alert("Error", isPresented: showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .accessibilityLabel("Error Alert")
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
 
enum GenerationError: Error {
    case invalidURL
    case encodingFailed(String)
    case apiError(String)
    case noWorkflow
    case invalidServerURL
    case invalidWebSocketURL
    case invalidPromptNode
    case uploadFailed
    case queueFailed
    case noOutputImage
    case decodeFailed
    case fetchFailed(String)
    case invalidViewURL
    case invalidImageNode
}
 
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State var isLoading: Bool = false  // Removed 'private'
    @State var progress: Double = 0.0  // Removed 'private'
    @State var webSocketTask: URLSessionWebSocketTask? = nil  // Removed 'private'
    @State var isCancelled: Bool = false  // Removed 'private'
    @State var errorMessage: String? = nil  // Removed 'private'
    @State var showErrorAlert: Bool = false  // Removed 'private'
    @State var showApiKey: Bool = false  // Removed 'private'
    @State var apiKeyPath: String = ""  // Removed 'private'
    @State var outputPath: String = ""  // Removed 'private'
    @State var showOnboarding: Bool = false  // Removed 'private'
    @State var imageScale: CGFloat = 1.0  // Removed 'private'
    @State var isTestingApi: Bool = false  // Removed 'private'
    @State var showFullImage: Bool = false  // Removed 'private'
    @State var showAnnotationSheet: Bool = false  // Removed 'private'
    @State var selectedSlotId: UUID?  // Removed 'private'
    @State var batchFilePath: String = ""  // Removed 'private'
    @State var batchStartIndex: Int = 1
    @State var batchEndIndex: Int = 1
    @State var successMessage: String = ""  // Removed 'private'
    @State var showSuccessAlert: Bool = false  // Removed 'private'
    @State var showHelp: Bool = false  // New: For help sheet
    @State var showSelectFolderAlert: Bool = false // New: For output folder alert
    @State var pendingAction: (() -> Void)? = nil // New: For pending submit action
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @AppStorage("configExpanded") private var configExpanded: Bool = true
    @AppStorage("promptExpanded") private var promptExpanded: Bool = true
    @AppStorage("inputImagesExpanded") private var inputImagesExpanded: Bool = true
    @AppStorage("responseExpanded") private var responseExpanded: Bool = true
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
    
    var body: some View {
#if os(iOS)
        iOSLayout
            .workflowErrorAlert(appState: appState)
            .fullImageSheet(showFullImage: $showFullImage, outputImage: appState.ui.outputImage)
            .errorAlert(showErrorAlert: $showErrorAlert, errorMessage: errorMessage)
            .successAlert(showSuccessAlert: $showSuccessAlert, successMessage: successMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .helpSheet(showHelp: $showHelp, mode: appState.settings.mode)
            .selectFolderAlert(isPresented: $showSelectFolderAlert) { // New: Attach alert modifier
                print("Showing output folder picker from alert")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                    if !outputPath.isEmpty {
                        pendingAction?()
                        pendingAction = nil
                    }
                }
            }
            .onAppear {
                performOnAppear()
            }
            .onChange(of: appState.ui.outputImage) { _ in
                imageScale = 1.0
            }
#else
        macOSLayout
            .workflowErrorAlert(appState: appState)
            .fullImageSheet(showFullImage: $showFullImage, outputImage: appState.ui.outputImage)
            .errorAlert(showErrorAlert: $showErrorAlert, errorMessage: errorMessage)
            .successAlert(showSuccessAlert: $showSuccessAlert, successMessage: successMessage)
            .onboardingSheet(showOnboarding: $showOnboarding)
            .helpSheet(showHelp: $showHelp, mode: appState.settings.mode)
            .selectFolderAlert(isPresented: $showSelectFolderAlert) { // New: Attach alert modifier
                print("Showing output folder picker from alert")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                    if !outputPath.isEmpty {
                        pendingAction?()
                        pendingAction = nil
                    }
                }
            }
            .onAppear {
                performOnAppear()
            }
            .onChange(of: appState.ui.outputImage) { _ in
                imageScale = 1.0
            }
#endif
    }
    
#if os(iOS)
    @ViewBuilder
    
    private var iOSLayout: some View {
        
        NavigationStack {
            
            ScrollView {
                VStack(spacing: 16) {  // Added VStack for better grouping and spacing
                    //                Text("Main UI")
                    //                    .foregroundColor(.primary)
                    //                    .font(.headline)  // Slightly bolder for hierarchy
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
                        errorMessage: $errorMessage,
                        showErrorAlert: $showErrorAlert,
                        imageScale: $imageScale,
                        showFullImage: $showFullImage,
                        isLoading: isLoading,
                        progress: progress,
                        isCancelled: $isCancelled,
                        onSubmit: submitPrompt,
                        onStop: stopGeneration,
                        onPopOut: {
                            appState.showResponseSheet = true
                        },
                        onAnnotate: { slotId in
                            appState.showMarkupSlotId = slotId
                        },
                        onApiKeySelected: handleApiKeySelection,
                        onOutputFolderSelected: handleOutputFolderSelection,
                        onComfyJSONSelected: handleComfyJSONSelection,
                        onBatchFileSelected: handleBatchFileSelection,
                        onBatchSubmit: batchSubmit,
                        batchFilePath: $batchFilePath,
                        batchStartIndex: $batchStartIndex,
                        batchEndIndex: $batchEndIndex
                    )
                    .environmentObject(appState)
                    .padding(.horizontal, 20)  // Increased horizontal padding for iPad comfort
                }
            }
            .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    toolbarContent
                }
            }
            .fullScreenCover(isPresented: $showHistory) {
                HistoryView(imageSlots: $appState.ui.imageSlots, columnVisibility: $columnVisibility)
                    .environmentObject(appState)
            }
            .fullScreenCover(isPresented: Binding(get: { appState.showResponseSheet }, set: { appState.showResponseSheet = $0 })) {
                PopOutView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: Binding(
                get: { appState.showFullHistoryItem != nil },
                set: { if !$0 { appState.showFullHistoryItem = nil } }
            )) {
                if let id = appState.showFullHistoryItem {
                    FullHistoryItemView(initialId: id)
                        .environmentObject(appState)
                }
            }
            .fullScreenCover(item: $appState.showMarkupSlotId) { slotId in
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
            }
        }
    }
#else
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
                    errorMessage: $errorMessage,
                    showErrorAlert: $showErrorAlert,
                    imageScale: $imageScale,
                    showFullImage: $showFullImage,
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
                    batchFilePath: $batchFilePath,
                    batchStartIndex: $batchStartIndex,
                    batchEndIndex: $batchEndIndex
                )
                .environmentObject(appState)
                .padding(.horizontal, 20)  // Add padding for better readability and alignment with iOS
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
    
    private var toolbarContent: some View {
        Group {
/*            Button(action: {
                print("Showing api file picker from toolbar")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                    handleApiKeySelection(result)
                }
            }) {
                Image(systemName: "key")
                    .symbolRenderingMode(.hierarchical)
                
            }
            .help("Load API Key")
*/
            Button(action: {
                print("Showing output folder picker from toolbar")
                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                    handleOutputFolderSelection(result)
                }
            }) {
                Image(systemName: "folder")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Select Output Folder")
            .accessibilityLabel("Select Output Folder")
            .accessibilityHint("Opens a folder picker to choose where generated images are saved.")
            
            Button(action: resetAppState) {
                Image(systemName: "arrow.counterclockwise")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("New Session")
            .accessibilityLabel("New Session")
            .accessibilityHint("Resets the current session, clearing prompt and images.")
            
            Button(action: {
#if os(iOS)
                showHistory.toggle()
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
            
            Button(action: {
                showOnboarding = true
            }) {
                Image(systemName: "info.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Show onboarding guide")
            .accessibilityLabel("Onboarding")
            .accessibilityHint("Opens the onboarding guide.")
 
            if appState.settings.mode == .gemini {
                Button(action: openBillingConsole) {
                    Image(systemName: "dollarsign.circle")
                        .symbolRenderingMode(.hierarchical)
                }
                .help("Open Gemini Billing Console")
                .accessibilityLabel("Billing")
                .accessibilityHint("Opens the Gemini billing console in a browser.")
            }
        }
    }
 
    private func openBillingConsole() {
        if let url = URL(string: "https://console.cloud.google.com/billing") {
            PlatformBrowser.open(url: url)
        }
    }
}
 

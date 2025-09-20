//MainFormView.swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct MainFormView: View {
    @Binding var configExpanded: Bool
    @Binding var promptExpanded: Bool
    @Binding var inputImagesExpanded: Bool
    @Binding var responseExpanded: Bool
    @Binding var prompt: String
    @Binding var showApiKey: Bool
    @Binding var apiKeyPath: String
    @Binding var outputPath: String
    @Binding var isTestingApi: Bool
    @Binding var errorMessage: String?
    @Binding var showErrorAlert: Bool
    @Binding var imageScale: CGFloat
    @Binding var showFullImage: Bool
    @State private var isUnsafe: Bool = false  // State for safety feedback
    let isLoading: Bool
    let progress: Double
    @Binding var isCancelled: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onPopOut: () -> Void
    let onAnnotate: (UUID) -> Void
    let onApiKeySelected: (Result<[URL], Error>) -> Void
    let onOutputFolderSelected: (Result<[URL], Error>) -> Void
    let onComfyJSONSelected: (Result<[URL], Error>) -> Void
    let onBatchFileSelected: (Result<[URL], Error>) -> Void  // New: Handler for batch file selection
    let onBatchSubmit: () -> Void  // New: Handler for batch submission (implement in ContentView to loop over prompts)

    @EnvironmentObject var appState: AppState
    
    @Environment(\.undoManager) private var undoManager
    
    @State private var showCopiedMessage: Bool = false
    @Binding var batchFilePath: String  // New: Path to selected batch file
    @Binding var startPrompt: String  // Changed to @Binding
    @Binding var endPrompt: String  // Changed to @Binding
    @AppStorage("batchExpanded") private var batchExpanded: Bool = true  // New: Expansion state
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var isCompact: Bool {
        sizeClass == .compact
    }

    var isSubmitDisabled: Bool {
        if appState.settings.mode == .gemini {
            return appState.settings.apiKey.isEmpty || prompt.isEmpty
        } else {
            let effectivePromptEmpty = prompt.isEmpty && selectedPromptText.isEmpty
            return appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty || effectivePromptEmpty
        }
    }
    
    private var selectedPromptText: String {
        appState.generation.promptNodes.first(where: { $0.id == appState.generation.comfyPromptNodeID })?.promptText ?? ""
    }
    
    private var isBatchSubmitDisabled: Bool {  // Updated: Disable if no prompts or invalid range or invalid config
        if appState.settings.mode == .gemini && appState.settings.apiKey.isEmpty {
            return true
        }
        if appState.settings.mode == .comfyUI && (appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty) {
            return true
        }
        guard !appState.batchPrompts.isEmpty else { return true }
        let start = Int(startPrompt) ?? 1
        let end = Int(endPrompt) ?? appState.batchPrompts.count
        return start < 1 || end > appState.batchPrompts.count || start > end
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                DisclosureGroup(isExpanded: $configExpanded) {
                    ConfigurationSection(
                        showApiKey: $showApiKey,
                        apiKeyPath: $apiKeyPath,
                        outputPath: $outputPath,
                        isTestingApi: $isTestingApi,
                        errorMessage: $errorMessage,
                        showErrorAlert: $showErrorAlert,
                        onApiKeySelected: onApiKeySelected,
                        onOutputFolderSelected: onOutputFolderSelected,
                        onComfyJSONSelected: onComfyJSONSelected
                    )
                } label: {
                    Text("Configuration")
                        .font(.system(size: 20, weight: .semibold))  // Increased label font size
                        .help("Configure API keys, output paths, and other settings for image generation")
                }
                .kerning(0.2)
                .foregroundColor(.primary) // Ensure visibility
                
                CustomDivider()
                
                DisclosureGroup(isExpanded: $promptExpanded) {
                                    PromptSection(prompt: $prompt, isUnsafe: $isUnsafe)  // Pass isUnsafe binding
                } label: {
                    HStack {
                        Text("Prompt")
                            .font(.system(size: 20, weight: .semibold))  // Increased label font size
                            .help("Enter or manage the text prompt for image generation")
                        
                        Spacer()
                        
                        Button(action: { pasteToPrompt() }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help("Paste text from clipboard into the prompt field")
                        
                        Button(action: { copyPromptToClipboard() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy the current prompt to the clipboard")
                        
                        Button(action: {
                            if !prompt.isEmpty {
                                let oldPrompt = prompt
                                prompt = ""
                                undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear the current prompt (can be undone)")
                    }
                }
                
                CustomDivider()
                
                DisclosureGroup(isExpanded: $inputImagesExpanded) {
                    InputImagesSection(
                        imageSlots: $appState.ui.imageSlots,
                        errorMessage: $errorMessage,
                        showErrorAlert: $showErrorAlert,
                        onAnnotate: onAnnotate
                    )
                } label: {
                    Text("Input Images")
                        .font(.system(size: 20, weight: .semibold))  // Increased label font size
                        .help("Add or manage input images for the generation process")
                }
                .kerning(0.2)
                .foregroundColor(.primary)
                
                CustomDivider()
                
                Group {
                    if isLoading {
                        LoadingView(mode: appState.settings.mode, progress: progress, isCancelled: $isCancelled, onStop: onStop)
                    } else {
                        Button("Submit") {
                            onSubmit()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isSubmitDisabled ? .gray : .blue)
                        .foregroundColor(isSubmitDisabled ? .gray : .white)
                        .controlSize(.large)
                        .disabled(isSubmitDisabled)
                        .frame(maxWidth: .infinity, minHeight: 44)  // Standard iOS button height
                        .font(.system(size: 17, weight: .semibold))
                        .help("Submit the current prompt and settings to generate an image")
                    }
                }
                .padding(.vertical, 5)
                .offset(y: 0)
                
                CustomDivider()
                
                
                // New: Batch Mode section
                DisclosureGroup(isExpanded: $batchExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isCompact {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Batch File:")
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .help("Select a text file containing one prompt per line for batch processing")
                                HStack {
                                    #if os(iOS)
                                    Text(batchFilePath.isEmpty ? "No file selected" : URL(fileURLWithPath: batchFilePath).lastPathComponent)
                                        .help("Currently selected batch file path")
                                    #else
                                    Text(batchFilePath.isEmpty ? "No file selected" : batchFilePath)
                                        .help("Currently selected batch file path")
                                    #endif
                                    Button(action: {
                                        PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                                            onBatchFileSelected(result)
                                        }
                                    }) {
                                        Image(systemName: "doc")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Choose a .txt file with multiple prompts for batch generation")
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(alignment: .center) {
                                Text("Batch File:")
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .help("Select a text file containing one prompt per line for batch processing")
                                #if os(iOS)
                                Text(batchFilePath.isEmpty ? "No file selected" : URL(fileURLWithPath: batchFilePath).lastPathComponent)
                                    .help("Currently selected batch file path")
                                #else
                                Text(batchFilePath.isEmpty ? "No file selected" : batchFilePath)
                                    .help("Currently selected batch file path")
                                #endif
                                Button(action: {
                                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                                        onBatchFileSelected(result)
                                    }
                                }) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                                .help("Choose a .txt file with multiple prompts for batch generation")
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        HStack {
                            Text("Starting Prompt:")
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading) // Align labels
                                .help("Specify the starting prompt number in the batch file")
                            TextField("1", text: $startPrompt)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .help("Enter the 1-based index of the first prompt to process (default: 1)")
                            
                            Spacer().frame(width: 20)  // Add 50px space between boxes
                            
                            Text("Ending Prompt:")
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading) // Align labels
                                .help("Specify the ending prompt number in the batch file")
                            TextField("", text: $endPrompt)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .help("Enter the 1-based index of the last prompt to process (default: last prompt)")
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if appState.batchPrompts.isEmpty {
                            Text("Select a .txt file with one prompt per line.")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                                .padding(.top, 4)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .help("The batch file should contain one prompt per line for sequential processing")
                        }
                        
                        Group {
                            // New: Batch Submit button
                            Button("Submit Batch Job") {
                                onBatchSubmit()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint((isBatchSubmitDisabled || isLoading) ? .gray : .blue)
                            .foregroundColor((isBatchSubmitDisabled || isLoading) ? .gray : .white)
                            .controlSize(.large)
                            .disabled(isBatchSubmitDisabled || isLoading)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .font(.system(size: 17, weight: .semibold))
                            .help("Start generating images for the selected range of prompts in batch mode")
                        }
                        .padding(.vertical, 5)
                        .offset(y: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Batch Mode")
                        .font(.system(size: 20, weight: .semibold))  // Increased label font size
                        .help("Process multiple prompts from a file in batch for efficient generation")
                }
                .kerning(0.2)
                .foregroundColor(.primary)
                
                CustomDivider()
                
                DisclosureGroup(isExpanded: $responseExpanded) {
                    ResponseSection(
                        imageScale: $imageScale,
                        showFullImage: $showFullImage,
                        errorMessage: $errorMessage,
                        showErrorAlert: $showErrorAlert
                    )
                } label: {
                    HStack {
                        Text("Response")
                            .font(.system(size: 20, weight: .semibold))  // Increased label font size
                            .help("View generated images and responses from the AI")
                        Spacer()
                        Button(action: onPopOut) {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Pop out the response section to a new window for better viewing")
                    }
                }
                .foregroundColor(.primary)
            }
            .padding()
            
            if showCopiedMessage {
                Text("Copied to Clipboard")
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .transition(.opacity)
                    .help("Confirmation that the prompt was copied to the clipboard")
            }
        }
        .onChange(of: appState.batchPrompts) { newPrompts in  // New: Update start/end on batch load
            if !newPrompts.isEmpty {
                startPrompt = "1"
                endPrompt = "\(newPrompts.count)"
            } else {
                startPrompt = "1"
                endPrompt = ""
            }
        }
    }
    
    private func pasteToPrompt() {
        var pastedText: String? = nil
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pastedText = pasteboard.string(forType: .string)
        #elseif os(iOS)
        pastedText = UIPasteboard.general.string
        #endif
        
        if let text = pastedText {
            let oldPrompt = prompt
            prompt = text
            undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)
        }
    }
    
    private func copyPromptToClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = prompt
        #endif
        withAnimation {
            showCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedMessage = false
            }
        }
    }
}

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
    
    private var isBatchSubmitDisabled: Bool {  // New: Disable if no prompts or invalid range
        guard !appState.batchPrompts.isEmpty else { return true }
        let start = Int(startPrompt) ?? 1
        let end = Int(endPrompt) ?? appState.batchPrompts.count
        return start < 1 || end > appState.batchPrompts.count || start > end
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                DisclosureGroup("Configuration", isExpanded: $configExpanded) {
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
                }
                .font(.system(.headline, design: .default, weight: .semibold))
                .kerning(0.2)
                .foregroundColor(.primary) // Ensure visibility
                
                Divider()
                    .foregroundStyle(.separator.opacity(0.5))
                
                DisclosureGroup(isExpanded: $promptExpanded) {
                    PromptSection(prompt: $prompt)
                } label: {
                    HStack {
                        Text("Prompt")
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .kerning(0.2)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: { pasteToPrompt() }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .help("Paste from clipboard")
                        
                        Button(action: { copyPromptToClipboard() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                        
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
                        .help("Clear prompt")
                    }
                }
                
                Divider()
                    .foregroundStyle(.separator.opacity(0.5))
                
                DisclosureGroup("Input Images", isExpanded: $inputImagesExpanded) {
                    InputImagesSection(
                        imageSlots: $appState.ui.imageSlots,
                        errorMessage: $errorMessage,
                        showErrorAlert: $showErrorAlert,
                        onAnnotate: onAnnotate
                    )
                }
                .font(.system(.headline, design: .default, weight: .semibold))
                .kerning(0.2)
                .foregroundColor(.primary)
                
                Divider()
                    .foregroundStyle(.separator.opacity(0.5))
                
                Group {
                    if isLoading {
                        LoadingView(mode: appState.settings.mode, progress: progress, isCancelled: $isCancelled, onStop: onStop)
                    } else {
                        Button("Submit") {
                            onSubmit()
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitDisabled)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.vertical, 8)
                        .font(.system(size: 24, weight: .medium))
                    }
                }
                .padding(.vertical, -12)
                .offset(y: 0)
                
                Divider()
                    .foregroundStyle(.separator.opacity(0.5))
                
                // New: Batch Mode section
                DisclosureGroup("Batch Mode", isExpanded: $batchExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center) {
                            Text("Batch File:")
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.secondary)
                            #if os(iOS)
                            Text(batchFilePath.isEmpty ? "No file selected" : URL(fileURLWithPath: batchFilePath).lastPathComponent)
                            #else
                            Text(batchFilePath.isEmpty ? "No file selected" : batchFilePath)
                            #endif
                            Spacer()
                            Button("Select File") {
                                PlatformFilePicker.presentOpenPanel(allowedTypes: [.plainText], allowsMultiple: false, canChooseDirectories: false) { result in
                                    onBatchFileSelected(result)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue.opacity(0.8))
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .shadow(color: .black.opacity(0.1), radius: 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Text("Starting Prompt:")
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 130, alignment: .leading) // Align labels
                            TextField("1", text: $startPrompt)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Text("Ending Prompt:")
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 130, alignment: .leading) // Align labels
                            TextField("", text: $endPrompt)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Group {
                            // New: Batch Submit button
                            Button("Submit Batch Job") {
                                onBatchSubmit()
                            }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                            .disabled(isBatchSubmitDisabled || isLoading)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .padding(.vertical, 8)
                            .font(.system(size: 24, weight: .medium))
                        }
                        .padding(.vertical, -12)
                        .offset(y: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(.headline, design: .default, weight: .semibold))
                .kerning(0.2)
                .foregroundColor(.primary)
                
                Divider()
                    .foregroundStyle(.separator.opacity(0.5))
                
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
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .kerning(0.2)
                        Spacer()
                        Button(action: onPopOut) {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Pop out to new window")
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

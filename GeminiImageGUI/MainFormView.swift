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
    @Binding var errorItem: AlertError?
    @Binding var imageScale: CGFloat
    @Binding var promptTextView: (any PlatformTextView)?  // New: From PromptSection
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
    let onBatchFileSelected: (Result<[URL], Error>) -> Void
    let onBatchSubmit: () -> Void
    let onEditBatchFile: () -> Void

    @EnvironmentObject var appState: AppState
    
    @Environment(\.undoManager) private var undoManager
    
    @State private var showCopiedMessage: Bool = false
    @Binding var batchFilePath: String
    @Binding var batchStartIndex: Int
    @Binding var batchEndIndex: Int
    @AppStorage("batchExpanded") private var batchExpanded: Bool = true
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var isCompact: Bool {
        sizeClass == .compact
    }

    var isSubmitDisabled: Bool {
        switch appState.settings.mode {
        case .gemini:
            return appState.settings.apiKey.isEmpty || prompt.isEmpty
        case .comfyUI:
            let effectivePromptEmpty = prompt.isEmpty && selectedPromptText.isEmpty
            return appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty || effectivePromptEmpty
        case .grok:
            return appState.settings.grokApiKey.isEmpty || prompt.isEmpty
        case .aimlapi:
            return appState.settings.aimlapiKey.isEmpty || prompt.isEmpty
        }
    }
    
    private var selectedPromptText: String {
        appState.generation.promptNodes.first(where: { $0.id == appState.generation.comfyPromptNodeID })?.promptText ?? ""
    }
    
    private var isBatchSubmitDisabled: Bool {
        switch appState.settings.mode {
        case .gemini:
            if appState.settings.apiKey.isEmpty {
                return true
            }
        case .comfyUI:
            if appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty {
                return true
            }
        case .grok:
            if appState.settings.grokApiKey.isEmpty {
                return true
            }
        case .aimlapi:
            if appState.settings.aimlapiKey.isEmpty {
                return true
            }
        }
        guard !appState.batchPrompts.isEmpty else { return true }
        let start = batchStartIndex
        let end = batchEndIndex
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
                        errorItem: $errorItem,
                        onApiKeySelected: onApiKeySelected,
                        onOutputFolderSelected: onOutputFolderSelected,
                        onComfyJSONSelected: onComfyJSONSelected
                    )
                } label: {
                    Text("Configuration")
                        .font(.system(size: 20, weight: .semibold))
                        .help("Configure API keys, output paths, and other settings for image generation")
                }
                .kerning(0.2)
                .foregroundColor(.primary)

                CustomDivider()
                
                DisclosureGroup(isExpanded: $promptExpanded) {
                        PromptSection(prompt: $prompt, isUnsafe: $isUnsafe, platformTextView: $promptTextView)  // Pass binding
                } label: {
                    HStack {
                        Text("Prompt")
                            .font(.system(size: 20, weight: .semibold))
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
                            if let textView = promptTextView {
                                let oldPrompt = prompt  // Backup for optional extra undo registration
                                textView.clear()  // Native clear, which integrates with undoManager automatically
                                undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)  // Optional: Reinforce if needed
                            } else if !prompt.isEmpty {
                                // Fallback if native view not available (e.g., during init)
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
                        errorItem: $errorItem,
                        onAnnotate: onAnnotate
                    )
                } label: {
                    Text("Input Images")
                        .font(.system(size: 20, weight: .semibold))
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
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .font(.system(size: 17, weight: .semibold))
                        .help("Submit the current prompt and settings to generate an image")
                    }
                }
                .padding(.vertical, 5)
                .offset(y: 0)
                
                CustomDivider()
                
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
                                    
                                    Button(action: {
                                        onEditBatchFile()
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Edit or create a batch file")
                                    
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
                                
                                Button(action: {
                                    onEditBatchFile()
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 16))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                                .help("Edit or create a batch file")
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if isCompact {
                            HStack {
                                VStack(alignment: .center) {
                                    Text("Starting Prompt:")
                                        .font(.system(.subheadline, design: .default, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .help("Specify the starting prompt number in the batch file")
                                    if appState.batchPrompts.count >= 1 {
                                        #if os(iOS)
                                        Picker("", selection: $batchStartIndex) {
                                            ForEach(1...appState.batchPrompts.count, id: \.self) { num in
                                                Text("\(num)").tag(num)
                                            }
                                        }
                                        .pickerStyle(.wheel)
                                        .frame(width: 80, height: 100)
                                        .clipped()
                                        .disabled(appState.batchPrompts.isEmpty)
                                        .help("Select the 1-based index of the first prompt to process (default: 1)")
                                        #else
                                        HStack(spacing: 0) {
                                            Button("-") {
                                                if batchStartIndex > 1 {
                                                    batchStartIndex -= 1
                                                }
                                            }
                                            .disabled(batchStartIndex <= 1 || appState.batchPrompts.isEmpty)
                                            
                                            TextField("", value: $batchStartIndex, formatter: NumberFormatter())
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 60)
                                                .disabled(appState.batchPrompts.isEmpty)
                                            
                                            Button("+") {
                                                if batchStartIndex < appState.batchPrompts.count {
                                                    batchStartIndex += 1
                                                }
                                            }
                                            .disabled(batchStartIndex >= appState.batchPrompts.count || appState.batchPrompts.isEmpty)
                                        }
                                        .help("Select the 1-based index of the first prompt to process (default: 1)")
                                        #endif
                                    } else {
                                        Text("N/A")
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .center) {
                                    Text("Ending Prompt:")
                                        .font(.system(.subheadline, design: .default, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .help("Specify the ending prompt number in the batch file")
                                    if appState.batchPrompts.count >= 1 {
                                        #if os(iOS)
                                        Picker("", selection: $batchEndIndex) {
                                            ForEach(1...appState.batchPrompts.count, id: \.self) { num in
                                                Text("\(num)").tag(num)
                                            }
                                        }
                                        .pickerStyle(.wheel)
                                        .frame(width: 80, height: 100)
                                        .clipped()
                                        .disabled(appState.batchPrompts.isEmpty)
                                        .help("Select the 1-based index of the last prompt to process (default: last prompt)")
                                        #else
                                        HStack(spacing: 0) {
                                            Button("-") {
                                                if batchEndIndex > 1 {
                                                    batchEndIndex -= 1
                                                }
                                            }
                                            .disabled(batchEndIndex <= 1 || appState.batchPrompts.isEmpty)
                                            
                                            TextField("", value: $batchEndIndex, formatter: NumberFormatter())
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 60)
                                                .disabled(appState.batchPrompts.isEmpty)
                                            
                                            Button("+") {
                                                if batchEndIndex < appState.batchPrompts.count {
                                                    batchEndIndex += 1
                                                }
                                            }
                                            .disabled(batchEndIndex >= appState.batchPrompts.count || appState.batchPrompts.isEmpty)
                                        }
                                        .help("Select the 1-based index of the last prompt to process (default: last prompt)")
                                        #endif
                                    } else {
                                        Text("N/A")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Text("Starting Prompt:")
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .help("Specify the starting prompt number in the batch file")
                                if appState.batchPrompts.count >= 1 {
                                    #if os(iOS)
                                    Picker("", selection: $batchStartIndex) {
                                        ForEach(1...appState.batchPrompts.count, id: \.self) { num in
                                            Text("\(num)").tag(num)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 80, height: 100)
                                    .clipped()
                                    .disabled(appState.batchPrompts.isEmpty)
                                    .help("Select the 1-based index of the first prompt to process (default: 1)")
                                    #else
                                    HStack(spacing: 0) {
                                        Button("-") {
                                            if batchStartIndex > 1 {
                                                batchStartIndex -= 1
                                            }
                                        }
                                        .disabled(batchStartIndex <= 1 || appState.batchPrompts.isEmpty)
                                        
                                        TextField("", value: $batchStartIndex, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .disabled(appState.batchPrompts.isEmpty)
                                        
                                        Button("+") {
                                            if batchStartIndex < appState.batchPrompts.count {
                                                batchStartIndex += 1
                                            }
                                        }
                                        .disabled(batchStartIndex >= appState.batchPrompts.count || appState.batchPrompts.isEmpty)
                                    }
                                    .help("Select the 1-based index of the first prompt to process (default: 1)")
                                    #endif
                                } else {
                                    Text("N/A")
                                        .foregroundColor(.gray)
                                }

                                Spacer().frame(width: 20)

                                Text("Ending Prompt:")
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .help("Specify the ending prompt number in the batch file")
                                if appState.batchPrompts.count >= 1 {
                                    #if os(iOS)
                                    Picker("", selection: $batchEndIndex) {
                                        ForEach(1...appState.batchPrompts.count, id: \.self) { num in
                                            Text("\(num)").tag(num)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: 80, height: 100)
                                    .clipped()
                                    .disabled(appState.batchPrompts.isEmpty)
                                    .help("Select the 1-based index of the last prompt to process (default: last prompt)")
                                    #else
                                    HStack(spacing: 0) {
                                        Button("-") {
                                            if batchEndIndex > 1 {
                                                batchEndIndex -= 1
                                            }
                                        }
                                        .disabled(batchEndIndex <= 1 || appState.batchPrompts.isEmpty)
                                        
                                        TextField("", value: $batchEndIndex, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                            .disabled(appState.batchPrompts.isEmpty)
                                        
                                        Button("+") {
                                            if batchEndIndex < appState.batchPrompts.count {
                                                batchEndIndex += 1
                                            }
                                        }
                                        .disabled(batchEndIndex >= appState.batchPrompts.count || appState.batchPrompts.isEmpty)
                                    }
                                    .help("Select the 1-based index of the last prompt to process (default: last prompt)")
                                    #endif
                                } else {
                                    Text("N/A")
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if appState.batchPrompts.isEmpty {
                            Text("Select a .txt file with one prompt per line.")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                                .padding(.top, 4)
                            if batchFilePath.isEmpty {
                                Text("Or create a new batch file using the edit button.")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            EmptyView()
                                .help("The batch file should contain one prompt per line for sequential processing")
                        }
                        
                        Group {
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
                        .font(.system(size: 20, weight: .semibold))
                        .help("Process multiple prompts from a file in batch for efficient generation")
                }
                .kerning(0.2)
                .foregroundColor(.primary)
                
                CustomDivider()
                
                DisclosureGroup(isExpanded: $responseExpanded) {
                    ResponseSection(
                        imageScale: $imageScale,
                        errorItem: $errorItem
                    )
                } label: {
                    HStack {
                        Text("Response")
                            .font(.system(size: 20, weight: .semibold))
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
        .onChange(of: appState.batchPrompts) { newPrompts in
            if !newPrompts.isEmpty {
                batchStartIndex = 1
                batchEndIndex = newPrompts.count
            } else {
                batchStartIndex = 1
                batchEndIndex = 1
            }
        }
    }
    
    private func pasteToPrompt() {
            if let textView = promptTextView {
                textView.paste()  // Native paste with undo
            } else {
                // Fallback to your original clipboard logic
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

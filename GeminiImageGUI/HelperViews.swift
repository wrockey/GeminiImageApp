//HelperViews.swift
import SwiftUI
import AVKit
import AVFoundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import Photos
#endif
 
struct Resizer: View {
    let onDrag: (CGFloat) -> Void
   
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onDrag(value.translation.width)
                    }
            )
            #if os(macOS)
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            #endif
    }
}
 
struct PopOutView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss  // Add for closing
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var isVideoPlayable: Bool = false
   
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                let count = appState.ui.outputImages.count
                let index = appState.ui.currentOutputIndex
                if count > 0 {
                    if let optionalPath = appState.ui.outputPaths[safe: index],
                       let path = optionalPath,
                       path.hasSuffix(".mp4") {
                        if isVideoPlayable {
                            VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: path)))
                                .aspectRatio(videoAspectRatio, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        } else {
                            Text("Video unavailable")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .help("Video file is missing or unplayable")
                        }
                    } else if let optionalImage = appState.ui.outputImages[safe: index], let platformImage = optionalImage {
                        Image(platformImage: platformImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    } else {
                        Text("No media available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .help("No image or video available for this output")
                    }
                   
                    if count > 1 {
                        HStack(spacing: 12) {
                            Button {
                                if index > 0 { appState.ui.currentOutputIndex -= 1 }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(index == 0)
                           
                            Text("\(index + 1) of \(count)")
                           
                            Button {
                                if index < count - 1 { appState.ui.currentOutputIndex += 1 }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(index == count - 1)
                        }
                        .padding(.top, 8)
                    }
                }
               
                ScrollView {
                    let text = appState.ui.outputTexts[safe: index] ?? ""
                    TextEditor(text: .constant(text))
                        .frame(height: 80)
                        .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
                        .cornerRadius(12)
                        .disabled(true)
                        .foregroundColor(.primary)
                }
                .frame(height: 80)
            }
           
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .padding()
            .help("Close")
        }
        .onAppear {
            Task {
                await loadVideoMetadata()
            }
            updateWindowSize()
        }
        .onChange(of: appState.ui.outputImages) { _ in
            Task {
                await loadVideoMetadata()
            }
            updateWindowSize()
        }
        .onChange(of: appState.ui.outputPaths) { _ in
            Task {
                await loadVideoMetadata()
            }
            updateWindowSize()
        }
        .onChange(of: appState.ui.currentOutputIndex) { _ in
            Task {
                await loadVideoMetadata()
            }
            updateWindowSize()
        }
    }
   
    private func updateWindowSize() {
        #if os(macOS)
        let index = appState.ui.currentOutputIndex
        guard index < appState.ui.outputImages.count,
              let window = NSApp.windows.last,
              let screen = NSScreen.main else {
            return
        }
       
        let textHeight: CGFloat = 80
        let minWidth: CGFloat = 400
        var desiredSize: CGSize
       
        if let optionalPath = appState.ui.outputPaths[safe: index],
           let path = optionalPath,
           path.hasSuffix(".mp4"),
           isVideoPlayable {
            desiredSize = CGSize(width: max(videoAspectRatio * 400, minWidth), height: 400 + textHeight)
        } else if let platformImage = appState.ui.outputImages[index] {
            let imageSize = platformImage.platformSize
            desiredSize = CGSize(width: max(imageSize.width, minWidth), height: imageSize.height + textHeight)
        } else {
            desiredSize = CGSize(width: minWidth, height: 400 + textHeight)
        }
       
        let screenSize = screen.visibleFrame.size
        let marginHorizontal: CGFloat = 40
        let marginVertical: CGFloat = 100
       
        let maxSize = CGSize(width: screenSize.width - marginHorizontal,
                             height: screenSize.height - marginVertical)
       
        let scale = min(1.0, min(maxSize.width / desiredSize.width, maxSize.height / desiredSize.height))
       
        let windowSize = CGSize(width: desiredSize.width * scale, height: desiredSize.height * scale)
       
        window.setContentSize(windowSize)
        window.center()
        #endif
    }
   
    private func loadVideoMetadata() async {
        let index = appState.ui.currentOutputIndex
        guard let optionalPath = appState.ui.outputPaths[safe: index],
              let path = optionalPath,
              path.hasSuffix(".mp4") else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            return
        }
       
        let fileURL = URL(fileURLWithPath: path)
        guard fileExists(path: path) else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            return
        }
       
        let asset = AVAsset(url: fileURL)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                isVideoPlayable = false
                videoAspectRatio = 16.0 / 9.0
                return
            }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let naturalSize = try await tracks.first?.load(.naturalSize) ?? CGSize(width: 16, height: 9)
            isVideoPlayable = true
            videoAspectRatio = naturalSize.width / naturalSize.height
        } catch {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
        }
    }
   
    private func fileExists(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let dir = appState.settings.outputDirectory {
            return (try? withSecureAccess(to: dir) {
                FileManager.default.fileExists(atPath: url.path)
            }) ?? false
        } else {
            return FileManager.default.fileExists(atPath: url.path)
        }
    }
}
 
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
   
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
               
                Text("Welcome to Gemini Image App")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
               
                Text("Generate stunning images using Google's Gemini AI or the powerful ComfyUI workflow engine. Whether you're a beginner or advanced user, this app makes AI image creation simple and accessible.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
               
                Text("Generated images are AI-created; user responsible for usage. No copyright claims.")
                    .bold()
                    .multilineTextAlignment(.center)
               
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Start Guide:")
                        .font(.headline)
                    Text("1. **Choose Your Mode**: Switch between Gemini (cloud-based) or ComfyUI (local server) in the Configuration section.")
                    Text("2. **Set Up Credentials**: For Gemini, add your API key. For ComfyUI, enter your server URL (default: http://localhost:8188).")
                    Text("3. **Craft a Prompt**: Describe the image you want in the Prompt section.")
                    Text("4. **Add Inputs (Optional)**: Upload reference images in the Input Images section.")
                    Text("5. **Generate**: Hit Submit and watch the magic happen!")
                    Text("6. **Explore History**: View, copy, or reuse past generations from the History sidebar.")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
               
                VStack(spacing: 8) {
                    Text("Pro Tips:")
                        .font(.headline)
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                        Text("Use descriptive prompts for better results, e.g., 'A serene mountain landscape at sunset, in the style of Van Gogh'.")
                    }
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        Text("For ComfyUI, ensure your server is running with network access enabled.")
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
               
                Button("Get Started") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }
            .padding()
        }
        .frame(maxWidth: 400)
    }
}
 
struct HelpView: View {
    let mode: GenerationMode
    @Environment(\.dismiss) private var dismiss
   
    var body: some View {
#if os(iOS)
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch mode {
                    case .gemini:
                        geminiHelpContent
                    case .comfyUI:
                        comfyUIHelpContent
                    case .grok:
                        grokHelpContent
                    case .aimlapi:
                        aimlHelpContent
                    }
                   
                    Text("Privacy Notices")
                        .font(.title2)
                        .padding(.top)
 
                    Text("Review privacy details for services used in the app:")
 
                    ForEach([PrivacyService.gemini, .grok, .aimlapi, .imgbb], id: \.self) { service in
                        if let url = URL(string: service.policyURL) {
                            Link(service.rawValue + " Privacy Policy", destination: url)
                                .padding(.vertical, 5)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(mode == .gemini ? "Gemini Help" : (mode == .comfyUI ? "ComfyUI Help" : (mode == .grok ? "Grok Help" : "AI/ML API Help")))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
#else
        VStack(spacing: 0) {
            Text(mode == .gemini ? "Gemini Help" : (mode == .comfyUI ? "ComfyUI Help" : (mode == .grok ? "Grok Help" : "AI/ML API Help")))
                .font(.title)
                .padding()
           
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch mode {
                    case .gemini:
                        geminiHelpContent
                    case .comfyUI:
                        comfyUIHelpContent
                    case .grok:
                        grokHelpContent
                    case .aimlapi:
                        aimlHelpContent
                    }
                   
                    Text("Privacy Notices")
                        .font(.title2)
                        .padding(.top)
 
                    Text("Review privacy details for services used in the app:")
 
                    ForEach([PrivacyService.gemini, .grok, .aimlapi, .imgbb], id: \.self) { service in
                        if let url = URL(string: service.policyURL) {
                            Link(service.rawValue + " Privacy Policy", destination: url)
                                .padding(.vertical, 5)
                        }
                    }
                }
                .padding()
            }
           
            Button("Done") {
                dismiss()
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
#endif
    }
   
    private var geminiHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gemini Mode Guide")
                .font(.title.bold())
           
            VStack(alignment: .leading, spacing: 12) {
                Text("1. **API Key Setup**")
                    .font(.headline)
                Text("Obtain your free API key from the Google AI Studio (makersuite.google.com). Paste it into the API Key field or load from a .txt file. Use the 'Test API' button to verify.")
               
                Text("2. **Prompting Tips**")
                    .font(.headline)
                Text("- Be descriptive: Include style, mood, composition (e.g., 'A futuristic cityscape at dusk, cyberpunk style, highly detailed').\n- Use modifiers: Add 'in the style of [artist]' or 'photorealistic'.\n- Aspect ratio: Gemini supports square images; experiment with prompts for composition.")
               
                Text("3. **Input Images**")
                    .font(.headline)
                Text("Upload up to 4 images for image-to-image generation. Annotate them with Markup tools for masks or regions.")
               
                Text("4. **Output & History**")
                    .font(.headline)
                Text("- Save or copy generated images directly.\n- View past generations in History for reuse.")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
   
    private var comfyUIHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ComfyUI Mode Guide")
                .font(.title.bold())
           
            VStack(alignment: .leading, spacing: 12) {
                Text("1. **Server Setup**")
                    .font(.headline)
                Text("Run ComfyUI with network access:\n- Add `--listen 0.0.0.0` to listen on all interfaces (default: localhost only).\n- Use default port 8188 (or specify `--port 8188`).\nExample command: `python main.py --listen 0.0.0.0 --port 8188`.\nEnter the server URL as `http://[your-ip]:8188` (find IP via `ifconfig` on macOS or `ipconfig` on Windows).")
               
                Text("2. **Local Network Access**")
                    .font(.headline)
                Text("- **macOS**: Add `com.apple.security.network.client` to your app's entitlements for outbound connections. The system will prompt for Local Network permission if needed.\n- **iOS**: Add `NSLocalNetworkUsageDescription` to Info.plist (e.g., 'This app needs local network access to connect to ComfyUI server.'). iOS will prompt the user on first use.\nEnsure firewall allows port 8188.")
               
                Text("3. **Workflow Loading**")
                    .font(.headline)
                Text("Load a .json or .png workflow file via Browse. The app auto-detects prompt, image, and output nodes. Select them if multiple exist.")
               
                Text("4. **Prompting & Inputs**")
                    .font(.headline)
                Text("- Edit prompts in selected nodes.\n- Upload images to image nodes.\n- Use batch mode for multiple prompts from a .txt file.")
               
                Text("5. **Troubleshooting**")
                    .font(.headline)
                Text("- Connection failed? Check server is running and URL is correct.\n- No nodes detected? Ensure workflow is valid ComfyUI format.\n- Slow generation? Monitor server console for errors.")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
   
    // Added: Help content for Grok mode
    private var grokHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grok Mode Guide")
                .font(.title.bold())
           
            VStack(alignment: .leading, spacing: 12) {
                Text("1. **API Key Setup**")
                    .font(.headline)
                Text("Obtain your API key from console.x.ai. Paste it into the Grok API Key field. Use the 'Test API' button to verify.")
               
                Text("2. **Model Selection**")
                    .font(.headline)
                Text("Choose between available models like 'grok-2-image-1212' (default, based on Flux.1) or 'aurora' for advanced photorealism and text rendering.")
               
                Text("3. **Prompting Tips**")
                    .font(.headline)
                Text("- Be descriptive: Include style, mood, composition (e.g., 'A futuristic cityscape at dusk, cyberpunk style, highly detailed').\n- Use modifiers: Add 'in the style of [artist]' or 'photorealistic'.\n- Experiment with inputs: Grok supports optional image inputs for variations or editing.")
               
                Text("4. **Input Images (Optional)**")
                    .font(.headline)
                Text("Upload an image for image-to-image generation or variations. Annotate with Markup tools if needed.")
               
                Text("5. **Output & History**")
                    .font(.headline)
                Text("- Save or copy generated images directly.\n- View past generations in History for reuse.")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
   
    // New: Help content for AI/ML API mode
    private var aimlHelpContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI/ML API Mode Guide")
                .font(.title.bold())
           
            VStack(alignment: .leading, spacing: 12) {
                Text("1. **API Key Setup**")
                    .font(.headline)
                Text("Sign up at aimlapi.com and obtain your API key from the dashboard. Paste it into the AI/ML API Key field. Use the 'Test API' button to verify connectivity.")
               
                Text("2. **Model Selection**")
                    .font(.headline)
                Text("Click 'Fetch Models' to retrieve available text-to-image (t2i) and image-to-image (i2i) models from the API. Select one from the dropdown, such as Stable Diffusion, Imagen 4, Flux-Pro, DALL·E 2, or Seedream variants for high-quality generation.")
               
                Text("3. **Prompting Tips**")
                    .font(.headline)
                Text("- Be descriptive: Include details on style, mood, composition, and specifics (e.g., 'A photorealistic portrait of a cyberpunk samurai in a neon-lit city, high detail, 4K').\n- For better results: Use modifiers like 'in the style of [artist]', 'photorealistic', or 'cinematic lighting'.\n- Experiment: Some models like Flux-Pro excel in text rendering and complex scenes.")
               
                Text("4. **Input Images (for i2i Models)**")
                    .font(.headline)
                Text("For image-to-image or edit models, upload up to 10 reference images. The app will send them as base64 data. Annotate with Markup tools for precise edits. Ensure the selected model supports i2i (e.g., contains 'edit' or 'i2i' in name).")
               
                Text("5. **Advanced Parameters & Troubleshooting**")
                    .font(.headline)
                Text("- Safety: Enabled by default to filter inappropriate content.\n- Output: Images returned as base64 or URLs; saved automatically.\n- Issues: If generation fails, check API key, model compatibility with inputs, or prompt length (max 4000 chars). Use batch mode for multiple prompts.")
               
                Text("6. **Output & History**")
                    .font(.headline)
                Text("- View, save, or copy generated images.\n- Access past generations in the History sidebar for reuse.")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}
 
struct LoadingView: View {
    let mode: GenerationMode
    let progress: Double
    let isCancelled: Binding<Bool>
    let onStop: () -> Void
 
    var body: some View {
        VStack(spacing: 20) {
            AbstractBloomExpansionLoading()
                .frame(width: 200, height: 100) // Adjust size to fit your UI
 
            if mode == .comfyUI {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView("Generating...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
 
            Button("Stop") {
                isCancelled.wrappedValue = true
                onStop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
//        .background(Color.gray.opacity(0.2))
//        .cornerRadius(12)
    }
}
 
struct SubmitButtonView: View {
    let isDisabled: Bool
    let onSubmit: () -> Void
 
    var body: some View {
        Button("Submit") {
            onSubmit()
        }
        .buttonStyle(.borderedProminent)
        .tint(LinearGradient(gradient: Gradient(colors: [.blue, .indigo]), startPoint: .leading, endPoint: .trailing))
        .disabled(isDisabled)
        .frame(maxWidth: .infinity)
        .padding(.top)
        .keyboardShortcut(.return, modifiers: .command)
        .font(.system(.body, design: .rounded, weight: .medium))
        .shadow(color: .black.opacity(0.1), radius: 1)
    }
}
 
// Helper to check if data is PNG
func isPNGData(_ data: Data) -> Bool {
    guard data.count >= 8 else { return false }
    let signature = data.subdata(in: 0..<8)
    return signature == Data([137, 80, 78, 71, 13, 10, 26, 10])
}
 
// NEW: Helper for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
 
#if os(iOS)
extension View {
    func dynamicHeightPresentation() -> some View {
        modifier(DynamicHeightModifier())
    }
}
 
struct DynamicHeightModifier: ViewModifier {
    @State private var contentHeight: CGFloat = 0
   
    func body(content: Self.Content) -> some View {
        content
            .background(GeometryReader { geo in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: geo.size.height)
            })
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                contentHeight = height
            }
            .presentationDetents([PresentationDetent.height(contentHeight + 60)])  // +60 for padding/title/safe areas; adjust after testing
    }
}
#endif

import SwiftUI
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
    
    var body: some View {
        ZStack(alignment: .topTrailing) {  // Use ZStack for overlay positioning
            VStack(spacing: 0) {
                if let platformImage = appState.ui.outputImage {
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                
                ScrollView {
                    TextEditor(text: .constant(appState.ui.responseText))
                        .frame(height: 80)
                        .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
                        .cornerRadius(12)
                        .disabled(true)
                        .foregroundColor(.primary)
                }
                .frame(height: 80)
            }
            
            // Add X close button at upper right
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
            updateWindowSize()
        }
        .onChange(of: appState.ui.outputImage) { _ in
            updateWindowSize()
        }
    }
    
    private func updateWindowSize() {
        #if os(macOS)
        if let platformImage = appState.ui.outputImage, let window = NSApp.windows.last {
            let textHeight: CGFloat = 80
            let size = CGSize(width: max(platformImage.platformSize.width, 400), height: platformImage.platformSize.height + textHeight)
            window.setContentSize(size)
        }
        #endif
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
                    if mode == .gemini {
                        geminiHelpContent
                    } else {
                        comfyUIHelpContent
                    }
                }
                .padding()
            }
            .navigationTitle(mode == .gemini ? "Gemini Help" : "ComfyUI Help")
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
            Text(mode == .gemini ? "Gemini Help" : "ComfyUI Help")
                .font(.title)
                .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if mode == .gemini {
                        geminiHelpContent
                    } else {
                        comfyUIHelpContent
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
}

struct FullImageView: View {
    let image: PlatformImage
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            ScrollView {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
            }
            
            HStack {
                Button(action: {
                    PlatformPasteboard.clearContents()
                    PlatformPasteboard.writeImage(image)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy to Clipboard")
                
                Button(action: {
                    #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.png]
                    panel.nameFieldStringValue = "generated_image.png"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        if let pngData = image.platformPngData() {
                            try? pngData.write(to: url)
                        }
                    }
                    #elseif os(iOS)
                    PHPhotoLibrary.requestAuthorization { status in
                        if status == .authorized {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        }
                    }
                    #endif
                }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save Image")
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                }
                .help("Close")
            }
        }
        .frame(width: image.platformSize.width, height: image.platformSize.height + 50)
        .padding()
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
                .frame(width: 200, height: 200) // Adjust size to fit your UI

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

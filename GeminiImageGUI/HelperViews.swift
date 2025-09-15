//HelperViews.swift
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
    
    var body: some View {
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
        VStack(spacing: 20) {
            Text("Welcome to Gemini Image App")
                .font(.title.bold())
            
            Text("This app allows you to generate images using the Gemini API or ComfyUI.")
                .multilineTextAlignment(.center)
            
            Text("Steps:\n1. Select mode (Gemini or ComfyUI).\n2. Enter API key or ComfyUI server details.\n3. Write a prompt.\n4. Add input images if needed.\n5. Submit to generate.")
                .multilineTextAlignment(.leading)
            
            Button("Get Started") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 400, height: 300)
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
                Button("Copy to Clipboard") {
                    PlatformPasteboard.clearContents()
                    PlatformPasteboard.writeImage(image)
                }
                .buttonStyle(.bordered)
                
                Button("Save As...") {
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
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
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

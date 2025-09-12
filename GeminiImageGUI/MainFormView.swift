//  MainFormView.swift
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

    @EnvironmentObject var appState: AppState

    var isSubmitDisabled: Bool {
        if appState.settings.mode == .gemini {
            return appState.settings.apiKey.isEmpty || prompt.isEmpty
        } else {
            return appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty || prompt.isEmpty
        }
    }

    var body: some View {
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
            
            DisclosureGroup("Prompt", isExpanded: $promptExpanded) {
                PromptSection(prompt: $prompt)
            }
            .font(.system(.headline, design: .default, weight: .semibold))
            .kerning(0.2)
            .foregroundColor(.primary)
            
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
                    SubmitButtonView(isDisabled: isSubmitDisabled, onSubmit: onSubmit)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 50) // Or higher, e.g., 60, to make it taller/larger overall
                        .padding(.vertical, 8) // Keeps the tightened space above/below
                        .font(.system(size: 30, weight: .medium))
                }
            }
            .padding(.vertical, -12) // More negative padding to halve the empty space above/below (from ~32pt effective to ~16pt)
            .offset(y: -5) // Moves the entire group (including the button) up by 5 points/pixels

            
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
    }
}

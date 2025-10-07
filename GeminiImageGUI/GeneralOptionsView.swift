// GeneralOptionsView.swift
import SwiftUI

struct GeneralOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    private var allowsBase64: Bool {
        switch appState.settings.mode {
        case .gemini:
            return true
        case .aimlapi:
            if let model = appState.currentAIMLModel {
                return model.acceptsBase64
            }
            return true
        default:
            return true
        }
    }
    
    private var allowsImgBB: Bool {
        switch appState.settings.mode {
        case .gemini:
            return false
        case .aimlapi:
            if let model = appState.currentAIMLModel {
                return model.acceptsPublicURL
            }
            return true
        default:
            return true
        }
    }
    
    private func updateSelection() {
        let current = appState.settings.imageSubmissionMethod
        if (current == .base64 && !allowsBase64) || (current == .imgBB && !allowsImgBB) {
            appState.settings.imageSubmissionMethod = allowsBase64 ? .base64 : (allowsImgBB ? .imgBB : .base64)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        methodRow(method: .base64, title: "Base64 Payload (Private)", disabled: !allowsBase64)
                        methodRow(method: .imgBB, title: "ImgBB Links (Public URLs)", disabled: !allowsImgBB)
                    }
                } header: {
                    Text("Image Submission Method")
                } footer: {
                    Text("Choose how to send input images to APIs. Base64 is more private but may increase request size.")
                }
                
                if appState.settings.imageSubmissionMethod == .base64 {
                    Section {
                        Toggle("Convert to JPEG (lossy compression)", isOn: $appState.settings.base64ConvertToJPG)
                        Toggle("Scale Down by 50% (halves dimensions)", isOn: $appState.settings.base64Scale50Percent)
                    } header: {
                        Text("Base64 Optimizations")
                    } footer: {
                        Text("Reduce payload size for large images.")
                    }
                }

            }
            .formStyle(.grouped)
            .navigationTitle("General Options")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                updateSelection()
            }
            .onChange(of: appState.settings.mode) { _ in
                updateSelection()
            }
            .onChange(of: appState.settings.selectedAIMLModel) { _ in
                updateSelection()
            }
        }
    }
    
    @ViewBuilder
    private func methodRow(method: ImageSubmissionMethod, title: String, disabled: Bool) -> some View {
        HStack {
            Image(systemName: appState.settings.imageSubmissionMethod == method ? "circle.fill" : "circle")
                .foregroundColor(disabled ? .gray : .accentColor)
            Text(title)
        }
        .foregroundColor(disabled ? .gray : .primary)
        .contentShape(Rectangle())
        .onTapGesture {
            if !disabled {
                appState.settings.imageSubmissionMethod = method
            }
        }
    }
}


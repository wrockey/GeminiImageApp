// GeneralOptionsView.swift
import SwiftUI

struct GeneralOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $appState.settings.imageSubmissionMethod) {
                        Text("ImgBB Links (Public URLs)").tag(ImageSubmissionMethod.imgBB)
                        Text("Base64 Payload (Private)").tag(ImageSubmissionMethod.base64)
                    }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.inline)
                #endif
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
        }

    }
}

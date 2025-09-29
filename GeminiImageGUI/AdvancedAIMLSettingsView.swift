//  AdvancedAIMLSettingsView.swift
import SwiftUI

struct AdvancedAIMLSettingsView: View {
    let model: AIMLModel
    @Binding var params: ModelParameters
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                if model.supportedParams.contains(.strength) {
                    Section(header: Text("Strength (0-1)")) {
                        Slider(value: Binding(
                            get: { params.strength ?? 0.8 },
                            set: { params.strength = $0 }
                        ), in: 0...1, step: 0.05)
                    }
                }
                if model.supportedParams.contains(.numInferenceSteps) {
                    Section(header: Text("Inference Steps (1-100)")) {
                        Stepper(value: Binding(
                            get: { params.numInferenceSteps ?? 50 },
                            set: { params.numInferenceSteps = $0 }
                        ), in: 1...100) {
                            Text("\(params.numInferenceSteps ?? 50)")
                        }
                    }
                }
                if model.supportedParams.contains(.guidanceScale) {
                    Section(header: Text("Guidance Scale (1-20)")) {
                        Slider(value: Binding(
                            get: { params.guidanceScale ?? 7.5 },
                            set: { params.guidanceScale = $0 }
                        ), in: 1...20, step: 0.5)
                    }
                }
                if model.supportedParams.contains(.negativePrompt) {
                    Section(header: Text("Negative Prompt")) {
                        TextEditor(text: Binding(
                            get: { params.negativePrompt ?? "" },
                            set: { params.negativePrompt = $0 }
                        ))
                        .frame(height: 100)
                    }
                }
                if model.supportedParams.contains(.seed) {
                    Section(header: Text("Seed")) {
                        TextField("Random if empty", value: $params.seed, format: .number)
                    }
                }
                if model.supportedParams.contains(.numImages) {
                    Section(header: Text("Number of Images (1-4)")) {
                        Stepper(value: Binding(
                            get: { params.numImages ?? 1 },
                            set: { params.numImages = $0 }
                        ), in: 1...4) {
                            Text("\(params.numImages ?? 1)")
                        }
                    }
                }
                if model.supportedParams.contains(.enhancePrompt) {
                                    Section(header: Text("Enhance Prompt")) {
                                        Toggle("Enable Prompt Enhancement", isOn: Binding(
                                            get: { params.enhancePrompt ?? true },
                                            set: { params.enhancePrompt = $0 }
                                        ))
                                        .help("Use LLM to rewrite prompt for better quality (default: on)")
                                    }
                                }
                if model.supportedParams.contains(.enableSafetyChecker) {
                    Section(header: Text("Safety Checker")) {
                        Toggle("Enable", isOn: Binding(
                            get: { params.enableSafetyChecker ?? true },
                            set: { params.enableSafetyChecker = $0 }
                        ))
                    }
                }
                if model.supportedParams.contains(.watermark) {
                    Section(header: Text("Watermark")) {
                        Toggle("Enable Watermark", isOn: Binding(
                            get: { params.watermark ?? false },
                            set: { params.watermark = $0 }
                        ))
                    }
                }
                // Add sections for other params as needed
            }
            .navigationTitle("Advanced Settings for \(model.id)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dismiss()}
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }
}

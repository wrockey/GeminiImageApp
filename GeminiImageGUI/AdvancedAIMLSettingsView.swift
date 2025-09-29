import SwiftUI

struct AdvancedAIMLSettingsView: View {
    let model: AIMLModel
    @Binding var params: ModelParameters
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        #if os(iOS)
#if os(iOS)
        NavigationStack {
            Form {
                parameterSections
            }
            .padding(.vertical)
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.blue)
                }
            }
        }
#endif
        #elseif os(macOS)
        VStack {
            ScrollView {
                Form {
                    parameterSections
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .navigationTitle("Advanced Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 600, idealHeight: 700)
        .fixedSize() // Prevents any resizing
        #endif
    }
    
    @ViewBuilder
    private var parameterSections: some View {
        if model.supportedParams.contains(.strength) {
            Section {
                HStack {
                    Slider(value: Binding(
                        get: { params.strength ?? 0.8 },
                        set: { params.strength = $0 }
                    ), in: 0...1, step: 0.05) {
                        Text("Strength")
                    }
                    .help("Controls how much the output deviates from the input image (0: minimal change, 1: maximum transformation)")
                    .accessibilityLabel("Strength slider")
                    .accessibilityValue("\(String(format: "%.2f", params.strength ?? 0.8))")
                    
                    Text(String(format: "%.2f", params.strength ?? 0.8))
                        .frame(width: 50)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Strength")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.numInferenceSteps) {
            Section {
                Stepper(value: Binding(
                    get: { params.numInferenceSteps ?? 50 },
                    set: { params.numInferenceSteps = $0 }
                ), in: 1...100) {
                    Text("\(params.numInferenceSteps ?? 50)")
                        .help("Number of denoising steps; higher values improve quality but increase generation time")
                        .accessibilityLabel("Inference Steps stepper")
                        .accessibilityValue("\(params.numInferenceSteps ?? 50) steps")
                }
                .padding(.vertical, 8)
            } header: {
                Text("Inference Steps")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.guidanceScale) {
            Section {
                HStack {
                    Slider(value: Binding(
                        get: { params.guidanceScale ?? 7.5 },
                        set: { params.guidanceScale = $0 }
                    ), in: 1...20, step: 0.5) {
                        Text("Guidance")
                    }
                    .help("How closely the model follows the prompt; higher values make output more prompt-adherent but may reduce diversity")
                    .accessibilityLabel("Guidance Scale slider")
                    .accessibilityValue("\(String(format: "%.1f", params.guidanceScale ?? 7.5))")
                    
                    Text(String(format: "%.1f", params.guidanceScale ?? 7.5))
                        .frame(width: 50)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Guidance Scale")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.negativePrompt) {
            Section {
                TextEditor(text: Binding(
                    get: { params.negativePrompt ?? "" },
                    set: { params.negativePrompt = $0 }
                ))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .help("Describe elements to avoid in the generated image (e.g., 'blurry, dark, crowded')")
                .accessibilityLabel("Negative Prompt editor")
                .padding(.vertical, 8)
            } header: {
                Text("Negative Prompt")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.seed) {
            Section {
                TextField("Random if empty", value: $params.seed, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .help("Fixed seed for reproducible results; leave empty for random")
                    .accessibilityLabel("Seed input")
                    .padding(.vertical, 8)
            } header: {
                Text("Seed")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.numImages) {
            Section {
                Stepper(value: Binding(
                    get: { params.numImages ?? 1 },
                    set: { params.numImages = $0 }
                ), in: 1...4) {
                    Text("\(params.numImages ?? 1)")
                        .help("Number of images to generate per prompt (1-4)")
                        .accessibilityLabel("Number of Images stepper")
                        .accessibilityValue("\(params.numImages ?? 1) images")
                }
                .padding(.vertical, 8)
            } header: {
                Text("Number of Images")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.enableSafetyChecker) {
            Section {
                Toggle("Enable Safety Checker", isOn: Binding(
                    get: { params.enableSafetyChecker ?? true },
                    set: { params.enableSafetyChecker = $0 }
                ))
                .help("Filter out potentially inappropriate content")
                .accessibilityLabel("Safety Checker toggle")
                .padding(.vertical, 8)
            } header: {
                Text("Safety Checker")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.watermark) {
            Section {
                Toggle("Enable Watermark", isOn: Binding(
                    get: { params.watermark ?? false },
                    set: { params.watermark = $0 }
                ))
                .help("Add a watermark to generated images")
                .accessibilityLabel("Watermark toggle")
                .padding(.vertical, 8)
            } header: {
                Text("Watermark")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        
        if model.supportedParams.contains(.enhancePrompt) {
            Section {
                Toggle("Enable Prompt Enhancement", isOn: Binding(
                    get: { params.enhancePrompt ?? true },
                    set: { params.enhancePrompt = $0 }
                ))
                .help("Automatically refine the prompt using an LLM for better results")
                .accessibilityLabel("Prompt Enhancement toggle")
                .padding(.vertical, 8)
            } header: {
                Text("Prompt Enhancement")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

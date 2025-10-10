import SwiftUI

struct AdvancedAIMLSettingsView: View {
    let model: AIMLModel
    @Binding var params: ModelParameters
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
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
        .fixedSize()
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
                .help("Describe elements to avoid in the generated content (e.g., 'blurry, dark, crowded')")
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
                .help("Add a watermark to generated content")
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
        
        if model.isVideo {
            Section {
                if model.supportedParams.contains(.duration) {
                    Stepper(value: Binding(
                        get: { params.duration ?? 5 },
                        set: { params.duration = $0 }
                    ), in: 1...20, step: 1) {
                        Text("\(params.duration ?? 5) seconds")
                            .help("Duration of the generated video (1-20 seconds)")
                            .accessibilityLabel("Duration stepper")
                            .accessibilityValue("\(params.duration ?? 5) seconds")
                    }
                    .padding(.vertical, 8)
                }
                
                if model.supportedParams.contains(.aspectRatio) {
                    Picker("Aspect Ratio", selection: Binding(
                        get: { params.aspectRatio ?? "16:9" },
                        set: { params.aspectRatio = $0 }
                    )) {
                        Text("16:9").tag("16:9")
                        Text("9:16").tag("9:16")
                        Text("4:3").tag("4:3")
                        Text("1:1").tag("1:1")
                    }
                    .pickerStyle(.menu)
                    .help("Select the aspect ratio for the video")
                    .accessibilityLabel("Aspect Ratio picker")
                    .padding(.vertical, 8)
                }
                
                if model.supportedParams.contains(.frameRate) {
                    Picker("Frame Rate", selection: Binding(
                        get: { params.frameRate ?? 30 },
                        set: { params.frameRate = $0 }
                    )) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.menu)
                    .help("Select the frame rate for the video (frames per second)")
                    .accessibilityLabel("Frame Rate picker")
                    .padding(.vertical, 8)
                }
                
                if model.supportedParams.contains(.stylePreset) {
                    Picker("Style Preset", selection: Binding(
                        get: { params.stylePreset ?? "realistic" },
                        set: { params.stylePreset = $0 }
                    )) {
                        Text("Realistic").tag("realistic")
                        Text("Anime").tag("anime")
                        Text("Cinematic").tag("cinematic")
                        Text("3D Animation").tag("3d_animation")
                    }
                    .pickerStyle(.menu)
                    .help("Select the stylistic preset for the video")
                    .accessibilityLabel("Style Preset picker")
                    .padding(.vertical, 8)
                }
                
                if model.supportedParams.contains(.cameraControl) {
                    TextEditor(text: Binding(
                        get: { params.cameraControl ?? "{\"pan\": \"none\", \"tilt\": \"none\", \"zoom\": \"none\"}" },
                        set: { params.cameraControl = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .help("JSON-like camera controls (e.g., {\"pan\": \"left\", \"tilt\": \"up\", \"zoom\": \"in\"})")
                    .accessibilityLabel("Camera Control editor")
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Video Parameters")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
}

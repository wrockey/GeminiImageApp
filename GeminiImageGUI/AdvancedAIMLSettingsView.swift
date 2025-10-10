import SwiftUI

struct AdvancedAIMLSettingsView: View {
    let model: AIMLModel
    @Binding var params: ModelParameters
    @Environment(\.dismiss) var dismiss
    
    // State for camera controls
    @State private var selectedControls: Set<String> = []
    @State private var panDirection: String = "none"
    @State private var tiltDirection: String = "none"
    @State private var zoomDirection: String = "none"
    @State private var rollDirection: String = "none"
    @State private var dollyDirection: String = "none"
    @State private var trackDirection: String = "none"
    @State private var otherControl: String = ""
    @State private var showCameraHelp: Bool = false
    
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
            .sheet(isPresented: $showCameraHelp) {
                CameraControlHelpView(modelId: model.id)
            }
            .onAppear {
                parseCameraControl()
            }
            .onChange(of: selectedControls) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: panDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: tiltDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: zoomDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: rollDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: dollyDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: trackDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: otherControl) { _ in
                updateCameraControlJSON()
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
            .sheet(isPresented: $showCameraHelp) {
                CameraControlHelpView(modelId: model.id)
            }
            .onAppear {
                parseCameraControl()
            }
            .onChange(of: selectedControls) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: panDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: tiltDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: zoomDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: rollDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: dollyDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: trackDirection) { _ in
                updateCameraControlJSON()
            }
            .onChange(of: otherControl) { _ in
                updateCameraControlJSON()
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
                    Section {
                        Toggle("Pan", isOn: Binding(
                            get: { selectedControls.contains("pan") },
                            set: { if $0 { selectedControls.insert("pan") } else { selectedControls.remove("pan") } }
                        ))
                        .help("Enable pan (horizontal movement)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("pan") {
                            Picker("Direction", selection: $panDirection) {
                                Text("None").tag("none")
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                            .help("Select pan direction")
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Tilt", isOn: Binding(
                            get: { selectedControls.contains("tilt") },
                            set: { if $0 { selectedControls.insert("tilt") } else { selectedControls.remove("tilt") } }
                        ))
                        .help("Enable tilt (vertical movement)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("tilt") {
                            Picker("Direction", selection: $tiltDirection) {
                                Text("None").tag("none")
                                Text("Up").tag("up")
                                Text("Down").tag("down")
                            }
                            .pickerStyle(.segmented)
                            .help("Select tilt direction")
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Zoom", isOn: Binding(
                            get: { selectedControls.contains("zoom") },
                            set: { if $0 { selectedControls.insert("zoom") } else { selectedControls.remove("zoom") } }
                        ))
                        .help("Enable zoom (in/out movement)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("zoom") {
                            Picker("Direction", selection: $zoomDirection) {
                                Text("None").tag("none")
                                Text("In").tag("in")
                                Text("Out").tag("out")
                            }
                            .pickerStyle(.segmented)
                            .help("Select zoom direction")
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Roll", isOn: Binding(
                            get: { selectedControls.contains("roll") },
                            set: { if $0 { selectedControls.insert("roll") } else { selectedControls.remove("roll") } }
                        ))
                        .help("Enable roll (rotation around z-axis)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("roll") {
                            Picker("Direction", selection: $rollDirection) {
                                Text("None").tag("none")
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                            .help("Select roll direction")
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Dolly", isOn: Binding(
                            get: { selectedControls.contains("dolly") },
                            set: { if $0 { selectedControls.insert("dolly") } else { selectedControls.remove("dolly") } }
                        ))
                        .help("Enable dolly (forward/back movement)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("dolly") {
                            Picker("Direction", selection: $dollyDirection) {
                                Text("None").tag("none")
                                Text("Forward").tag("forward")
                                Text("Back").tag("back")
                            }
                            .pickerStyle(.segmented)
                            .help("Select dolly direction")
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Track", isOn: Binding(
                            get: { selectedControls.contains("track") },
                            set: { if $0 { selectedControls.insert("track") } else { selectedControls.remove("track") } }
                        ))
                        .help("Enable track (side-to-side movement)")
                        .padding(.vertical, 4)
                        if selectedControls.contains("track") {
                            Picker("Direction", selection: $trackDirection) {
                                Text("None").tag("none")
                                Text("Left").tag("left")
                                Text("Right").tag("right")
                            }
                            .pickerStyle(.segmented)
                            .help("Select track direction")
                            .padding(.leading, 20)
                        }
                        
                        TextField("Other (custom JSON, e.g., {\"fly_over\": \"forward\"})", text: $otherControl)
                            .textFieldStyle(.roundedBorder)
                            .help("Enter additional custom camera controls as JSON")
                            .accessibilityLabel("Other camera control input")
                            .padding(.vertical, 8)
                    } header: {
                        HStack {
                            Text("Camera Controls")
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Button(action: {
                                showCameraHelp = true
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Show camera control help")
                            .accessibilityLabel("Camera control help")
                        }
                        .padding(.bottom, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                Text("Video Parameters")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }
    
    // Parse existing cameraControl JSON into state
    private func parseCameraControl() {
        guard let jsonString = params.cameraControl, let data = jsonString.data(using: .utf8) else { return }
        do {
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                for (key, value) in dict {
                    switch key.lowercased() {
                    case "pan":
                        selectedControls.insert("pan")
                        panDirection = value
                    case "tilt":
                        selectedControls.insert("tilt")
                        tiltDirection = value
                    case "zoom":
                        selectedControls.insert("zoom")
                        zoomDirection = value
                    case "roll":
                        selectedControls.insert("roll")
                        rollDirection = value
                    case "dolly":
                        selectedControls.insert("dolly")
                        dollyDirection = value
                    case "track":
                        selectedControls.insert("track")
                        trackDirection = value
                    default:
                        otherControl = "\"\(key)\": \"\(value)\""
                    }
                }
            }
        } catch {
            otherControl = jsonString // Fallback to Other if not valid JSON
        }
    }
    
    // Update params.cameraControl with JSON from selections
    private func updateCameraControlJSON() {
        var jsonDict: [String: String] = [:]
        
        if selectedControls.contains("pan") && panDirection != "none" {
            jsonDict["pan"] = panDirection
        }
        if selectedControls.contains("tilt") && tiltDirection != "none" {
            jsonDict["tilt"] = tiltDirection
        }
        if selectedControls.contains("zoom") && zoomDirection != "none" {
            jsonDict["zoom"] = zoomDirection
        }
        if selectedControls.contains("roll") && rollDirection != "none" {
            jsonDict["roll"] = rollDirection
        }
        if selectedControls.contains("dolly") && dollyDirection != "none" {
            jsonDict["dolly"] = dollyDirection
        }
        if selectedControls.contains("track") && trackDirection != "none" {
            jsonDict["track"] = trackDirection
        }
        
        if !otherControl.isEmpty {
            if let otherData = otherControl.data(using: .utf8), let otherDict = try? JSONSerialization.jsonObject(with: otherData) as? [String: String] {
                jsonDict.merge(otherDict) { (_, new) in new }
            }
        }
        
        if jsonDict.isEmpty {
            params.cameraControl = nil
        } else {
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted]), let jsonString = String(data: jsonData, encoding: .utf8) {
                params.cameraControl = jsonString
            }
        }
    }
}

struct CameraControlHelpView: View {
    let modelId: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                let info = CameraControlInfo.infoForModel(id: modelId)
                
                Text("Camera Control Help")
                    .font(.title2)
                    .bold()
                    .padding(.bottom, 4)
                
                Text(info.description)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text("Supported Controls:")
                    .font(.headline)
                    .padding(.top, 8)
                
                ForEach(info.supportedControls, id: \.self) { control in
                    Text("• \(control)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Text("Format:")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text(info.format)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding()
            #if os (macOS)
            .navigationTitle("Camera Control Help")
            #endif
            #if os (iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.blue)
                }
            }
        }
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 400, minHeight: 300, idealHeight: 400, maxHeight: 500)
    }
}

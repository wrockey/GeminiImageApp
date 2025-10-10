import Foundation

struct ModelParameters: Codable {
    var strength: Double? = 0.8
    var numInferenceSteps: Int? = 50
    var guidanceScale: Double? = 7.5
    var negativePrompt: String? = ""
    var seed: Int?
    var numImages: Int? = 1
    var enableSafetyChecker: Bool? = true
    var watermark: Bool? = false
    var enhancePrompt: Bool? = true
    var duration: Int? = 5
    var aspectRatio: String? = "16:9"
    var cameraControl: String? // JSON-like string for camera params (e.g., {"pan": "left"})
    var frameRate: Int? = 30 // Default 30fps for video models
    var stylePreset: String? // Optional style preset (e.g., "anime", "realistic")

    enum CodingKeys: String, CodingKey {
        case strength
        case numInferenceSteps = "num_inference_steps"
        case guidanceScale = "guidance_scale"
        case negativePrompt = "negative_prompt"
        case seed
        case numImages = "num_images"
        case enableSafetyChecker = "enable_safety_checker"
        case watermark
        case enhancePrompt = "enhance_prompt"
        case duration
        case aspectRatio = "aspect_ratio"
        case cameraControl = "camera_control"
        case frameRate = "frame_rate"
        case stylePreset = "style_preset"
    }
}

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
    var duration: Int? = 5 // Default for video models (5 seconds)
    var aspectRatio: String? = "16:9" // Default for video models
    var cameraControl: String? // Optional JSON-like string for camera params (e.g., {"pan": "left"})

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
    }
}

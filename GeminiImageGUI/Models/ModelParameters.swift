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
    // Add more model-specific defaults as needed
}

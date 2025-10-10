import Foundation

struct AIMLModel {
    let id: String
    let isI2I: Bool
    let maxInputImages: Int
    let supportedParams: Set<AIMLParam>
    let supportsCustomResolution: Bool
    let defaultImageSize: String
    let imageInputParam: String
    let acceptsMultiImages: Bool
    let acceptsBase64: Bool
    let acceptsPublicURL: Bool
    let maxWidth: Int?  // Nil if no limit or enum-only
    let maxHeight: Int?  // Nil if no limit or enum-only
    var isVideo: Bool
}

enum AIMLParam: String, CaseIterable, Hashable {
    case strength
    case numInferenceSteps
    case guidanceScale
    case negativePrompt
    case seed
    case numImages
    case enableSafetyChecker
    case watermark
    case enhancePrompt  // New: For prompt enhancement in Google Imagen models
    case duration
    case aspectRatio
    // Add more as needed
}

struct ModelRegistry {
    static func modelFor(id: String) -> AIMLModel? {
        let lowerID = id.lowercased()
        switch lowerID {
        case "alibaba/qwen-image-edit":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 1,
                supportedParams: [.negativePrompt, .watermark],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "image",
                acceptsMultiImages: false,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "bytedance/uso":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 3,
                supportedParams: [.strength, .negativePrompt, .numInferenceSteps, .guidanceScale],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "image_urls",
                acceptsMultiImages: true,
                acceptsBase64: false,
                acceptsPublicURL: true,
                maxWidth: 1440,
                maxHeight: 1440,
                isVideo: false
            )
        case "flux/srpo/image-to-image":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 1,
                supportedParams: [.strength, .numInferenceSteps, .guidanceScale],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "image_url",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: true,
                maxWidth: 1440,
                maxHeight: 1440,
                isVideo: false
            )
        case "flux/kontext-pro/image-to-image":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 4,
                supportedParams: [.strength, .numInferenceSteps, .guidanceScale],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "image_url",
                acceptsMultiImages: true,
                acceptsBase64: false,
                acceptsPublicURL: true,
                maxWidth: 1440,
                maxHeight: 1440,
                isVideo: false
            )
        case "openai/gpt-image-1":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 16,
                supportedParams: [.strength, .negativePrompt],
                supportsCustomResolution: false,
                defaultImageSize: "square",
                imageInputParam: "image_urls",
                acceptsMultiImages: true,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "stability/stable-diffusion-v3-medium":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 1,
                supportedParams: [.negativePrompt, .numInferenceSteps, .guidanceScale],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "image_urls",
                acceptsMultiImages: false,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: 1536,
                maxHeight: 1536,
                isVideo: false
            )
        case "flux-pro":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [.numInferenceSteps],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: true,
                maxWidth: 1440,
                maxHeight: 1440,
                isVideo: false
            )
        case "dall-e-2":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [],
                supportsCustomResolution: false,
                defaultImageSize: "1024x1024",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: false,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "imagen-4.0-generate-001", "google/imagen-4.0-generate-001":
                    return AIMLModel(
                        id: id,
                        isI2I: false,
                        maxInputImages: 0,
                        supportedParams: [.enhancePrompt, .numImages, .enableSafetyChecker],
                        supportsCustomResolution: false,
                        defaultImageSize: "1:1",
                        imageInputParam: "",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: false,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: false
                    )
        case "recraft-v3":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: false,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "flux/dev":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: true,
                maxWidth: 1440,
                maxHeight: 1440,
                isVideo: false
            )
        case "imagen-4.0-fast-generate-001":
                    return AIMLModel(
                        id: id,
                        isI2I: false,
                        maxInputImages: 0,
                        supportedParams: [.enhancePrompt, .numImages, .enableSafetyChecker],
                        supportsCustomResolution: false,
                        defaultImageSize: "1:1",
                        imageInputParam: "",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: false,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: false
                    )
        case "imagen-4-ultra-generate-preview-06-06":
                    return AIMLModel(
                        id: id,
                        isI2I: false,
                        maxInputImages: 0,
                        supportedParams: [.enhancePrompt, .numImages, .enableSafetyChecker],
                        supportsCustomResolution: false,
                        defaultImageSize: "1:1",
                        imageInputParam: "",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: false,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: false
                    )
        case "google/gemini-2.5-flash-image":
                    return AIMLModel(
                        id: id,
                        isI2I: false,
                        maxInputImages: 0,
                        supportedParams: [.numImages, .enableSafetyChecker],
                        supportsCustomResolution: false,
                        defaultImageSize: "Square HD",
                        imageInputParam: "",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: false,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: false
                    )
                case "google/gemini-2.5-flash-image-edit":
                    return AIMLModel(
                        id: id,
                        isI2I: true,
                        maxInputImages: 10,
                        supportedParams: [.numImages, .enableSafetyChecker],
                        supportsCustomResolution: false,
                        defaultImageSize: "square_hd",
                        imageInputParam: "image_urls",
                        acceptsMultiImages: true,
                        acceptsBase64: true,
                        acceptsPublicURL: true,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: false
                    )
        case "reve/edit-image":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 1,
                supportedParams: [.enableSafetyChecker],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "image",
                acceptsMultiImages: false,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "bytedance/seedream-v4-text-to-image":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [.seed, .numImages, .enableSafetyChecker],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: false,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "bytedance/seedream-v4-edit":
            return AIMLModel(
                id: id,
                isI2I: true,
                maxInputImages: 10,  // Array of URLs/base64
                supportedParams: [.seed, .numImages, .enableSafetyChecker],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "image_urls",
                acceptsMultiImages: true,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        case "klingai/v2.1-master-text-to-video":
                    return AIMLModel(
                        id: id,
                        isI2I: false,
                        maxInputImages: 0,
                        supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio],
                        supportsCustomResolution: false,
                        defaultImageSize: "16:9",
                        imageInputParam: "",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: false,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: true
                    ) // isVideo: true - assume added
                case "klingai/v2.1-standard/image-to-video":
                    return AIMLModel(
                        id: id,
                        isI2I: true,
                        maxInputImages: 1,
                        supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio],
                        supportsCustomResolution: false,
                        defaultImageSize: "16:9",
                        imageInputParam: "image_url",
                        acceptsMultiImages: false,
                        acceptsBase64: false,
                        acceptsPublicURL: true,
                        maxWidth: nil,
                        maxHeight: nil,
                        isVideo: true
                    )
        // Add more as needed
        default:
            return AIMLModel(
                id: id,
                isI2I: lowerID.contains("edit") || lowerID.contains("image-to-image"),
                maxInputImages: 1,
                supportedParams: [.numInferenceSteps, .guidanceScale, .negativePrompt, .seed, .numImages, .enableSafetyChecker],
                supportsCustomResolution: true,
                defaultImageSize: "1024x1024",
                imageInputParam: "image_urls",
                acceptsMultiImages: false,
                acceptsBase64: true,
                acceptsPublicURL: true,
                maxWidth: nil,
                maxHeight: nil,
                isVideo: false
            )
        }
    }
}




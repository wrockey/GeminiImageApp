// ModelRegistry.swift
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
    case enhancePrompt
    case duration
    case aspectRatio
    case cameraControl  // New: For video camera params (pan/tilt/etc.)
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
            // Video Models (new/updated)
                    case "minimax/video-01":
                        return AIMLModel(
                            id: id,
                            isI2I: true,  // Supports first-frame image
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "first_frame_image",
                            acceptsMultiImages: false,
                            acceptsBase64: true,
                            acceptsPublicURL: true,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "minimax/hailuo-02":
                        return AIMLModel(
                            id: id,
                            isI2I: true,  // Supports image as first frame
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .enhancePrompt],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "first_frame_image",
                            acceptsMultiImages: false,
                            acceptsBase64: true,
                            acceptsPublicURL: true,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "klingai/v1-standard/text-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: false,
                            maxInputImages: 0,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "",
                            acceptsMultiImages: false,
                            acceptsBase64: false,
                            acceptsPublicURL: false,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "klingai/v1-pro/text-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: false,
                            maxInputImages: 0,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "",
                            acceptsMultiImages: false,
                            acceptsBase64: false,
                            acceptsPublicURL: false,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "klingai/v1-standard/image-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
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
                    case "klingai/v1-pro/image-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 2,  // Supports multi-image in some cases
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "image_url",
                            acceptsMultiImages: true,
                            acceptsBase64: false,
                            acceptsPublicURL: true,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "klingai/v1.6-standard/image-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
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
                    case "klingai/v1.6-pro/image-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
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
                    case "bytedance/seedance-1-0-lite-t2v":
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
                        )
                    case "bytedance/seedance-1-0-lite-i2v":
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
                    case "bytedance/seedance-1-0-pro-t2v":
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
                        )
                    case "bytedance/seedance-1-0-pro-i2v":
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
                    case "bytedance/omnihuman":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 2,  // Multi-image for avatars
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio],
                            supportsCustomResolution: false,
                            defaultImageSize: "16:9",
                            imageInputParam: "image_url",
                            acceptsMultiImages: true,
                            acceptsBase64: false,
                            acceptsPublicURL: true,
                            maxWidth: nil,
                            maxHeight: nil,
                            isVideo: true
                        )
                    case "google/veo2/image-to-video":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
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
                    case "google/veo-3.0-i2v":
                        return AIMLModel(
                            id: id,
                            isI2I: true,
                            maxInputImages: 1,
                            supportedParams: [.negativePrompt, .guidanceScale, .duration, .aspectRatio, .cameraControl],
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
                    case "openai/sora-2-text-to-video":
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
                        )
                    case "openai/sora-2-i2v":
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
                    case "runway/gen3a_turbo":
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
                    case "pixverse/v5/image-to-video":
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
                    case "alibaba/wan-2.1-plus":
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
                        )
                    // Add similar cases for other Alibaba Wan variants (wan-2.1-turbo, wan-2.2-plus, wan-2.5-preview, wan-2.5-preview-i2v)...
                    // For wan-2.5-preview-i2v: set isI2I: true, etc.
                    
                    // Existing Kling v2.1 (deprecated; kept for backward compat, but use v1.6 above)
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
                        )
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




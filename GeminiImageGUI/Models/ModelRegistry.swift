import Foundation

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
                acceptsPublicURL: true
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
                acceptsPublicURL: true
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
                acceptsPublicURL: true
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
                acceptsPublicURL: true
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
                acceptsPublicURL: true
            )
        case "stability/stable-diffusion-v3.5-large":
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
                acceptsPublicURL: true
            )
        // Add from your hard-coded supportingModels if needed, e.g.
        case "bytedance/seedream-v4-text-to-image", "bytedance/seedream-v4-edit", "black-forest-labs/flux-pro", "black-forest-labs/flux-realism":
            return AIMLModel(
                id: id,
                isI2I: lowerID.contains("edit") || lowerID.contains("image-to-image"),
                maxInputImages: lowerID.contains("edit") ? 10 : 0,  // i2i max 10
                supportedParams: [.seed, .numImages, .enableSafetyChecker],  // Only these for Seedream v4 variants; no guidance/strength/steps/negative
                supportsCustomResolution: false,  // Enum-based image_size
                defaultImageSize: "square_hd",
                imageInputParam: "image_urls",
                acceptsMultiImages: lowerID.contains("edit"),
                acceptsBase64: true,
                acceptsPublicURL: true
            )
        case "reve/edit-image", "reve/remix-edit-image":
            return AIMLModel(
                id: "reve/edit-image",  // Correct valid ID
                isI2I: true,
                maxInputImages: 1,  // Single; requires array for image_urls but expects single effectively
                supportedParams: [.enableSafetyChecker, .numImages],  // No image_size, guidance, etc.
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "image_urls",  // Array required per error
                acceptsMultiImages: false,  // But use array of 1
                acceptsBase64: true,
                acceptsPublicURL: true
            )
        case "reve/create-image":
            return AIMLModel(
                id: id,
                isI2I: false,
                maxInputImages: 0,
                supportedParams: [.enableSafetyChecker, .numImages],
                supportsCustomResolution: false,
                defaultImageSize: "square_hd",
                imageInputParam: "",
                acceptsMultiImages: false,
                acceptsBase64: false,
                acceptsPublicURL: false
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
                acceptsPublicURL: true
            )
        }
    }
}

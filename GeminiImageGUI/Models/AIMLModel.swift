//  AIMLModel.swift
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
}

enum AIMLParam: String, CaseIterable {
    case strength
    case numInferenceSteps
    case guidanceScale
    case negativePrompt
    case seed
    case numImages
    case enableSafetyChecker
    case watermark // Model-specific example
    // Add more as needed, e.g., .safetyTolerance
}

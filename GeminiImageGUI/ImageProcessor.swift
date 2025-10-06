//  ImageProcessor.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Required for CGImageSource/Destination APIs
import UniformTypeIdentifiers



// No need for duplicated typealias or platformPngData extension—they're in PlatformAbstractions.swift

func processImageForUpload(image: PlatformImage, originalData: Data? = nil, format: String = "jpeg", quality: CGFloat = 0.6) -> (data: Data, mimeType: String)? {
    let lowerFormat = format.lowercased()
    let ext = lowerFormat == "jpeg" ? "jpg" : "png"
    let mime = lowerFormat == "jpeg" ? "image/jpeg" : "image/png"
    
    if lowerFormat == "png", let orig = originalData, isPNGData(orig) {
        // Passthrough original PNG data to preserve metadata/chunks
        return (orig, mime)
    }
    
    guard let imageData = image.platformData(forType: ext, compressionQuality: quality) else { return nil }
    
    let safeData: Data
    if lowerFormat == "png" {
        safeData = imageData  // Generated PNG (may lose custom chunks)
    } else {
        safeData = stripExif(from: imageData) ?? imageData
    }
    
    return (safeData, mime)
}

private func stripExif(from imageData: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
          let type = CGImageSourceGetType(source),
          let destination = CGImageDestinationCreateWithData(NSMutableData() as CFMutableData, type, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, nil) // Copies without metadata
    guard CGImageDestinationFinalize(destination) else { return nil }
    return (destination as? NSMutableData) as Data?
}

/// Returns true if data is JPEG (checks signature).
func isJPEGData(_ data: Data) -> Bool {
    guard data.count >= 2 else { return false }
    return data[0] == 0xFF && data[1] == 0xD8
}

/// Converts image data to JPEG (if not already) and adds an EXIF UserComment (e.g., "Prompt: [prompt]\n[creator]"), preserving compatible metadata.
/// Returns JPEG data with EXIF on success; nil on failure.
/// Truncates prompt to maxTotalLength chars (with "..." if needed); set high for no effective limit.
func addCommentToJPEG(inputData: Data, prompt: String, creator: String, quality: CGFloat = 0.95, maxTotalLength: Int = 255) -> Data? {
    guard let source = CGImageSourceCreateWithData(inputData as CFData, nil) else {
        return nil
    }
    
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
        return nil
    }
    
    let destinationData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, kUTTypeJPEG as CFString, count, nil) else {
        return nil
    }
    
    // Truncate prompt to fit total limit (reserve space for "\n" + creator)
    let reserved = 1 + creator.count  // "\n" + creator
    let maxPromptLen = maxTotalLength - reserved
    let truncatedPrompt = (prompt.count > maxPromptLen) ? String(prompt.prefix(max(0, maxPromptLen - 3))) + "..." : prompt
    let comment = "Prompt: \(truncatedPrompt)\n\(creator)"  // Eliminated "Creator: " for space
    
    for i in 0..<count {
        // Copy existing properties (preserves compatible metadata)
        var mutableProps = (CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]) ?? [:]
        
        // Add/update EXIF dictionary with UserComment
        var exifDict = mutableProps[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exifDict[kCGImagePropertyExifUserComment as String] = comment
        mutableProps[kCGImagePropertyExifDictionary as String] = exifDict
        
        // Set JPEG compression quality
        let destOptions = [kCGImageDestinationMergeMetadata: true, kCGImageDestinationImageMaxPixelSize: 0, kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        
        // Add image with updated props
        CGImageDestinationAddImageFromSource(destination, source, i, mutableProps as CFDictionary)
        CGImageDestinationSetProperties(destination, destOptions)
    }
    
    guard CGImageDestinationFinalize(destination) else { return nil }
    return destinationData as Data
}

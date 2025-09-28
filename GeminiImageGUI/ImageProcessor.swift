//  ImageProcessor.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Required for CGImageSource/Destination APIs

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

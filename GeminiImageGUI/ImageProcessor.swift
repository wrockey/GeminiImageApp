//  ImageProcessor.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Required for CGImageSource/Destination APIs

// No need for duplicated typealias or platformPngData extension—they're in PlatformAbstractions.swift

func processImageForUpload(image: PlatformImage, format: String = "jpeg", quality: CGFloat = 0.6) -> (data: Data, mimeType: String)? {
    let ext = format.lowercased() == "jpeg" ? "jpg" : "png"
    guard let imageData = image.platformData(forType: ext, compressionQuality: quality) else { return nil }

    // Strip EXIF/GPS metadata
    let safeData = stripExif(from: imageData) ?? imageData

    let mime = format.lowercased() == "jpeg" ? "image/jpeg" : "image/png"

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

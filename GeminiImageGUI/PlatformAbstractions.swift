//
// PlatformAbstractions.swift
//
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import PhotosUI // Added for PHPicker
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Image Abstraction
#if os(macOS)
typealias PlatformImage = NSImage
#elseif os(iOS)
typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    var platformSize: CGSize {
        #if os(macOS)
        return size
        #elseif os(iOS)
        return size
        #endif
    }
    
    convenience init?(platformData: Data) {
        #if os(macOS)
        self.init(data: platformData)
        #elseif os(iOS)
        self.init(data: platformData)
        #endif
    }
    
    convenience init?(contentsOf url: URL) {
        do {
            let data = try Data(contentsOf: url)
            self.init(platformData: data)
        } catch {
            return nil
        }
    }
    
    func platformPngData() -> Data? {
        #if os(macOS)
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #elseif os(iOS)
        return pngData()
        #endif
    }
    
    func platformTiffRepresentation() -> Data? {
        #if os(macOS)
        return tiffRepresentation
        #elseif os(iOS)
        // iOS equivalent: Convert to TIFF if needed, but rare; stub for compatibility
        return nil // Implement if required for port
        #endif
    }
}

// MARK: - Pasteboard Abstraction
struct PlatformPasteboard {
    static func clearContents() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        #elseif os(iOS)
        UIPasteboard.general.items = []
        #endif
    }
    
    static func writeImage(_ image: PlatformImage) {
        #if os(macOS)
        NSPasteboard.general.writeObjects([image])
        #elseif os(iOS)
        UIPasteboard.general.image = image
        #endif
    }
    
    static func writeString(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
    }
    
    static func readImages() -> [PlatformImage]? {
        #if os(macOS)
        return NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [PlatformImage]
        #elseif os(iOS)
        if let image = UIPasteboard.general.image {
            return [image]
        }
        return nil
        #endif
    }
}

// MARK: - File Picker Abstraction
// Callback-based for handling selection results
typealias FilePickerCallback = (Result<[URL], Error>) -> Void

#if os(iOS)
class FilePickerManager {
    static let shared = FilePickerManager()
    private init() {}
    var activeDelegates: [FilePickerDelegate] = []
}
#endif

struct PlatformFilePicker {
    static func presentOpenPanel(
        allowedTypes: [UTType],
        allowsMultiple: Bool,
        canChooseDirectories: Bool,
        message: String? = nil,
        prompt: String? = "Open",
        directoryURL: URL? = nil,
        callback: @escaping FilePickerCallback
    ) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = !canChooseDirectories // For folders, disable file selection
        if let message = message {
            panel.message = message
        }
        panel.prompt = prompt
        panel.directoryURL = directoryURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first // Asynchronous presentation
        panel.begin { response in
            if response == .OK {
                callback(.success(panel.urls))
            } else {
                callback(.failure(NSError(domain: "FilePicker", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
            }
        }
        #elseif os(iOS)
        let asCopy = false // Use false for all to get scoped access without copy
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultiple
        picker.directoryURL = directoryURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        picker.shouldShowFileExtensions = true
        let delegate = FilePickerDelegate(callback: callback)
        FilePickerManager.shared.activeDelegates.append(delegate) // Retain delegate
        picker.delegate = delegate
        // Present from top VC to avoid dismissal bugs
        var topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presentedVC = topVC?.presentedViewController {
            topVC = presentedVC
        }
        if let topVC = topVC {
            print("Presenting picker from top VC: \(topVC)")
            topVC.present(picker, animated: true)
        } else {
            print("No top VC found")
            callback(.failure(NSError(domain: "FilePicker", code: 1, userInfo: [NSLocalizedDescriptionKey: "No root view controller"])))
        }
        #endif
    }
}

// MARK: - Browser Opener Abstraction
struct PlatformBrowser {
    static func open(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Graphics Context Abstraction for Annotation Rendering
protocol PlatformRenderer {
    func render(image: PlatformImage, strokes: [Stroke], textBoxes: [TextBox], annotationScale: CGFloat, offset: CGPoint) -> PlatformImage?
}

struct PlatformRendererFactory {
    static var renderer: PlatformRenderer {
        #if os(macOS)
        MacOSRenderer()
        #elseif os(iOS)
        iOSRenderer()
        #endif
    }
}

#if os(macOS)
struct MacOSRenderer: PlatformRenderer {
    func render(image: PlatformImage, strokes: [Stroke], textBoxes: [TextBox], annotationScale: CGFloat, offset: CGPoint) -> PlatformImage? {
        let size = image.platformSize
        let newImage = NSImage(size: size, flipped: true) { _ in
            // Draw base image (in flipped y-down context)
            image.draw(in: NSRect(origin: .zero, size: size))
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            
            // Draw strokes (no manual flip needed)
            for stroke in strokes {
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setLineWidth(stroke.lineWidth * annotationScale)
                stroke.color.platformColor.setStroke()
                
                var path = stroke.path
                // Transform: scale points first, then translate (maps view coords to image in y-down)
                let transform = CGAffineTransform(scaleX: annotationScale, y: annotationScale)
                    .translatedBy(x: -offset.x, y: -offset.y)
                path = path.applying(transform)
                context.addPath(path.cgPath)
                context.strokePath()
            }
            
            // Draw text boxes (upright, centered in y-down context)
            for box in textBoxes {
                let scaledX = (box.position.x - offset.x) * annotationScale
                let scaledY = (box.position.y - offset.y) * annotationScale
                let fontSize = 20 * annotationScale
                let font = NSFont.systemFont(ofSize: fontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: box.color.platformColor,
                    .font: font
                ]
                let attributedString = NSAttributedString(string: box.text, attributes: attributes)
                let stringSize = attributedString.size()
                
                // Center the text bounding box around the scaled position
                let textRect = NSRect(
                    x: scaledX - stringSize.width / 2,
                    y: scaledY - stringSize.height / 2,
                    width: stringSize.width,
                    height: stringSize.height
                )
                attributedString.draw(in: textRect)
            }
            
            return true
        }
        return newImage
    }
}
#endif

#if os(iOS)
struct iOSRenderer: PlatformRenderer {
    func render(image: PlatformImage, strokes: [Stroke], textBoxes: [TextBox], annotationScale: CGFloat, offset: CGPoint) -> PlatformImage? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            // Draw base image (in flipped y-down context provided by renderer)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let context = ctx.cgContext
            // Draw strokes (no manual flip needed)
            for stroke in strokes {
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setLineWidth(stroke.lineWidth * annotationScale)
                stroke.color.platformColor.setStroke()
                
                var path = stroke.path
                // Transform: scale points first, then translate (maps view coords to image in y-down)
                let transform = CGAffineTransform(scaleX: annotationScale, y: annotationScale)
                    .translatedBy(x: -offset.x, y: -offset.y)
                path = path.applying(transform)
                context.addPath(path.cgPath)
                context.strokePath()
            }
            
            // Draw text boxes (upright, centered in y-down context)
            for box in textBoxes {
                let scaledX = (box.position.x - offset.x) * annotationScale
                let scaledY = (box.position.y - offset.y) * annotationScale
                let fontSize = 20 * annotationScale
                let font = UIFont.systemFont(ofSize: fontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: box.color.platformColor,
                    .font: font
                ]
                let attributedString = NSAttributedString(string: box.text, attributes: attributes)
                let stringSize = attributedString.size()
                
                // Center the text bounding box around the scaled position
                let textRect = CGRect(
                    x: scaledX - stringSize.width / 2,
                    y: scaledY - stringSize.height / 2,
                    width: stringSize.width,
                    height: stringSize.height
                )
                attributedString.draw(in: textRect)
            }
        }
    }
}
#endif

extension Color {
    var platformColor: PlatformColor {
        #if os(macOS)
        NSColor(self)
        #elseif os(iOS)
        UIColor(self)
        #endif
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
#elseif os(iOS)
typealias PlatformColor = UIColor
#endif

// MARK: - SwiftUI Image Extension for PlatformImage
extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #elseif os(iOS)
        self.init(uiImage: platformImage)
        #endif
    }
}

// MARK: - Secure Access Utility
func withSecureAccess<T>(to url: URL, perform: () throws -> T) throws -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    return try perform()
}

#if os(iOS)
class FilePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let callback: FilePickerCallback
    
    init(callback: @escaping FilePickerCallback) {
        self.callback = callback
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("Picked URLs in delegate: \(urls)")
        callback(.success(urls))
        controller.dismiss(animated: true)
        FilePickerManager.shared.activeDelegates.removeAll { $0 === self } // Release self
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Picker cancelled in delegate")
        callback(.failure(NSError(domain: "FilePicker", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
        controller.dismiss(animated: true)
        FilePickerManager.shared.activeDelegates.removeAll { $0 === self } // Release self
    }
}
#endif

// Note: Add this extension to PlatformAbstractions.swift for full abstraction
extension PlatformImage {
    func platformData(forType ext: String, compressionQuality: CGFloat = 1.0) -> Data? {
        let lower = ext.lowercased()
        if lower == "png" {
            return platformPngData()
        } else if lower == "jpg" || lower == "jpeg" {
            #if os(macOS)
            guard let tiff = tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
            #elseif os(iOS)
            return jpegData(compressionQuality: compressionQuality)
            #endif
        }
        // Add support for more formats if needed
        return nil
    }
}

protocol PlatformTextView {
    var string: String { get set }
    var selectedText: String { get }
    func copySelected()
    func paste()
    func clear()
}

#if os(macOS)
extension NSTextView: PlatformTextView {
    var selectedText: String {
        return (string as NSString).substring(with: selectedRange()) as String
    }
    
    func copySelected() {
        if let window = self.window {
            window.makeFirstResponder(self)
        }
        self.copy(nil)
    }
    
    func paste() {
        print("Executing paste in NSTextView")
        if let window = self.window {
            window.makeFirstResponder(self)
        }
        self.paste(nil)
    }
    
    func clear() {
        string = ""
    }
}
#elseif os(iOS)
extension UITextView: PlatformTextView {
    var string: String {
        get { text ?? "" }
        set { text = newValue }
    }
    
    var selectedText: String {
        if let range = selectedTextRange {
            return text(in: range) ?? ""
        }
        return ""
    }
    
    func copySelected() {
        if !isFirstResponder {
            becomeFirstResponder()
        }
        self.copy(nil)
    }
    
    func paste() {
        if !isFirstResponder {
            becomeFirstResponder()
        }
        self.paste(nil)
    }
    
    func clear() {
        text = ""
    }
}
#endif

#if os(macOS)
typealias PlatformTextDelegate = NSTextViewDelegate
#elseif os(iOS)
typealias PlatformTextDelegate = UITextViewDelegate
#endif

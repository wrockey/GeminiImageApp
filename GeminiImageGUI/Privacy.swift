//  Privacy.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

extension ContentView {
    
    // New: Show consent alert for AI/ML API
    @MainActor
    func showAIMLConsentAlert() async -> Bool {
        await withCheckedContinuation { continuation in
#if os(iOS)
            let alert = UIAlertController(
                title: "Data Sharing Notice",
                message: "Prompts and images will be sent to aimlapi.com for generation. View AI/ML API's privacy policy?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "View Privacy Policy", style: .default) { _ in
                if let url = URL(string: "https://aimlapi.com/privacy-policy") {
                    UIApplication.shared.open(url)
                }
                continuation.resume(returning: false)
            })
            
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            // Present from top VC
            var topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let presentedVC = topVC?.presentedViewController {
                topVC = presentedVC
            }
            topVC?.present(alert, animated: true)
#elseif os(macOS)
            let alert = NSAlert()
            alert.messageText = "Data Sharing Notice"
            alert.informativeText = "Prompts and images will be sent to aimlapi.com for generation. View AI/ML API's privacy policy?"
            alert.addButton(withTitle: "View Privacy Policy")
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // View Privacy Policy
                if let url = URL(string: "https://aimlapi.com/privacy-policy") {
                    NSWorkspace.shared.open(url)
                }
                continuation.resume(returning: false)
            case .alertSecondButtonReturn: // Continue
                continuation.resume(returning: true)
            default: // Cancel
                continuation.resume(returning: false)
            }
#endif
        }
    }
    // New: Show consent alert for Grok
    @MainActor
    func showGrokConsentAlert() async -> Bool {
        await withCheckedContinuation { continuation in
#if os(iOS)
            let alert = UIAlertController(
                title: "Data Sharing Notice",
                message: "Prompts and images will be sent to xAI for generation. View xAI's privacy policy?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "View Privacy Policy", style: .default) { _ in
                if let url = URL(string: "https://x.ai/privacy-policy") {
                    UIApplication.shared.open(url)
                }
                continuation.resume(returning: false)
            })
            
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            // Present from top VC
            var topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let presentedVC = topVC?.presentedViewController {
                topVC = presentedVC
            }
            topVC?.present(alert, animated: true)
#elseif os(macOS)
            let alert = NSAlert()
            alert.messageText = "Data Sharing Notice"
            alert.informativeText = "Prompts and images will be sent to xAI for generation. View xAI's privacy policy?"
            alert.addButton(withTitle: "View Privacy Policy")
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // View Privacy Policy
                if let url = URL(string: "https://x.ai/privacy-policy") {
                    NSWorkspace.shared.open(url)
                }
                continuation.resume(returning: false)
            case .alertSecondButtonReturn: // Continue
                continuation.resume(returning: true)
            default: // Cancel
                continuation.resume(returning: false)
            }
#endif
        }
    }
    @MainActor
    func showGeminiConsentAlert() async -> Bool {
        await withCheckedContinuation { continuation in
#if os(iOS)
            let alert = UIAlertController(
                title: "Data Sharing Notice",
                message: "Prompts and images will be sent to Google for generation. View Google's privacy policy?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "View Privacy Policy", style: .default) { _ in
                if let url = URL(string: "https://policies.google.com/privacy") {
                    UIApplication.shared.open(url)
                }
                continuation.resume(returning: false) // Don't proceed automatically after viewing
            })
            
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            // Present from top VC
            var topVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let presentedVC = topVC?.presentedViewController {
                topVC = presentedVC
            }
            topVC?.present(alert, animated: true)
#elseif os(macOS)
            let alert = NSAlert()
            alert.messageText = "Data Sharing Notice"
            alert.informativeText = "Prompts and images will be sent to Google for generation. View Google's privacy policy?"
            alert.addButton(withTitle: "View Privacy Policy")
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // View Privacy Policy
                if let url = URL(string: "https://policies.google.com/privacy") {
                    NSWorkspace.shared.open(url)
                }
                continuation.resume(returning: false)
            case .alertSecondButtonReturn: // Continue
                continuation.resume(returning: true)
            default: // Cancel
                continuation.resume(returning: false)
            }
#endif
        }
    }
}

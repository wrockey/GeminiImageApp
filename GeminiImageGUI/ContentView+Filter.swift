// ContentView+Filter.swift
import Foundation
import SwiftUI

extension ContentView {
    // New: Prompt safety check (client-side keyword filter)
    static func isPromptSafe(_ prompt: String) -> Bool {
        let forbiddenPatterns = [
            "(?:nsfw|explicit|nude|porn|sex|violence|gore|hate|illegal|drugs)s?",  // Handles plurals
            "\\b(p[o0]rn|seks|violenc[ea])\\b"  // Misspellings
        ]  // Expand as needed
        
        let lowerPrompt = prompt.lowercased()
        for pattern in forbiddenPatterns {
            if lowerPrompt.range(of: pattern, options: .regularExpression) != nil {
                return false
            }
        }
        return true
    }
}

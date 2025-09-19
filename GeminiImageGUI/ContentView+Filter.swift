// ContentView+Filter.swift
import Foundation
import SwiftUI

extension ContentView {
    // New: Prompt safety check (client-side keyword filter)
    static func isPromptSafe(_ prompt: String) -> Bool {
        let forbiddenTerms = ["nsfw", "explicit", "nude", "porn", "sex", "violence", "gore", "hate", "illegal", "drugs", "weapon"]  // Expand as needed; case-insensitive
        let lowerPrompt = prompt.lowercased()
        for term in forbiddenTerms {
            if lowerPrompt.contains(term) {
                return false
            }
        }
        return true
    }
}

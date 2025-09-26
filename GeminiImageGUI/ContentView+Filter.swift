import Foundation
import SwiftUI

extension ContentView {
    // Improved: Prompt safety check (returns safety flag and list of offending phrases)
    static func isPromptSafe(_ prompt: String) -> (isSafe: Bool, offendingPhrases: [String]) {
        // Preprocess the prompt to handle obfuscations
        var normalized = prompt.lowercased()
        
        // Replace common leetspeak and substitutions
        normalized = normalized.replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "3", with: "e")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "@", with: "a")
            .replacingOccurrences(of: "$", with: "s")
            .replacingOccurrences(of: "!", with: "i")
        
        // Remove non-alphanumeric characters and extra spaces to catch spaced words
        normalized = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        
        // Expanded list of forbidden patterns (regex for flexibility)
        let forbiddenPatterns = [
            // Sexual/explicit
            "(?:nsfw|explicit|nude|naked|porn|sex|erotic|intercourse|orgasm|masturbat|fuck|blowjob|anal|bdsm|fetish|incest|rape|molest|hentai|ecchi|lewd|boob|breast|ass|butt|genital|pussy|dick|cock|penis|vagina|nipple|thong|bikini|lingerie|strip|seduc|prostitut|escort|hooker|traffick)s?",
            "\\b(p[o0]rn|s[e3]x|f[u]ck|bl[o0]wj[o0]b|an[a4]l|r[a4]p[e3]|m[o0]l[e3]st)\\b",
            
            // Violence/gore
            "(?:violence|gore|blood|torture|kill|murder|assault|abuse|stab|shoot|bomb|explode|terror|massacre|slaughter|decapitat|dismember|suicide|selfharm|lynch|genocide|warcrime)s?",
            "\\b(v[i1][o0]l[e3]nc[e3]|g[o0]r[e3]|k[i1]ll|m[u]rd[e3]r|t[o0]rt[u]r[e3]|b[o0]mb)\\b",
            
            // Hate/discrimination
            "(?:hate|racis|discriminat|bigot|nazi|supremac|slur|nigga|nigger|fag|dyke|tranny|retard|cripple|islamophob|antisemit|homophob|transphob|xenophob)s?",
            "\\b(r[a4]c[i1]st|h[a4]t[e3]|n[a4]z[i1]|sl[u]r)\\b",
            
            // Drugs/illegal substances (excluding therapeutic like cannabis)
            "(?:drug|heroin|cocaine|meth|crack|lsd|ecstasy|fentanyl|opioid|addict|overdose|smuggle|dealer)s?",
            "\\b(h[e3]r[o0][i1]n|c[o0]c[a4][i1]n[e3]|m[e3]th|dr[u]g)\\b",
            
            // Weapons/illegal activities
            "(?:weapon|gun|knife|explosive|bomb|illegal|hack|phish|fraud|steal|rob|burglar|traffick|extort|blackmail)s?",
            "\\b(w[e3][a4]p[o0]n|g[u]n|kn[i1]f[e3]|b[o0]mb|h[a4]ck)\\b",
            
            // Other harmful (e.g., self-harm, extremism)
            "(?:selfharm|suicid|cut|burn|anorex|bulim|extremis|radical|jihad|cult|propaganda)s?",
            "\\b(s[u][i1]c[i1]d[e3]|s[e3]lfh[a4]rm|[e3]xtr[e3]m[i1]st)\\b"
        ]  // Expand further based on testing or API feedback
        
        var offending = Set<String>()  // Use Set to avoid duplicates
        
        for pattern in forbiddenPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(location: 0, length: normalized.utf16.count)
            regex.enumerateMatches(in: normalized, options: [], range: range) { result, _, _ in
                if let matchRange = result?.range, let swiftRange = Range(matchRange, in: normalized) {
                    let matchedString = String(normalized[swiftRange])
                    offending.insert(matchedString)
                }
            }
        }
        
        let isSafe = offending.isEmpty
        return (isSafe, Array(offending).sorted())  // Sort for consistent output
    }
}

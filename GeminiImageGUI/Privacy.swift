// Privacy.swift (full corrected)
import SwiftUI

enum PrivacyService: String, Identifiable {
    case gemini = "Gemini"
    case grok = "Grok"
    case aimlapi = "AI/ML API"
    case imgbb = "ImgBB"

    var id: Self { self }  // Conform to Identifiable

    var policyURL: String {
        switch self {
        case .gemini: return "https://policies.google.com/privacy"
        case .grok: return "https://x.ai/privacy-policy"
        case .aimlapi: return "https://aimlapi.com/privacy-policy"
        case .imgbb: return "https://imgbb.com/privacy"
        }
    }

    var message: String {
        switch self {
        case .gemini, .grok, .aimlapi:
            return "Your prompts and any input images will be sent to \(rawValue) for image generation. Data may be stored or used to improve services. Review the privacy policy for details."
        case .imgbb:
            return "Input images will be uploaded to ImgBB to generate public URLs for the AI model. These URLs are temporary but public during processing."
        }
    }
}

struct PrivacyNoticeSheet: View {
    let service: PrivacyService
    let onDismiss: (Bool, Bool) -> Void  // (consented, dontShowAgain)

    @State private var dontShowAgain = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("\(service.rawValue) Privacy Notice")
                .font(.title2.bold())
                .foregroundColor(.primary)

            Text(service.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let url = URL(string: service.policyURL) {
                Link("View Privacy Policy", destination: url)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.regular)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }

            Toggle(isOn: $dontShowAgain) {
                Text("Don't show again")
                    .font(.subheadline.italic())
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onDismiss(false, dontShowAgain)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .foregroundColor(.secondary)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0.5)

                Button("Continue") {
                    onDismiss(true, dontShowAgain)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.blue)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
        .padding(24)
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .frame(minWidth: 400, maxWidth: 450, minHeight: 250)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

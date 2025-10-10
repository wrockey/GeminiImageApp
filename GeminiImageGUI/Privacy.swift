// Privacy.swift (simplified without #available to avoid version errors; use introspection for all iOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PrivacyService: String, Identifiable {
    case gemini = "Gemini"
    case grok = "Grok"
    case aimlapi = "AI/ML API"
    case imgbb = "ImgBB"

    var id: Self { self }

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
    let onDismiss: (Bool, Bool) -> Void

    @State private var dontShowAgain = false

    var body: some View {
        ZStack {
            #if os(iOS)
            UIKitIntrospectionView { hostingController in
                hostingController.view.backgroundColor = .clear
                if let presentationController = hostingController.presentationController {
                    presentationController.containerView?.backgroundColor = .clear
                }
                if let sheetView = hostingController.view.superview {
                    sheetView.backgroundColor = .clear
                }
            }
            .frame(width: 0, height: 0)
            #endif
            
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

                Checkbox(isChecked: $dontShowAgain, label: "Don't show again")

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
            #if os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
            #elseif os(iOS)
            .background(Color(UIColor.systemBackground).opacity(0.95))
            #endif
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .frame(minWidth: 400, maxWidth: 450, minHeight: 250)  // If extra arg error, remove minHeight or check SwiftUI version; it's valid in SwiftUI 5+
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        #if os(iOS)
        .presentationDetents([.height(320)])
        .presentationBackground(.clear)
        #endif
    }
}

struct Checkbox: View {
    @Binding var isChecked: Bool
    let label: String

    var body: some View {
        Button(action: {
            isChecked.toggle()
        }) {
            HStack {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .blue : .gray)
                    .font(.system(size: 20))
                Text(label)
                    .font(.subheadline.italic())
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// Update UIKitIntrospectionView to target more views
#if os(iOS)
class IntrospectionViewController: UIViewController {
    var onResolve: ((UIViewController) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let onResolve = onResolve {
            var targetVC = self.parent
            while let vc = targetVC, !(vc is UIHostingController<PrivacyNoticeSheet>) {
                targetVC = vc.parent
            }
            if let sheetVC = targetVC as? UIHostingController<PrivacyNoticeSheet> {
                sheetVC.view.backgroundColor = .clear
            }
            onResolve(targetVC ?? self)
        }
    }
}

struct UIKitIntrospectionView: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void
    
    func makeUIViewController(context: Context) -> IntrospectionViewController {
        let controller = IntrospectionViewController()
        controller.onResolve = onResolve
        return controller
    }
    
    func updateUIViewController(_ uiViewController: IntrospectionViewController, context: Context) {}
}
#endif

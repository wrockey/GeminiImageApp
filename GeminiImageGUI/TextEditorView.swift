//TextEditorView.swift
import SwiftUI

#if os(macOS)
typealias Representable = NSViewRepresentable
#elseif os(iOS)
typealias Representable = UIViewRepresentable
#endif

struct CustomTextEditor: Representable {
    @Binding var text: String
    @Binding var platformTextView: PlatformTextView?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        platformTextView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
            }
        }
    }
    #elseif os(iOS)
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        platformTextView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    #endif

    class Coordinator: NSObject, PlatformTextDelegate {
        var parent: CustomTextEditor

        init(parent: CustomTextEditor) {
            self.parent = parent
        }

        #if os(macOS)
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
        #elseif os(iOS)
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }
        #endif
    }
}

extension Notification.Name {
    static let batchFileUpdated = Notification.Name("batchFileUpdated")
}

struct TextEditorView: View {
    let fileURL: URL
    @State private var text: String = ""
    @State private var error: String? = nil
    @State private var platformTextView: PlatformTextView? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
            } else {
                CustomTextEditor(text: $text, platformTextView: $platformTextView)
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    platformTextView?.paste()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                Button {
                    platformTextView?.copySelectedOrAll()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                Button {
                    platformTextView?.clear()
                    text = ""
                } label: {
                    Image(systemName: "trash")
                }
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
        .onAppear {
            loadText()
        }
    }

    private func loadText() {
        do {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveAndDismiss() {
        do {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// CustomTextEditor.swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct CustomTextEditor: View {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    
    let windowDelegate: TextEditorWindowDelegate? = nil  // Optional for macOS
    let windowTitle: String = ""  // Optional for macOS

    var body: some View {
        #if os(macOS)
        MacCustomTextEditor(text: $text, platformTextView: $platformTextView, windowDelegate: windowDelegate, windowTitle: windowTitle)
        #elseif os(iOS)
        iOSCustomTextEditor(text: $text, platformTextView: $platformTextView)
        #endif
    }
}

#if os(macOS)
struct MacCustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    let windowDelegate: TextEditorWindowDelegate?
    let windowTitle: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor.withAlphaComponent(0.5)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        textView.delegate = context.coordinator
        textView.string = text
        platformTextView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        DispatchQueue.main.async {
            if let window = nsView.window {
                if window.firstResponder != textView {
                    window.makeFirstResponder(textView)
                }
                if let windowDelegate = windowDelegate, window.delegate !== windowDelegate {
                    windowDelegate.window = window
                    window.delegate = windowDelegate
                }
                if window.title != windowTitle && !windowTitle.isEmpty {
                    window.title = windowTitle
                }
            }
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacCustomTextEditor
        
        init(parent: MacCustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
}
#endif

#if os(iOS)
struct iOSCustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.delegate = context.coordinator
        textView.textColor = .label
        textView.backgroundColor = .systemBackground.withAlphaComponent(0.5)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.contentInsetAdjustmentBehavior = .automatic
        textView.text = text
        platformTextView = textView
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        DispatchQueue.main.async {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSCustomTextEditor
        
        init(parent: iOSCustomTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }
    }
}
#endif

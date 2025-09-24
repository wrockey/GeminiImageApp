//TextEditorView.swift
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
typealias Representable = NSViewRepresentable
#elseif os(iOS)
typealias Representable = UIViewRepresentable
#endif

struct CustomTextEditor: Representable {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    #if os(macOS)
    let windowDelegate: TextEditorWindowDelegate?
    let windowTitle: String
    #endif

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
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
                    print("Setting delegate for window: \(window.title), all windows: \(NSApp.windows.map { $0.title })")
                    windowDelegate.window = window
                    window.delegate = windowDelegate
                }
                if window.title != windowTitle {
                    window.title = windowTitle
                }
            }
        }
    }
    #elseif os(iOS)
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 10, bottom: 20, right: 10)
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

#if os(macOS)
class TextEditorWindowDelegate: NSObject, NSWindowDelegate {
    var shouldCloseHandler: (() -> Bool)?
    weak var window: NSWindow?
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("windowShouldClose called for window: \(sender.title)")
        return shouldCloseHandler?() ?? true
    }
}
#endif

struct TextEditorView: View {
    let bookmarkData: Data?
    @Binding var batchFilePath: String
    @State private var fileURL: URL? = nil
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var error: String? = nil
    @State private var platformTextView: (any PlatformTextView)? = nil
    @State private var showSaveConfirm: Bool = false
    @State private var showCloseConfirm: Bool = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    #if os(macOS)
    @State private var windowDelegate = TextEditorWindowDelegate()
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: { handleCloseAttempt() }) {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            saveAndDismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Batch Editor")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Are you sure you want to overwrite \(fileURL?.lastPathComponent ?? "the file")?", isPresented: $showSaveConfirm) {
            Button("Yes", role: .destructive) {
                if let url = fileURL {
                    performSave(to: url) { success in
                        if success {
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Unsaved Changes", isPresented: $showCloseConfirm) {
            Button("Save and Close") {
                saveAndDismiss()
            }
            Button("Discard Changes", role: .destructive) {
                initialText = text
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Do you want to save them?")
        }
        .alert("Error", isPresented: Binding<Bool>(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown error")
        }
        .onAppear {
            if let bookmarkData = bookmarkData, !bookmarkData.isEmpty {
                loadFromBookmark(bookmarkData)
            } else {
                // No bookmark; initialize empty editor
                text = ""
                initialText = ""
                fileURL = nil
                self.error = nil
            }
        }
        #else
        VStack(spacing: 0) {
            content
        }
        .frame(minWidth: 400, minHeight: 300)
        .toolbar {
            ToolbarItem {
                Button(action: { handleCloseAttempt() }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "trash")
                }
            }
            ToolbarItem {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
        .alert("Are you sure you want to overwrite \(fileURL?.lastPathComponent ?? "the file")?", isPresented: $showSaveConfirm) {
            Button("Yes", role: .destructive) {
                if let url = fileURL {
                    performSave(to: url) { success in
                        if success {
                            windowDelegate.window?.close()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Unsaved Changes", isPresented: $showCloseConfirm) {
            Button("Save and Close") {
                saveAndDismiss()
            }
            Button("Discard Changes", role: .destructive) {
                initialText = text
                windowDelegate.window?.close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Do you want to save them?")
        }
        .alert("Error", isPresented: Binding<Bool>(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown error")
        }
        .onAppear {
            if let bookmarkData = bookmarkData, !bookmarkData.isEmpty {
                loadFromBookmark(bookmarkData)
            } else {
                // No bookmark; initialize empty editor
                text = ""
                initialText = ""
                fileURL = nil
                self.error = nil
            }
            windowDelegate.shouldCloseHandler = handleWindowClose
        }
        #endif
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            if let err = error {
                Text("Error: \(err)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Group {
                #if os(macOS)
                CustomTextEditor(text: $text, platformTextView: $platformTextView, windowDelegate: windowDelegate, windowTitle: fileURL?.lastPathComponent ?? "Batch Editor")
                #else
                CustomTextEditor(text: $text, platformTextView: $platformTextView)
                #endif
            }
            .background(systemBackgroundColor)
        }
    }
    
    private var systemBackgroundColor: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
    
    private func loadFromBookmark(_ bookmarkData: Data) {
        do {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
            fileURL = resolvedURL
            batchFilePath = resolvedURL.path
            if isStale {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
                #endif
                if let newBookmark = try? resolvedURL.bookmarkData(options: bookmarkOptions) {
                    UserDefaults.standard.set(newBookmark, forKey: "batchFileBookmark")
                }
            }
            loadText(from: resolvedURL)
        } catch {
            self.error = error.localizedDescription
            // Fallback to empty if error
            text = ""
            initialText = ""
            fileURL = nil
            UserDefaults.standard.removeObject(forKey: "batchFileBookmark")
            appState.batchPrompts = []
            appState.batchFileURL = nil
            batchFilePath = ""
        }
    }

    private func loadText(from url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                do {
                    let fileContent = try String(contentsOf: coordinatedURL, encoding: .utf8)
                    text = fileContent
                    initialText = fileContent
                    self.error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            } else {
                self.error = "Failed to access file."
            }
        }
        if let coordError = coordError {
            self.error = coordError.localizedDescription
        }
    }

    private func saveAndDismiss() {
        if let url = fileURL {
            showSaveConfirm = true
        } else {
            PlatformFileSaver.presentSavePanel(
                suggestedName: "batch.txt",
                allowedTypes: [UTType.text],
                callback: { result in
                    switch result {
                    case .success(let url):
                        performSave(to: url) { success in
                            if success {
                                appState.batchFileURL = url
                                appState.batchPrompts = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                                batchFilePath = url.path
                                #if os(macOS)
                                windowDelegate.window?.close()
                                #else
                                dismiss()
                                #endif
                            }
                        }
                    case .failure(let err):
                        if err.localizedDescription.lowercased() != "user cancelled" {
                            self.error = err.localizedDescription
                        } else {
                            self.error = nil
                        }
                    }
                }
            )
        }
    }

    private func performSave(to url: URL, accessURL: URL? = nil, completion: @escaping (Bool) -> Void) {
        if let access = accessURL {
            if !access.startAccessingSecurityScopedResource() {
                self.error = "Failed to access folder."
                completion(false)
                return
            }
            defer { access.stopAccessingSecurityScopedResource() }
        }
        
        var coordError: NSError?
        let options: NSFileCoordinator.WritingOptions = fileURL == nil ? [] : [.forReplacing]
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { coordinatedURL in
            let didStart = coordinatedURL.startAccessingSecurityScopedResource()
            defer { if didStart { coordinatedURL.stopAccessingSecurityScopedResource() } }
            
            do {
                try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                if fileURL == nil {
                    #if os(macOS)
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                    #else
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
                    #endif
                    if let newBookmark = try? url.bookmarkData(options: bookmarkOptions) {
                        UserDefaults.standard.set(newBookmark, forKey: "batchFileBookmark")
                    }
                    fileURL = url
                    NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                } else {
                    appState.batchPrompts = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                }
                initialText = text
                completion(true)
            } catch {
                self.error = error.localizedDescription
                completion(false)
            }
        }
        if let coordError = coordError {
            self.error = coordError.localizedDescription
            completion(false)
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        print("Checking unsaved changes: text=\(text), initialText=\(initialText), hasChanges=\(text != initialText)")
        return text != initialText
    }
    
    private func handleCloseAttempt() {
        print("Handle close attempt: hasUnsavedChanges=\(hasUnsavedChanges())")
        if hasUnsavedChanges() {
            DispatchQueue.main.async {
                showCloseConfirm = true
            }
        } else {
            #if os(macOS)
            windowDelegate.window?.close()
            #else
            dismiss()
            #endif
        }
    }
    
    #if os(macOS)
    private func handleWindowClose() -> Bool {
        print("Handle window close: hasUnsavedChanges=\(hasUnsavedChanges())")
        if hasUnsavedChanges() {
            DispatchQueue.main.async {
                showCloseConfirm = true
            }
            return false
        }
        return true
    }
    #endif
}

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
    @Binding var platformTextView: PlatformTextView?
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
            if let window = nsView.window, window.firstResponder != textView {
                window.makeFirstResponder(textView)
            }
            if let window = nsView.window, let windowDelegate = windowDelegate, window.delegate !== windowDelegate {
                print("Setting delegate for window: \(window.title), all windows: \(NSApp.windows.map { $0.title })")
                window.delegate = windowDelegate
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
    @State private var platformTextView: PlatformTextView? = nil
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
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button {
                            platformTextView?.clear()
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            platformTextView?.paste()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            platformTextView?.copySelected()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            platformTextView?.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .disabled(!(platformTextView?.canUndo ?? false))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            platformTextView?.redo()
                        } label: {
                            Image(systemName: "arrow.uturn.right")
                        }
                        .disabled(!(platformTextView?.canRedo ?? false))
                    }
                }
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Batch Editor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: onAppearAction)
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
        #else
        Group {
            content
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Batch Editor")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { handleCloseAttempt() }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                toolbarButtons
            }
        }
        .onAppear {
            onAppearAction()
            #if os(macOS)
            windowDelegate.shouldCloseHandler = handleWindowClose
            #endif
        }
        .alert("Are you sure you want to overwrite \(fileURL?.lastPathComponent ?? "the file")?", isPresented: $showSaveConfirm) {
            Button("Yes", role: .destructive) {
                if let url = fileURL {
                    performSave(to: url) { success in
                        if success {
                            #if os(macOS)
                            let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
                            if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                                window.close()
                            }
                            #else
                            dismiss()
                            #endif
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save changes to \(fileURL?.lastPathComponent ?? "new file") before closing?", isPresented: $showCloseConfirm) {
            Button("Save", role: .destructive) {
                if let url = fileURL {
                    performSave(to: url) { success in
                        if success {
                            #if os(macOS)
                            let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
                            if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                                window.close()
                            }
                            #else
                            dismiss()
                            #endif
                        }
                    }
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
                                        let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
                                        if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                                            window.close()
                                        }
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
            Button("Don’t Save", role: .destructive) {
                #if os(macOS)
                let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
                if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                    window.close()
                }
                #else
                dismiss()
                #endif
            }
            Button("Cancel", role: .cancel) {}
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let error = error, !error.isEmpty {
            Text(error).foregroundColor(.red).padding()
        } else {
            Group {
                #if os(macOS)
                CustomTextEditor(
                    text: $text,
                    platformTextView: $platformTextView,
                    windowDelegate: windowDelegate,
                    windowTitle: fileURL?.lastPathComponent ?? "Batch Editor"
                )
                #else
                CustomTextEditor(
                    text: $text,
                    platformTextView: $platformTextView
                )
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color({
                #if os(macOS)
                NSColor.textBackgroundColor
                #elseif os(iOS)
                UIColor.systemBackground
                #endif
            }()))
        }
    }

    private var toolbarButtons: some View {
        Group {
            #if os(macOS)
            Button(action: {
                NSApp.sendAction(#selector(NSTextView.paste(_:)), to: nil, from: nil as Any?)
            }) {
                Image(systemName: "doc.on.clipboard")
            }
            Button(action: {
                NSApp.sendAction(#selector(NSTextView.copy(_:)), to: nil, from: nil as Any?)
            }) {
                Image(systemName: "doc.on.doc")
            }
            #elseif os(iOS)
            Button(action: {
                platformTextView?.paste()
            }) {
                Image(systemName: "doc.on.clipboard")
            }
            Button(action: {
                platformTextView?.copySelected()
            }) {
                Image(systemName: "doc.on.doc")
            }
            #endif
            Button(action: {
                platformTextView?.clear()
                text = ""
            }) {
                Image(systemName: "trash")
            }
            Button(action: {
                platformTextView?.undo()
            }) {
                Image(systemName: "arrow.uturn.left")
            }
            .disabled(!(platformTextView?.canUndo ?? false))
            Button(action: {
                platformTextView?.redo()
            }) {
                Image(systemName: "arrow.uturn.right")
            }
            .disabled(!(platformTextView?.canRedo ?? false))
            Button(action: saveAndDismiss) {
                Image(systemName: "checkmark")
            }
        }
    }

    private func onAppearAction() {
        if let data = bookmarkData, !data.isEmpty {
            resolveURL(from: data)
        } else {
            // Initialize with empty text for new file
            text = ""
            initialText = ""
            fileURL = nil
            self.error = nil
        }
    }

    private func resolveURL(from bookmarkData: Data) {
        do {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            let bookmarkOptions: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
            
            if resolvedURL.startAccessingSecurityScopedResource() {
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    fileURL = resolvedURL
                    loadText(from: resolvedURL)
                } else {
                    // File doesn't exist; initialize empty editor
                    text = ""
                    initialText = ""
                    fileURL = nil
                    self.error = nil
                    UserDefaults.standard.removeObject(forKey: "batchFileBookmark")
                    appState.batchPrompts = []
                    appState.batchFileURL = nil
                    batchFilePath = ""
                }
                resolvedURL.stopAccessingSecurityScopedResource()
            } else {
                // Failed to access resource; initialize empty editor
                text = ""
                initialText = ""
                fileURL = nil
                self.error = nil
                UserDefaults.standard.removeObject(forKey: "batchFileBookmark")
                appState.batchPrompts = []
                appState.batchFileURL = nil
                batchFilePath = ""
            }
            
            if isStale {
                if let newBookmark = try? resolvedURL.bookmarkData(options: bookmarkOptions) {
                    UserDefaults.standard.set(newBookmark, forKey: "batchFileBookmark")
                }
            }
        } catch {
            // Failed to resolve bookmark; initialize empty editor
            text = ""
            initialText = ""
            fileURL = nil
            self.error = nil
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
                                let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
                                if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                                    window.close()
                                }
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
    
    #if os(macOS)
    private func hasUnsavedChanges() -> Bool {
        return text != initialText
    }
    
    private func handleCloseAttempt() {
        if hasUnsavedChanges() {
            showCloseConfirm = true
        } else {
            let targetTitle = fileURL?.lastPathComponent ?? "Batch Editor"
            if let window = NSApp.windows.first(where: { $0.title == targetTitle }) {
                window.close()
            }
        }
    }
    
    private func handleWindowClose() -> Bool {
        if hasUnsavedChanges() {
            showCloseConfirm = true
            return false
        }
        return true
    }
    #endif
}

extension PlatformTextView {
    var canUndo: Bool {
        #if os(macOS)
        return (self as? NSTextView)?.undoManager?.canUndo ?? false
        #elseif os(iOS)
        return (self as? UITextView)?.undoManager?.canUndo ?? false
        #endif
    }

    var canRedo: Bool {
        #if os(macOS)
        return (self as? NSTextView)?.undoManager?.canRedo ?? false
        #elseif os(iOS)
        return (self as? UITextView)?.undoManager?.canRedo ?? false
        #endif
    }

    func undo() {
        #if os(macOS)
        if let textView = self as? NSTextView {
            textView.undoManager?.undo()
        }
        #elseif os(iOS)
        if let textView = self as? UITextView {
            textView.undoManager?.undo()
        }
        #endif
    }

    func redo() {
        #if os(macOS)
        if let textView = self as? NSTextView {
            textView.undoManager?.redo()
        }
        #elseif os(iOS)
        if let textView = self as? UITextView {
            textView.undoManager?.redo()
        }
        #endif
    }
}

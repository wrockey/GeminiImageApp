//TextEditorView.swift
import SwiftUI
 
#if os(macOS)
typealias Representable = NSViewControllerRepresentable
#elseif os(iOS)
typealias Representable = UIViewRepresentable
#endif


#if os(macOS)
class TextEditorViewController: NSViewController {
    var textView: NSTextView!
    var onTextChange: ((String) -> Void)?  // Callback for text updates
    
    override func loadView() {
        let scrollView = NSScrollView()
        let contentSize = scrollView.contentSize
        
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height), textContainer: textContainer)
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        self.view = scrollView
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }
    
    func updateText(_ newText: String) {
        if textView.string != newText {
            textView.string = newText
        }
    }
}
#endif
 
struct CustomTextEditor: Representable {
    @Binding var text: String
    @Binding var platformTextView: PlatformTextView?

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    #if os(macOS)
    func dismantleNSViewController(_ nsViewController: TextEditorViewController, coordinator: Coordinator) {
        nsViewController.textView.delegate = nil
    }
    #endif

#if os(macOS)
    func makeNSViewController(context: Context) -> TextEditorViewController {
        let controller = TextEditorViewController()
        _ = controller.view  // Force loadView() to initialize textView
        controller.textView.delegate = context.coordinator
        controller.onTextChange = { newText in
            self.text = newText
        }
        platformTextView = controller.textView
        return controller
    }
    
    func updateNSViewController(_ nsViewController: TextEditorViewController, context: Context) {
        _ = nsViewController.view  // Ensure loaded if not already
        nsViewController.updateText(text)
        DispatchQueue.main.async {
            if let window = nsViewController.view.window, window.firstResponder != nsViewController.textView {
                window.makeFirstResponder(nsViewController.textView)
            }
        }
    }

    
    #elseif os(iOS)
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = context.coordinator
        textView.textColor = .label  // Adaptive text color (black in light mode, white in dark)
        textView.backgroundColor = .systemBackground  // Adaptive background
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 10, bottom: 20, right: 10)  // Padding for better usability
        textView.contentInsetAdjustmentBehavior = .automatic  // Respects safe areas and keyboard
        platformTextView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        DispatchQueue.main.async {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()  // <-- ADDED: Shows keyboard, makes editable
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
 
struct TextEditorView: View {
    let bookmarkData: Data
    @State private var fileURL: URL? = nil
    @State private var text: String = ""
    @State private var error: String? = nil
    @State private var platformTextView: PlatformTextView? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
#if os(iOS)
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {  // Leading: Cancel (xmark)
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .destructiveAction) {  // Trailing: Clear (trash)
                        Button {
                            platformTextView?.clear()
                            text = ""
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {  // Trailing: Save (checkmark)
                        Button {
                            saveAndDismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {  // Additional trailing: Paste and Copy
                        Button {
                            platformTextView?.paste()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            platformTextView?.copySelectedOrAll()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Batch Editor")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear(perform: onAppearAction)  // <-- ADD THIS: Loads the text on iOS
#else
        Group {
            content
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Batch Editor")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                toolbarButtons
            }
        }
        .onAppear(perform: onAppearAction)
#endif

    }

    @ViewBuilder
    private var content: some View {
        if let error = error {
            Text(error).foregroundColor(.red).padding()
        } else {
            CustomTextEditor(text: $text, platformTextView: $platformTextView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures it fills the available space below the nav bar
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
            Button(action: { platformTextView?.paste() }) {
                Image(systemName: "doc.on.clipboard")
            }
            Button(action: { platformTextView?.copySelectedOrAll() }) {
                Image(systemName: "doc.on.doc")
            }
            Button(action: { platformTextView?.clear(); text = "" }) {
                Image(systemName: "trash")
            }
            Button(action: saveAndDismiss) {
                Image(systemName: "checkmark")
            }
        }
    }

    private func onAppearAction() {
        resolveURL()
        if let url = fileURL {
            loadText(from: url)
        }
    }

    private func resolveURL() {
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
            
            // Start access (works on both platforms if scoped)
            if resolvedURL.startAccessingSecurityScopedResource() {
                fileURL = resolvedURL
            } else {
                self.error = "Failed to start accessing security-scoped resource."
                return
            }
            
            if isStale {
                if let newBookmark = try? resolvedURL.bookmarkData(options: bookmarkOptions) {
                    UserDefaults.standard.set(newBookmark, forKey: "batchFileBookmark")
                }
            }
        } catch {
            self.error = "Failed to resolve file: \(error.localizedDescription)"
        }
    }
    private func loadText(from url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                do {
                    text = try String(contentsOf: coordinatedURL, encoding: .utf8)
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
        guard let url = fileURL else {
            self.error = "No file URL."
            return
        }
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                do {
                    try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                    NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            } else {
                self.error = "Failed to access file for writing."
            }
        }
        if let coordError = coordError {
            self.error = coordError.localizedDescription
        }
    }
}


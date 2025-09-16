//
// MarkupView.swift
//
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// Preference key for image frame
struct FramePreferenceKey: PreferenceKey {
 static var defaultValue: CGRect = .zero
 static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
 value = nextValue()
 }
}

// Markup State for undo (shared)
struct MarkupState {
 let strokes: [Stroke]
 let textBoxes: [TextBox]
}

struct Stroke: Identifiable {
 let id = UUID()
 var path: Path
 let color: Color
 let lineWidth: CGFloat
}

struct TextBox: Identifiable {
 let id = UUID()
 var text: String
 var position: CGPoint
 var color: Color = .black
}

// Extension for conditional modifier
extension View {
 @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
 if condition {
 transform(self)
 } else {
 self
 }
 }
}

// Extension to make window non-resizable on macOS
extension View {
    func nonResizableWindow() -> some View {
        #if os(macOS)
        self.onAppear {
            if let window = NSApp.windows.first {
                window.styleMask.remove(.resizable)
            }
        }
        #else
        self
        #endif
    }
}

// Markup View with unified implementation (custom drawing for both platforms)
struct MarkupView: View {
 let image: PlatformImage
 let baseFileName: String
 let fileExtension: String
 let onSave: (PlatformImage) -> Void
 
 @Environment(\.dismiss) private var dismiss
 @EnvironmentObject var appState: AppState
 
 // Shared states
 @State private var strokes: [Stroke] = []
 @State private var currentPath: Path = Path()
 @State private var color: Color = .red
 @State private var lineWidth: CGFloat = 5.0
 @State private var textBoxes: [TextBox] = []
 @State private var addingText: Bool = false
 @State private var currentText: String = ""
 @State private var textPosition: CGPoint = .zero
 @State private var imageFrame: CGRect = .zero
 @State private var history: [MarkupState] = [] // For undo
 @State private var editingTextID: UUID? = nil
 @FocusState private var textFieldFocused: Bool
 @State private var showingFolderPicker = false
 @State private var pendingSaveImage: PlatformImage? = nil
 @State private var showSaveSuccess: Bool = false
 @State private var savedFilename: String = ""
 @State private var showCancelConfirmation: Bool = false
 @State private var previousScale: CGFloat? = nil
 
 let colors: [Color] = [.red, .green, .blue, .yellow, .purple, .orange, .black, .white]
 
 let paletteHeight: CGFloat = 80 // Increased slightly for more vertical space
 
 private var hasChanges: Bool {
     !strokes.isEmpty || !textBoxes.isEmpty
 }
 
 var body: some View {
     GeometryReader { geo in
         markupContent(geo: geo)
     }
#if os(macOS)
     .frame(width: image.platformSize.width, height: image.platformSize.height + paletteHeight)
     .nonResizableWindow()
#else
     .navigationBarHidden(true)
#endif
     .onChange(of: addingText) { newValue in
         if newValue {
             if imageFrame.size != .zero {
                 textPosition = CGPoint(x: imageFrame.midX, y: imageFrame.midY)
                 print("DEBUG: Initial text position set to screen center: \(textPosition)")
             }
             DispatchQueue.main.async {
                 textFieldFocused = true
             }
         } else {
             textFieldFocused = false
         }
     }
     .onChange(of: editingTextID) { newValue in
         if newValue != nil {
             saveToHistory()
             DispatchQueue.main.async {
                 textFieldFocused = true
             }
         } else {
             textFieldFocused = false
         }
     }
     .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
         if case .success(let folderURL) = result, let img = pendingSaveImage {
             saveImage(img, to: folderURL)
         }
         pendingSaveImage = nil
     }
     .alert("Save Successful", isPresented: $showSaveSuccess) {
         Button("OK") {}
     } message: {
         Text("Annotated image successfully saved as \(savedFilename)")
     }
     .alert("Are you sure you want to exit and discard changes?", isPresented: $showCancelConfirmation) {
         Button("Discard Changes", role: .destructive) {
             dismiss()
         }
         Button("Cancel", role: .cancel) {}
     }
#if os(iOS)
     .toolbar {
         if addingText || editingTextID != nil {
             ToolbarItemGroup(placement: .keyboard) {
                 Spacer()
                 Button("Done") {
                     if addingText {
                         commitText()
                     } else {
                         editingTextID = nil
                     }
                 }
             }
         }
     }
#endif
 }
 
 private func markupContent(geo: GeometryProxy) -> some View {
     #if os(iOS)
     let isLandscape = geo.size.width > geo.size.height
     let inset = geo.safeAreaInsets
     let effectiveWidth = geo.size.width - inset.leading - inset.trailing
     let effectiveHeight = geo.size.height - inset.top - inset.bottom
     let paletteAdjustedHeight = effectiveHeight - paletteHeight
     let scale = isLandscape ? paletteAdjustedHeight / image.platformSize.height : effectiveWidth / image.platformSize.width
     let displaySize = CGSize(width: image.platformSize.width * scale, height: image.platformSize.height * scale)
     let axes: Axis.Set = isLandscape ? .horizontal : .vertical
     
     return ZStack {
         VStack(spacing: 0) {
             ScrollViewReader { proxy in
                 ScrollView(axes) {
                     if isLandscape {
                         HStack(spacing: 0) {
                             Spacer()
                             VStack(spacing: 0) {
                                 Spacer()
                                 annotationZStack(displaySize: displaySize, geo: geo)
                                     .id("annotation")
                                 Spacer()
                             }
                             .frame(maxHeight: .infinity)
                             Spacer()
                         }
                         .frame(minWidth: geo.size.width)
                     } else {
                         VStack(spacing: 0) {
                             Spacer()
                             HStack(spacing: 0) {
                                 Spacer()
                                 annotationZStack(displaySize: displaySize, geo: geo)
                                     .id("annotation")
                                 Spacer()
                             }
                             .frame(maxWidth: .infinity)
                             Spacer()
                         }
                         .frame(minHeight: paletteAdjustedHeight)
                     }
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
                 .simultaneousGesture(DragGesture(minimumDistance: 0))
                 .onAppear {
                     proxy.scrollTo("annotation", anchor: .center)
                 }
             }
             FloatingPaletteView(color: $color, lineWidth: $lineWidth, addingText: $addingText, colors: colors,
                                 onStartAddingText: {
                                     addingText = true
                                 },
                                 onUndo: undoLastAction,
                                 onClear: clearAll,
                                 canUndo: canUndo,
                                 onCancel: {
                                     if hasChanges {
                                         showCancelConfirmation = true
                                     } else {
                                         dismiss()
                                     }
                                 },
                                 onSaveFile: {
                                     if let img = renderAnnotatedImage() {
                                         if let folderURL = appState.settings.outputDirectory {
                                             saveImage(img, to: folderURL)
                                         } else {
                                             pendingSaveImage = img
                                             showingFolderPicker = true
                                         }
                                     }
                                 },
                                 onDone: {
                                     if let updatedImage = renderAnnotatedImage() {
                                         onSave(updatedImage)
                                     }
                                     dismiss()
                                 })
             .frame(height: paletteHeight)
             .frame(maxWidth: .infinity)
             .background(Color.gray.opacity(0.1))
         }
         
         Button {
             if hasChanges {
                 showCancelConfirmation = true
             } else {
                 dismiss()
             }
         } label: {
             Image(systemName: "xmark.circle.fill")
                 .font(.system(size: 30))
                 .foregroundColor(.gray)
         }
         .position(x: geo.size.width - 20 - geo.safeAreaInsets.trailing, y: geo.safeAreaInsets.top + 20)
     }
     .applySafeAreaPadding(.top, geo.safeAreaInsets.top)
     .applySafeAreaPadding(.bottom, geo.safeAreaInsets.bottom)
     #else
     let availableW = geo.size.width
     let availableH = geo.size.height - paletteHeight
     let scale = min(availableW / image.platformSize.width, availableH / image.platformSize.height, 1.0)
     let displaySize = CGSize(width: image.platformSize.width * scale, height: image.platformSize.height * scale)
     
     let vPadding = max(0, (availableH - displaySize.height) / 2)
     let hPadding = max(0, (availableW - displaySize.width) / 2)
     
     return VStack(spacing: 0) { // Zero spacing for full height
         if vPadding > 0 {
             Color.clear
                 .frame(height: vPadding)
         }
         HStack {
             if hPadding > 0 {
                 Color.clear
                     .frame(width: hPadding)
             }
             annotationZStack(displaySize: displaySize, geo: geo)
             if hPadding > 0 {
                 Color.clear
                     .frame(width: hPadding)
             }
         }
         .frame(height: displaySize.height)
         // Palette at bottom, full width, no scrolling - vertical layout
         FloatingPaletteView(color: $color, lineWidth: $lineWidth, addingText: $addingText, colors: colors,
                             onStartAddingText: {
                                 addingText = true
                             },
                             onUndo: undoLastAction,
                             onClear: clearAll,
                             canUndo: canUndo,
                             onCancel: {
                                 if hasChanges {
                                     showCancelConfirmation = true
                                 } else {
                                     dismiss()
                                 }
                             },
                             onSaveFile: {
                                 if let img = renderAnnotatedImage() {
                                     if let folderURL = appState.settings.outputDirectory {
                                         saveImage(img, to: folderURL)
                                     } else {
                                         pendingSaveImage = img
                                         showingFolderPicker = true
                                     }
                                 }
                             },
                             onDone: {
                                 if let updatedImage = renderAnnotatedImage() {
                                     onSave(updatedImage)
                                 }
                                 dismiss()
                             })
         .frame(height: paletteHeight)
         .frame(maxWidth: .infinity)
         .background(Color.gray.opacity(0.1))
     }
     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
     #endif
 }
 
 private func annotationZStack(displaySize: CGSize, geo: GeometryProxy) -> some View {
     ZStack {
         Color.white
             .allowsHitTesting(false)
         Image(platformImage: image)
             .resizable()
             .aspectRatio(contentMode: .fit)
             .frame(width: displaySize.width, height: displaySize.height)
             .allowsHitTesting(false)
             .background(
                 GeometryReader { bgGeo in
                     Color.clear.preference(key: FramePreferenceKey.self, value: bgGeo.frame(in: .named("markupZStack")))
                 }
             )
         // Unified: Custom drawing for both platforms
         strokesOverlay
         currentPathOverlay
         // Shared: Text overlays
         textBoxesOverlay
         addingTextOverlay
     }
     .frame(width: displaySize.width, height: displaySize.height)
     .coordinateSpace(name: "markupZStack")
     .background(Color.clear.contentShape(Rectangle()))
     .gesture(
         DragGesture(minimumDistance: 0)
             .onChanged { value in
                 print("DEBUG: Drag changed at \(value.location)") // Debug log
                 if !addingText && editingTextID == nil {
                     addPoint(to: $currentPath, point: value.location)
                 }
             }
             .onEnded { value in
                 print("DEBUG: Drag ended at \(value.location)") // Debug log
                 let loc = value.location
                 if addingText {
                     textPosition = loc
                     print("DEBUG: Tap location: \(loc)")
                 } else if editingTextID == nil {
                     addPoint(to: $currentPath, point: loc)
                     saveToHistory()
                     strokes.append(Stroke(path: currentPath, color: color, lineWidth: lineWidth))
                     currentPath = Path()
                 }
             }
     )
     .onTapGesture {
         if editingTextID != nil || addingText {
             textFieldFocused = false
             if addingText {
                 commitText()
             } else {
                 editingTextID = nil
             }
         }
     }
     .onAppear {
         print("DEBUG: MarkupView appeared with image size: \(image.platformSize)")
     }
     .onPreferenceChange(FramePreferenceKey.self) { frame in
         let newScale = frame.size.width / image.platformSize.width
         if let prev = previousScale, prev != newScale, prev > 0 {
             let ratio = newScale / prev
             for i in 0..<strokes.count {
                 strokes[i].path = strokes[i].path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
             }
             for i in 0..<textBoxes.count {
                 textBoxes[i].position = CGPoint(x: textBoxes[i].position.x * ratio, y: textBoxes[i].position.y * ratio)
             }
             if !currentPath.isEmpty {
                 currentPath = currentPath.applying(CGAffineTransform(scaleX: ratio, y: ratio))
             }
             if addingText {
                 textPosition = CGPoint(x: textPosition.x * ratio, y: textPosition.y * ratio)
             }
         }
         previousScale = newScale
         imageFrame = frame
         print("DEBUG: Image frame updated: \(imageFrame)")
     }
     .onChange(of: imageFrame) { newFrame in
         if addingText && newFrame.size != .zero && textPosition == .zero {
             textPosition = CGPoint(x: newFrame.midX, y: newFrame.midY)
             DispatchQueue.main.async {
                 textFieldFocused = true
             }
         }
     }
 }
 
 private var strokesOverlay: some View {
     ForEach(strokes) { stroke in
         stroke.path
             .stroke(stroke.color, style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
             .allowsHitTesting(false)
     }
 }
 
 private var currentPathOverlay: some View {
     currentPath
         .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
         .allowsHitTesting(false)
 }
 
 @ViewBuilder
 private func textOverlay(for box: Binding<TextBox>) -> some View {
     if editingTextID == box.wrappedValue.id {
         editableTextView(for: box)
     } else {
         draggableTextView(for: box)
     }
 }
 
 private func editableTextView(for box: Binding<TextBox>) -> some View {
     let boxValue = box.wrappedValue
     let textColor = boxValue.color
     let editPosition = boxValue.position
     
     let baseTextField = TextField("Edit text", text: box.text, axis: .vertical)
         .font(.system(size: 20))
         .foregroundColor(textColor)
         .focused($textFieldFocused)
     
     let committedTextField = baseTextField
         .onSubmit {
             editingTextID = nil
         }
     
     let positionedView = committedTextField
         .position(editPosition)
         .onTapGesture {} // Consume tap to prevent parent onTap from defocusing
     
     return positionedView
 }
 
 private func draggableTextView(for box: Binding<TextBox>) -> some View {
     DraggableText(box: box, onTap: {
         editingTextID = box.wrappedValue.id
     })
 }
 
 private var textBoxesOverlay: some View {
     ForEach($textBoxes) { $box in
         textOverlay(for: $box)
     }
 }
 
 private var addingTextOverlay: some View {
     Group {
         if addingText {
             let addColor = color
             
             let baseTextField = TextField("Enter text", text: $currentText, axis: .vertical)
                 .textFieldStyle(.roundedBorder)
                 .font(.system(size: 20))
                 .foregroundColor(addColor)
                 .focused($textFieldFocused)
             
             let committedTextField = baseTextField
                 .onSubmit {
                     commitText()
                 }
             
             let positionedView = committedTextField
                 .frame(width: 200)
                 .position(textPosition)
                 .onTapGesture {} // Consume tap to prevent parent onTap from defocusing
             
             positionedView
         }
     }
 }
 
 private func commitText() {
     if !currentText.isEmpty {
         saveToHistory()
         let textColor = color
         let finalPosition = textPosition
         textBoxes.append(TextBox(text: currentText, position: finalPosition, color: textColor))
     }
     addingText = false
     currentText = ""
     textFieldFocused = false
 }
 
 private var canUndo: Bool {
     !history.isEmpty
 }
 
 private func saveToHistory() {
     history.append(MarkupState(strokes: strokes, textBoxes: textBoxes))
 }
 
 private func undoLastAction() {
     guard !history.isEmpty else { return }
     let previous = history.removeLast()
     strokes = previous.strokes
     textBoxes = previous.textBoxes
     currentPath = Path()
     editingTextID = nil
 }
 
 private func clearAll() {
     saveToHistory()
     strokes = []
     currentPath = Path()
     textBoxes = []
     editingTextID = nil
 }
 
 private func addPoint(to path: Binding<Path>, point: CGPoint) {
     if path.wrappedValue.isEmpty {
         path.wrappedValue.move(to: point)
     } else {
         path.wrappedValue.addLine(to: point)
     }
 }
 
 private func renderAnnotatedImage() -> PlatformImage? {
     guard imageFrame.size != .zero else {
         print("DEBUG: Skipping render due to zero image frame")
         return nil
     }
     
     let displayedSize = imageFrame.size
     let annotationScale = image.platformSize.width / displayedSize.width
     let offset = CGPoint.zero
     let renderer = PlatformRendererFactory.renderer
     return renderer.render(image: image, strokes: strokes, textBoxes: textBoxes, annotationScale: annotationScale, offset: offset)
 }
 
 private func saveImage(_ image: PlatformImage, to folderURL: URL) {
     let fm = FileManager.default
     var num = 1
     var newURL = folderURL.appendingPathComponent("\(baseFileName)_annotated_\(num).\(fileExtension)")
     let extLower = fileExtension.lowercased()
     
     var isDirectory: ObjCBool = false
     guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
         print("Invalid folder")
         return
     }
     
     do {
         try withSecureAccess(to: folderURL) {
             while fm.fileExists(atPath: newURL.path) {
                 num += 1
                 newURL = folderURL.appendingPathComponent("\(baseFileName)_annotated_\(num).\(fileExtension)")
             }
             
             if let data = image.platformData(forType: extLower) {
                 try data.write(to: newURL)
                 print("Saved to \(newURL.path)")
                 DispatchQueue.main.async {
                     self.savedFilename = newURL.lastPathComponent
                     self.showSaveSuccess = true
                 }
             } else {
                 print("Unsupported file format")
             }
         }
     } catch {
         print("Error saving image: \(error)")
     }
 }
}

struct DraggableText: View {
 @Binding var box: TextBox
 @GestureState private var translation: CGSize = .zero
 let onTap: () -> Void
 
 var body: some View {
     let currentColor = box.color
     let basePosition = box.position
     let currentPosition = CGPoint(
         x: basePosition.x + translation.width,
         y: basePosition.y + translation.height
     )
     
     let textView = Text(box.text)
         .font(.system(size: 20))
         .foregroundColor(currentColor)
     
     let positionedText = textView
         .position(currentPosition)
     
     let draggedText = positionedText
         .gesture(
             DragGesture()
                 .updating($translation) { value, state, _ in
                     state = value.translation
                 }
                 .onEnded { value in
                     var newPosition = box.position
                     newPosition.x += value.translation.width
                     newPosition.y += value.translation.height
                     box.position = newPosition
                     print("DEBUG: Dragged text to relative: \(box.position)")
                 }
         )
     
     let tappableText = draggedText
         .onTapGesture(perform: onTap)
     
     return tappableText
 }
}

struct ColorPickerButton: View {
 let col: Color
 let isSelected: Bool

 var body: some View {
 Circle()
 .fill(col)
 .frame(width: 14, height: 14)
 .overlay {
 if isSelected {
 Circle()
 .stroke(Color.gray, lineWidth: 1)
 } else {
 Circle()
 .stroke(Color.clear, lineWidth: 1)
 }
 }
 }
}

struct FloatingPaletteView: View {
 @Binding var color: Color
 @Binding var lineWidth: CGFloat
 @Binding var addingText: Bool
 let colors: [Color]
 let onStartAddingText: () -> Void
 let onUndo: () -> Void
 let onClear: () -> Void
 let canUndo: Bool
 var onCancel: () -> Void
 var onSaveFile: () -> Void
 var onDone: () -> Void
 
 var body: some View {
     HStack(spacing: 8) {
         // Tools group
         HStack(spacing: 8) {
             Button {
                 if addingText {
                     addingText = false
                 } else {
                     onStartAddingText()
                 }
             } label: {
                 Image(systemName: "textformat.size")
             }
             .buttonStyle(.bordered)
             .frame(width: 44, height: 44)
             
             Button {
                 onUndo()
             } label: {
                 Image(systemName: "arrow.uturn.backward.circle")
             }
             .buttonStyle(.bordered)
             .disabled(!canUndo)
             .frame(width: 44, height: 44)
             
             Button {
                 onClear()
             } label: {
                 Image(systemName: "xmark.circle")
             }
             .buttonStyle(.bordered)
             .frame(width: 44, height: 44)
         }
         
         Spacer()
         
         // Color group
         HStack(spacing: 4) {
             Text("Pen Color:")
                 .font(.caption)
             
             ForEach(colors, id: \.self) { col in
                 Button(action: { color = col }) {
                     ColorPickerButton(col: col, isSelected: col == $color.wrappedValue)
                 }
                 .buttonStyle(.plain)
             }
         }
         
         Spacer()
         
         // Width group
         HStack(spacing: 8) {
             Text("Width:")
                 .font(.caption)
             
             Slider(value: $lineWidth, in: 1...20)
                 .frame(width: 100) // Slightly wider slider for better usability
         }
         
         Spacer()
         
         // Actions group
         HStack(spacing: 8) {
             Button {
                 onCancel()
             } label: {
                 Image(systemName: "xmark")
             }
             .buttonStyle(.borderedProminent)
             .frame(width: 44, height: 44)
             
             Button {
                 onSaveFile()
             } label: {
                 Image(systemName: "square.and.arrow.down")
             }
             .buttonStyle(.borderedProminent)
             .frame(width: 44, height: 44)
             
             Button {
                 onDone()
             } label: {
                 Image(systemName: "checkmark")
             }
             .buttonStyle(.borderedProminent)
             .frame(width: 44, height: 44)
         }
     }
     .padding(.horizontal, 8)
     .background(Color.gray.opacity(0.1))
     .cornerRadius(8)
     .shadow(radius: 4)
     .padding(.horizontal)
 }
}

#if os (iOS)
extension View {
    @ViewBuilder
    func applySafeAreaPadding(_ edge: Edge.Set, _ length: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.safeAreaPadding(edge, length)
        } else {
            self.padding(edge, length)
        }
    }
}
#endif

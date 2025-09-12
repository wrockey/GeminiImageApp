// HistoryView.swift
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HistoryView: View {
 @Binding var imageSlots: [ImageSlot]
 @EnvironmentObject var appState: AppState
 @State private var showDeleteAlert: Bool = false
 @State private var selectedHistoryItem: HistoryItem?
 @State private var showClearHistoryAlert: Bool = false
 @State private var searchText: String = ""
 @Binding var columnVisibility: NavigationSplitViewVisibility
 
 #if os(macOS)
 @available(macOS 13.0, *)
 @Environment(\.openWindow) private var openWindow
 #else
 @Environment(\.dismiss) private var dismiss // ADDED: To dismiss the history sheet on iOS
 #endif
 
 private var dateFormatter: DateFormatter {
 let formatter = DateFormatter()
 formatter.dateStyle = .short
 formatter.timeStyle = .short
 return formatter
 }
 
 private var filteredHistory: [HistoryItem] {
 if searchText.isEmpty {
 return appState.historyState.history
 } else {
 return appState.historyState.history.filter { item in
 item.prompt.lowercased().contains(searchText.lowercased()) ||
 dateFormatter.string(from: item.date).lowercased().contains(searchText.lowercased())
 }
 }
 }
 
 var body: some View {
 VStack(alignment: .leading) {
 header
 searchField
 historyList
 }
 .frame(minWidth: 200, maxHeight: .infinity)
 .navigationTitle("History")
 .alert("Delete History Item", isPresented: $showDeleteAlert) {
 Button("Delete Prompt Only") {
 deleteHistoryItem(deleteFile: false)
 }
 Button("Delete Prompt and Image File", role: .destructive) {
 deleteHistoryItem(deleteFile: true)
 }
 Button("Cancel", role: .cancel) {}
 } message : {
 Text("Do you want to delete just the prompt or also the associated image file?")
 }
 .alert("Clear History", isPresented: $showClearHistoryAlert) {
 Button("Yes", role: .destructive) {
 clearHistory()
 }
 Button("Cancel", role: .cancel) {}
 } message: {
 Text("Are you sure you want to clear the history?")
 }
 }
 
 private var header: some View {
 HStack {
 Button(action: {
 withAnimation(.easeInOut(duration: 0.3)) {
 columnVisibility = columnVisibility == .all ? .detailOnly : .all
 }
 }) {
 Image(systemName: "chevron.left")
 .symbolRenderingMode(.hierarchical)
 }
 .buttonStyle(.plain)
 .help("Collapse history sidebar")
 .accessibilityLabel("Collapse history sidebar")
 
 Text("History")
 .font(.system(.headline, design: .default, weight: .semibold))
 .kerning(0.2)
 
 Spacer()
 
 Button(action: {
 showClearHistoryAlert = true
 }) {
 Image(systemName: "trash")
 .symbolRenderingMode(.hierarchical)
 .foregroundColor(.red.opacity(0.8))
 }
 .buttonStyle(.borderless)
 .help("Clear all history")
 }
 .padding(.horizontal)
 }
 
 private var searchField: some View {
 TextField("Search prompts or dates...", text: $searchText)
 .textFieldStyle(.roundedBorder)
 .padding(.horizontal)
 }
 
 private var historyList: some View {
 List {
 if filteredHistory.isEmpty {
 Text("No history yet.")
 .foregroundColor(.secondary)
 } else {
 ForEach(filteredHistory.sorted(by: { $0.date > $1.date })) { item in
 itemRow(for: item)
 }
 }
 }
 .listStyle(.plain)
 }
 
 private func itemRow(for item: HistoryItem) -> some View {
 HStack(spacing: 12) {
 thumbnail(for: item)
 
 VStack(alignment: .leading, spacing: 4) {
 Text(item.prompt.prefix(50) + (item.prompt.count > 50 ? "..." : ""))
 .font(.subheadline)
 .lineLimit(1)
 Text(dateFormatter.string(from: item.date))
 .font(.caption)
 .foregroundColor(.secondary)
 if let mode = item.mode {
 Text(mode == .gemini ? "Gemini" : (item.workflowName ?? "ComfyUI"))
 .font(.caption)
 .foregroundColor(.secondary)
 }
 }
 
 Spacer()
 
 Button(action: {
 #if os(macOS)
 if #available(macOS 13.0, *) {
 openWindow(id: "history-viewer", value: item.id)
 } else {
 // Fallback for older macOS if needed
 }
 #else
 dismiss() // ADDED: Dismiss history sheet before presenting full item sheet
 appState.showFullHistoryItem = item.id
 #endif
 }) {
 Image(systemName: "magnifyingglass.circle.fill")
 .foregroundColor(.blue.opacity(0.8))
 .font(.system(size: 20))
 .symbolRenderingMode(.hierarchical)
 }
 .buttonStyle(.borderless)
 .help("View full image")
 
 Button(action: {
 selectedHistoryItem = item
 showDeleteAlert = true
 }) {
 Image(systemName: "trash.circle.fill")
 .foregroundColor(.red.opacity(0.8))
 .font(.system(size: 20))
 .symbolRenderingMode(.hierarchical)
 }
 .buttonStyle(.borderless)
 .help("Delete history item")
 
 Button(action: {
 if let img = loadHistoryImage(for: item) {
 imageSlots.append(ImageSlot(path: item.imagePath ?? "", image: img))
 }
 }) {
 Image(systemName: "plus.circle.fill")
 .foregroundColor(.blue.opacity(0.8))
 .font(.system(size: 20))
 .symbolRenderingMode(.hierarchical)
 }
 .buttonStyle(.borderless)
 .help("Add to input images")
 }
 .padding(.vertical, 4)
 .contextMenu {
 Button("Copy Prompt") {
 copyPromptToClipboard(item.prompt)
 }
 }
 .draggable(item.imagePath.map { URL(fileURLWithPath: $0) } ?? URL(string: "")!)
 }
 
 private func thumbnail(for item: HistoryItem) -> some View {
 Group {
 if let img = loadHistoryImage(for: item) {
 Image(platformImage: img)
 .resizable()
 .scaledToFit()
 .frame(width: 50, height: 50)
 .cornerRadius(12)
 .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
 } else {
 Image(systemName: "photo")
 .font(.system(size: 50))
 .foregroundColor(.secondary)
 }
 }
 }
 
 private func copyPromptToClipboard(_ prompt: String) {
 PlatformPasteboard.clearContents()
 PlatformPasteboard.writeString(prompt)
 }
 
 private func deleteHistoryItem(deleteFile: Bool) {
 guard let item = selectedHistoryItem else { return }
 
 if deleteFile, let path = item.imagePath {
 let fileURL = URL(fileURLWithPath: path)
 let fileManager = FileManager.default
 if let dir = appState.settings.outputDirectory {
 do {
 try withSecureAccess(to: dir) {
 try fileManager.removeItem(at: fileURL)
 }
 } catch {
 // Handle error if needed, but for simplicity, skip alert here
 }
 }
 }
 
 if let index = appState.historyState.history.firstIndex(where: { $0.id == item.id }) {
 appState.historyState.history.remove(at: index)
 appState.historyState.saveHistory()
 }
 
 selectedHistoryItem = nil
 }
 
 private func clearHistory() {
 appState.historyState.history.removeAll()
 appState.historyState.saveHistory()
 }
 
 private func loadHistoryImage(for item: HistoryItem) -> PlatformImage? {
 guard let path = item.imagePath else { return nil }
 let fileURL = URL(fileURLWithPath: path)
 if let dir = appState.settings.outputDirectory {
 let didStart = dir.startAccessingSecurityScopedResource()
 let image = PlatformImage(contentsOfFile: fileURL.path)
 if didStart {
 dir.stopAccessingSecurityScopedResource()
 }
 return image
 } else {
 return PlatformImage(contentsOfFile: fileURL.path)
 }
 }
}

struct FullHistoryItemView: View {
 let initialId: UUID
 @EnvironmentObject var appState: AppState
 @State private var currentIndex: Int = -1
 @State private var showDeleteAlert: Bool = false
 @State private var showCopiedMessage: Bool = false
 
 private var dateFormatter: DateFormatter {
 let formatter = DateFormatter()
 formatter.dateStyle = .short
 formatter.timeStyle = .short
 return formatter
 }
 
 private var history: [HistoryItem] {
 appState.historyState.history.sorted(by: { $0.date > $1.date })
 }
 
 private var currentItem: HistoryItem? {
 guard currentIndex >= 0 && currentIndex < history.count else { return nil }
 return history[currentIndex]
 }
 
 var body: some View {
 Group {
 if let item = currentItem {
 VStack(spacing: 16) {
 if let img = loadHistoryImage(for: item) {
 Image(platformImage: img)
 .resizable()
 .scaledToFit()
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 } else {
 Text("No image available")
 .font(.headline)
 .foregroundColor(.secondary)
 }
 
 VStack(alignment: .center, spacing: 4) {
 HStack(alignment: .center) {
 Text("Prompt: \(item.prompt)")
 .font(.body)
 Button(action: {
 copyPromptToClipboard(item.prompt)
 showCopiedMessage = true
 DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
 withAnimation(.easeOut(duration: 0.3)) {
 showCopiedMessage = false
 }
 }
 }) {
 Image(systemName: "doc.on.doc")
 .foregroundColor(.blue.opacity(0.8))
 .symbolRenderingMode(.hierarchical)
 }
 .buttonStyle(.borderless)
 .help("Copy prompt to clipboard")
 }
 Text("Date: \(dateFormatter.string(from: item.date))")
 .font(.caption)
 .foregroundColor(.secondary)
 if let mode = item.mode {
 Text("Created with: \(mode == .gemini ? "Gemini" : (item.workflowName ?? "ComfyUI"))")
 .font(.caption)
 .foregroundColor(.secondary)
 }
 }
 .padding()
 
 Spacer()
 
 HStack {
 Button(action: {
 currentIndex = max(0, currentIndex - 1)
 }) {
 Image(systemName: "arrow.left.circle.fill")
 .font(.system(size: 24))
 .symbolRenderingMode(.hierarchical)
 }
 .disabled(currentIndex == 0)
 .buttonStyle(.plain)
 
 Spacer()
 
 Button(action: {
 showDeleteAlert = true
 }) {
 Image(systemName: "trash.circle.fill")
 .font(.system(size: 24))
 .symbolRenderingMode(.hierarchical)
 .foregroundColor(.red.opacity(0.8))
 }
 .buttonStyle(.plain)
 
 Spacer()
 
 Button(action: {
 if let img = loadHistoryImage(for: item) {
 appState.ui.imageSlots.append(ImageSlot(path: item.imagePath ?? "", image: img))
 }
 }) {
 Image(systemName: "plus.circle.fill")
 .font(.system(size: 24))
 .symbolRenderingMode(.hierarchical)
 .foregroundColor(.blue.opacity(0.8))
 }
 .buttonStyle(.plain)
 .help("Add to input images")
 
 Spacer()
 
 Button(action: {
 currentIndex = min(history.count - 1, currentIndex + 1)
 }) {
 Image(systemName: "arrow.right.circle.fill")
 .font(.system(size: 24))
 .symbolRenderingMode(.hierarchical)
 }
 .disabled(currentIndex == history.count - 1)
 .buttonStyle(.plain)
 }
 .padding()
 }
 .alert("Delete History Item", isPresented: $showDeleteAlert) {
 Button("Delete Prompt Only") {
 deleteHistoryItem(item: item, deleteFile: false)
 }
 Button("Delete Prompt and Image File", role: .destructive) {
 deleteHistoryItem(item: item, deleteFile: true)
 }
 Button("Cancel", role: .cancel) {}
 } message: {
 Text("Do you want to delete just the prompt or also the associated image file?")
 }
 .overlay {
 if showCopiedMessage {
 Text("Copied to Clipboard")
 .font(.headline)
 .padding()
 .background(Color.black.opacity(0.7))
 .foregroundColor(.white)
 .cornerRadius(10)
 .transition(.opacity)
 .frame(maxHeight: .infinity, alignment: .top)
 .padding(.top, 50)
 }
 }
 } else {
 Text("No item selected")
 .font(.headline)
 .foregroundColor(.secondary)
 }
 }
 .onAppear {
 if currentIndex == -1 {
 currentIndex = history.firstIndex(where: { $0 .id == initialId }) ?? 0
 }
 }
 }
 
 private func deleteHistoryItem(item: HistoryItem, deleteFile: Bool) {
 if deleteFile, let path = item.imagePath {
 let fileURL = URL(fileURLWithPath: path)
 let fileManager = FileManager.default
 if let dir = appState.settings.outputDirectory {
 do {
 try withSecureAccess(to: dir) {
 try fileManager.removeItem(at: fileURL)
 }
 } catch {
 // Handle error if needed
 }
 }
 }
 
 if let index = appState.historyState.history.firstIndex(where: { $0.id == item.id }) {
 appState.historyState.history.remove(at: index)
 appState.historyState.saveHistory()
 }
 
 // Adjust currentIndex after deletion
 if currentIndex >= appState.historyState.history.count {
 currentIndex = max(0, appState.historyState.history.count - 1)
 }
 }
 
 private func loadHistoryImage(for item: HistoryItem) -> PlatformImage? {
 guard let path = item.imagePath else { return nil }
 let fileURL = URL(fileURLWithPath: path)
 if let dir = appState.settings.outputDirectory {
 let didStart = dir.startAccessingSecurityScopedResource()
 let image = PlatformImage(contentsOfFile: fileURL.path)
 if didStart {
 dir.stopAccessingSecurityScopedResource()
 }
 return image
 } else {
 return PlatformImage(contentsOfFile: fileURL.path)
 }
 }

 private func copyPromptToClipboard(_ prompt: String) {
 PlatformPasteboard.clearContents()
 PlatformPasteboard.writeString(prompt)
 }
}

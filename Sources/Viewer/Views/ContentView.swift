import AppKit
import GalleyCoreKit
import SwiftUI
import WebKit

struct ContentView: View {
  @Binding var fileURL: URL?
  @Environment(ViewerSettings.self) private var settings
  @Environment(ViewerAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var model = ViewerModel()
  @State private var didRestore = false
  @State private var hostWindow: NSWindow?

  /// Two-way bound title — clicking the window title opens the
  /// macOS rename popover, and the committed value flows back here.
  /// We treat any change as a rename request against `model.documentURL`.
  @State private var displayTitle: String = "Markdown Preview"

  /// Per-window persisted back/forward stack. SwiftUI's `@SceneStorage`
  /// gives each WindowGroup window its own keyspace, so two windows
  /// each get their own history that survives app relaunch.
  @SceneStorage("MarkdownEye.history") private var historyJSON: String = ""

  var body: some View {
    Group {
      if fileURL != nil {
        WebView(model.page)
          .overlay(alignment: .bottom) {
            if let error = model.lastError {
              Text(error)
                .padding(8)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                .padding()
            }
          }
      } else {
        // Empty placeholder while the launch open panel is up. The
        // window is hidden via alphaValue=0 in `launchTask`, so the
        // user only sees the open panel — never an "open a document"
        // label.
        Color.clear
      }
    }
    .background(WindowAccessor { window in
      if hostWindow == nil { hostWindow = window }
    })
    .toolbar { toolbarContent }
    .focusedSceneValue(\.viewerModel, model)
    .navigationTitle($displayTitle)
    .task(id: fileURL) { await launchTask() }
    .onChange(of: model.documentURL, initial: true) { _, _ in
      syncTitleFromModel()
      saveHistory()
    }
    .onChange(of: displayTitle) { _, new in handleTitleEdit(new) }
    .onChange(of: settings.selectedRendererID) { _, _ in
      Task { await model.reload() }
    }
    .onChange(of: settings.templateStore.selectedID) { _, _ in
      Task { await model.reload() }
    }
    .navigationDocument(model.documentURL ?? URL.homeDirectory)
  }

  private func syncTitleFromModel() {
    let title = model.documentURL?.lastPathComponent
      ?? fileURL?.lastPathComponent
      ?? "Markdown Preview"
    if displayTitle != title { displayTitle = title }
  }

  /// Treat a committed title edit as a rename of the underlying
  /// file. Reverts the field when the move fails or the title
  /// matches the current filename (no-op write from a sync-back).
  private func handleTitleEdit(_ candidate: String) {
    guard let url = model.documentURL else {
      // Placeholder window — restore default; we don't rename
      // anything because there's no document.
      let title = fileURL?.lastPathComponent ?? "Markdown Preview"
      if displayTitle != title { displayTitle = title }
      return
    }
    let current = url.lastPathComponent
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != current else {
      if displayTitle != current { displayTitle = current }
      return
    }
    Task {
      do {
        let newURL = try await model.renameCurrentDocument(toName: trimmed)
        appDelegate.record(newURL)
        // Update the WindowGroup binding so state restoration tracks
        // the renamed file rather than reopening a vanished path.
        if fileURL != newURL { fileURL = newURL }
      } catch {
        NSSound.beep()
        displayTitle = current
      }
    }
  }

  /// Drives launch wiring + initial bind + FTUE picker. Re-runs when
  /// `fileURL` changes — typically once: nil → picked URL.
  private func launchTask() async {
    model.bindSettings(settings)

    // First view to come up captures `openWindow` for the delegate
    // so Finder file opens and File > Open Recent route into new
    // windows. install() returns true when launch-time URLs flushed.
    let flushed = installOpenWindowHandlerIfNeeded()

    // History takes precedence over the WindowGroup URL — the user
    // may have been deeper in the back/forward stack at last quit.
    if !didRestore, let snapshot = decodeHistory(historyJSON) {
      didRestore = true
      await model.restore(snapshot: snapshot)
      if let current = model.documentURL { appDelegate.record(current) }
      return
    }

    if let fileURL {
      appDelegate.record(fileURL)
      await model.bind(to: fileURL)
      return
    }

    // No URL, no history — this is a fresh placeholder window.
    if flushed {
      // application(_:open:) URLs are spawning real windows of their
      // own. Drop the placeholder.
      hostWindow?.close()
      return
    }

    await runLaunchPicker()
  }

  /// FTUE: hide the placeholder window and run the open panel. If
  /// the user picks files, route the first into this same window
  /// (by writing the binding) and any extras into new windows; cancel
  /// closes the placeholder.
  private func runLaunchPicker() async {
    hostWindow?.alphaValue = 0
    let picks = appDelegate.runOpenPanel()
    guard let first = picks.first else {
      hostWindow?.close()
      return
    }
    for extra in picks.dropFirst() {
      appDelegate.record(extra)
      openWindow(value: extra)
    }
    appDelegate.record(first)
    hostWindow?.alphaValue = 1
    fileURL = first
    // Setting `fileURL` re-fires `task(id: fileURL)` which binds the
    // model and renders. No need to bind here.
  }

  @discardableResult
  private func installOpenWindowHandlerIfNeeded() -> Bool {
    guard appDelegate.openHandler == nil else { return false }
    let action = openWindow
    return appDelegate.install { url in action(value: url) }
  }

  private func saveHistory() {
    guard let snapshot = model.historySnapshot else {
      historyJSON = ""
      return
    }
    if let data = try? JSONEncoder().encode(snapshot),
       let text = String(data: data, encoding: .utf8)
    {
      historyJSON = text
    }
  }

  private func decodeHistory(_ text: String) -> HistorySnapshot? {
    guard !text.isEmpty,
          let data = text.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(
            HistorySnapshot.self, from: data),
          !snapshot.urls.isEmpty
    else { return nil }
    return snapshot
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        Task { await model.goBack() }
      } label: {
        Label("Back", systemImage: "chevron.backward")
      }
      .disabled(!model.canGoBack)
      .help("Back (⌘[)")

      Button {
        Task { await model.goForward() }
      } label: {
        Label("Forward", systemImage: "chevron.forward")
      }
      .disabled(!model.canGoForward)
      .help("Forward (⌘])")
    }
    ToolbarItem(placement: .primaryAction) {
      RendererToolbarPicker(settings: settings)
    }
    ToolbarItem(placement: .primaryAction) {
      TemplateToolbarPicker(settings: settings)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        Task { await model.reload() }
      } label: {
        Label("Reload", systemImage: "arrow.clockwise")
      }
      .help("Reload (⌘R)")
    }
  }
}

/// Resolves the host `NSWindow` so the SwiftUI view can drive
/// AppKit-only properties on it (alpha, close).
private struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow?) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    DispatchQueue.main.async { [weak view] in
      onResolve(view?.window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { [weak nsView] in
      onResolve(nsView?.window)
    }
  }
}

private struct RendererToolbarPicker: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    Menu {
      ProcessorMenu(settings: settings)
    } label: {
      Label(label, systemImage: "wand.and.stars")
    }
    .help("Markdown processor")
  }

  private var label: String {
    settings.activeEntry?.displayName ?? "No processor"
  }
}

private struct TemplateToolbarPicker: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    Menu {
      TemplateMenu(settings: settings)
    } label: {
      Label(label, systemImage: "doc.richtext")
    }
    .help("Template")
  }

  private var label: String {
    settings.templateStore.selected.name
  }
}

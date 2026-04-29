import AppKit
import GalleyCoreKit
import SwiftUI
import WebKit

struct ContentView: View {
  @Binding var fileURL: URL?
  @Environment(ViewerSettings.self) private var settings
  @Environment(ViewerAppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismiss) private var dismiss
  @State private var model = ViewerModel()
  @State private var didRestore = false
  @State private var hostWindow: NSWindow?

  /// Per-window persisted back/forward stack. SwiftUI's `@SceneStorage`
  /// gives each WindowGroup window its own keyspace, so two windows
  /// each get their own history that survives app relaunch.
  @SceneStorage("MarkdownEye.history") private var historyJSON: String = ""

  /// Per-window renderer / template overrides. `nil` means "no
  /// override — use the global selection." Only honored when
  /// `ViewerSettings.enablePerDocumentOverrides` is on.
  @SceneStorage("MarkdownEye.overrideRendererID")
  private var overrideRendererID: String = ""
  @SceneStorage("MarkdownEye.overrideTemplateID")
  private var overrideTemplateID: String?

  /// Per-window template choice. Reads/writes the `@SceneStorage`
  /// slot above so the override is persisted automatically. The
  /// `.global` value renders as "Use Global Setting" in the menu and
  /// is the resolved template when no window-local pick is active.
  private var templateChoice: SceneTemplateChoice {
    SceneTemplateChoice(
      source: settings.templateChoice,
      storage: $overrideTemplateID)
  }

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
    .background(WindowAccessor(
      onAttach: { window in
        if hostWindow == nil {
          hostWindow = window
          // Every window opens hidden until content is bound. State
          // restoration applies the URL ~half a second after a view
          // mounts, and a fresh placeholder sits empty until the
          // open panel returns. We can't predict the order of this
          // resolve vs. .task firing — if a previous fire already
          // bound content (e.g. openWindow(value:) → immediate
          // bind), unhide right away.
          window?.alphaValue = (model.documentURL == nil) ? 0 : 1
        }
        if let window {
          // Merge into the frontmost window's tab group if this open
          // came in under the `newTab` behavior. Has to happen as
          // soon as the new window exists so the user never sees
          // it as a separate floating window first.
          if let host = appDelegate.consumePendingTabHost(),
             host !== window
          {
            host.addTabbedWindow(window, ordered: .above)
          }
          appDelegate.registerWindow(window) { newURL in
            replaceDocument(with: newURL)
          }
        }
      },
      onDetach: { window in
        if let window { appDelegate.unregisterWindow(window) }
      }))
    .toolbar { toolbarContent }
    .modifier(SceneValuesModifier(
      model: model,
      templateChoice: templateChoice,
      renameContext: RenameContext(
        url: model.documentURL,
        apply: { newURL in
          appDelegate.record(newURL)
          if fileURL != newURL { fileURL = newURL }
        })))
    .navigationTitle(model.documentURL?.lastPathComponent
      ?? fileURL?.lastPathComponent
      ?? "Markdown Preview")
    .task(id: fileURL) { await launchTask() }
    .onChange(of: model.documentURL) { _, new in
      saveHistory()
      // First time content is bound (whether via initial bind,
      // restore, or in-window navigation), reveal the window.
      if new != nil { hostWindow?.alphaValue = 1 }
    }
    .onChange(of: settings.selectedProcessorID) { reloadModel() }
    .onChange(of: settings.templateChoice.selected) { reloadModel() }
    .onChange(of: settings.enablePerDocumentOverrides) { reloadModel() }
    .onChange(of: overrideTemplateID) { reloadModel() }
    .onChange(of: model.overrideRendererID) { _, new in
      overrideRendererID = new ?? ""
    }
    .navigationDocument(model.documentURL ?? URL.homeDirectory)
  }

  private func reloadModel() {
    Task { await model.reload() }
  }

  /// Swap this window's bound document for `newURL` in place. Used by
  /// the `replaceCurrent` open behavior. Updates the WindowGroup
  /// binding so state restoration follows, and rebinds the model so
  /// history/watcher restart on the new URL.
  private func replaceDocument(with newURL: URL) {
    appDelegate.record(newURL)
    if fileURL != newURL { fileURL = newURL }
    Task { await model.bind(to: newURL) }
  }

  /// Drives launch wiring + initial bind + FTUE picker. Re-runs when
  /// `fileURL` changes — typically once: nil → picked URL.
  private func launchTask() async {
    model.bindSettings(settings, templateChoice: templateChoice)
    // Keep the delegate's settings reference fresh — `application(_:open:)`
    // and Open Recent dispatch consult `openBehavior` from there.
    appDelegate.settings = settings
    // Hydrate the renderer override from scene storage on first run;
    // subsequent fires are no-ops since we only write when the value
    // actually differs.
    let storedRenderer = overrideRendererID.isEmpty
      ? nil : overrideRendererID
    if model.overrideRendererID != storedRenderer {
      model.overrideRendererID = storedRenderer
    }

    // First view to come up captures `openWindow` for the delegate
    // so Finder file opens and File > Open Recent route into new
    // windows. install() returns true when launch-time URLs flushed.
    let flushed = installOpenWindowHandlerIfNeeded()

    // SwiftUI fires `.task(id:)` more than once even when the id
    // is stable (the modifier is recreated on body re-eval). If a
    // previous fire already bound or restored content, we're done.
    if model.documentURL != nil { return }

    // Restore a saved session (back/forward stack) for this scene.
    if !didRestore, let snapshot = decodeHistory(historyJSON) {
      didRestore = true
      await model.restore(snapshot: snapshot)
      if let current = model.documentURL { appDelegate.record(current) }
      return
    }

    // Initial bind for a freshly-opened URL.
    if let fileURL {
      appDelegate.record(fileURL)
      await model.bind(to: fileURL)
      return
    }

    // application(_:open:) URLs are spawning real windows of their
    // own. Drop the placeholder.
    if flushed {
      dismiss()
      return
    }

    // Truly empty placeholder — wait for launch (and any in-flight
    // state restoration) to settle, then run the FTUE picker.
    await runLaunchPicker()
  }

  /// FTUE: wait for app launch to settle, then run the open panel.
  /// If the user picks files, route the first into this same window
  /// (by writing the binding) and any extras into new windows;
  /// cancel closes the placeholder.
  ///
  /// The window is already alpha=0 from `WindowAccessor` and will
  /// stay hidden until `model.documentURL` becomes non-nil — set
  /// when the picked file binds.
  private func runLaunchPicker() async {
    // Wait for AppKit to finish launching. State restoration is
    // complete by then, so any restored window's URL has already
    // landed in its scene's binding — this window is genuinely
    // the empty placeholder, not a restored window in transit.
    while !appDelegate.didFinishLaunching {
      try? await Task.sleep(for: .milliseconds(50))
      if Task.isCancelled { return }
    }
    if Task.isCancelled || fileURL != nil { return }

    let picks = appDelegate.runOpenPanel()
    guard let first = picks.first else {
      dismiss()
      return
    }
    for extra in picks.dropFirst() {
      appDelegate.record(extra)
      openWindow(value: extra)
    }
    appDelegate.record(first)
    fileURL = first
    // Setting `fileURL` re-fires `task(id: fileURL)` which binds
    // the model. The bind sets model.documentURL, which our
    // .onChange flips alphaValue=1 — revealing the window with
    // content already rendered.
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

/// Publishes the per-window scene values commands rely on. Lifted
/// out of `ContentView.body` to keep the modifier chain short enough
/// for the type-checker.
private struct SceneValuesModifier: ViewModifier {
  let model: ViewerModel
  let templateChoice: SceneTemplateChoice
  let renameContext: RenameContext

  func body(content: Content) -> some View {
    content
      .focusedSceneValue(\.viewerModel, model)
      .focusedSceneValue(\.viewerTemplateChoice, templateChoice)
      .focusedSceneValue(\.viewerRenameContext, renameContext)
  }
}

/// Resolves the host `NSWindow` so the SwiftUI view can drive
/// AppKit-only properties on it (alpha, close). Reports through
/// `viewDidMoveToWindow` so the resolution is synchronous with
/// AppKit attachment — async dispatch raced the `.task` that drives
/// the launch picker, leaving `hostWindow` nil when it was needed.
private struct WindowAccessor: NSViewRepresentable {
  let onAttach: (NSWindow?) -> Void
  let onDetach: (NSWindow?) -> Void

  init(
    onAttach: @escaping (NSWindow?) -> Void,
    onDetach: @escaping (NSWindow?) -> Void = { _ in }
  ) {
    self.onAttach = onAttach
    self.onDetach = onDetach
  }

  func makeNSView(context: Context) -> NSView {
    ResolvingView(onAttach: onAttach, onDetach: onDetach)
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ResolvingView: NSView {
  let onAttach: (NSWindow?) -> Void
  let onDetach: (NSWindow?) -> Void

  init(
    onAttach: @escaping (NSWindow?) -> Void,
    onDetach: @escaping (NSWindow?) -> Void
  ) {
    self.onAttach = onAttach
    self.onDetach = onDetach
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    if newWindow == nil, let current = window {
      onDetach(current)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onAttach(window)
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
    settings.activeProcessor?.name ?? "No processor"
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
    settings.templateChoice.selected.name
  }
}

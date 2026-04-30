import AppKit
import GalleyCoreKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Routes Finder double-click and `application(_:open:)` URLs into a
/// SwiftUI `WindowGroup(for: URL.self)`. The chicken-and-egg problem
/// here is that `openWindow(value:)` is a SwiftUI environment value —
/// only available inside a view — but `application(_:open:)` may fire
/// before any window has appeared. We buffer URLs until a window comes
/// up and installs its open handler, then flush.
///
/// Also tracks recently-opened URLs so the File > Open Recent menu can
/// observe them. `WindowGroup` doesn't get the system Open Recent for
/// free (that menu is wired to NSDocument), so we surface
/// `NSDocumentController.shared.recentDocumentURLs` ourselves and
/// refresh it whenever we note a new URL or clear the list.
@MainActor
@Observable
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
  @ObservationIgnored private(set) var openHandler: ((URL) -> Void)?
  @ObservationIgnored private var pending: [URL] = []

  /// Reference to the shared `ViewerSettings`, set by `ViewerApp` so
  /// `application(_:open:)` and friends can consult `openBehavior`
  /// without a SwiftUI environment lookup.
  @ObservationIgnored weak var settings: ViewerSettings?

  /// Window registry — each `ContentView` registers its `NSWindow`
  /// along with a closure that rebinds the window to a new URL. Used
  /// for the `replaceCurrent` open behavior, and to identify the
  /// frontmost window for the `newTab` handoff.
  @ObservationIgnored
  private var registrations: [ObjectIdentifier: WindowRegistration] = [:]

  /// FIFO queue of hosts for the next `newTab` opens. Populated
  /// immediately before calling `openHandler`; each new window's
  /// `WindowAccessor` consumes one entry when it resolves an
  /// `NSWindow`. A queue (rather than a single slot) handles the
  /// multi-URL case from `application(_:open:)` where window
  /// creation is async w.r.t. the dispatch loop.
  @ObservationIgnored private var pendingTabHosts: [NSWindow] = []

  /// Mirrors `NSDocumentController.shared.recentDocumentURLs`. Updated
  /// whenever we record or clear a recent URL. Bind from the File
  /// menu's Open Recent submenu.
  private(set) var recentURLs: [URL] = []

  /// Set true when AppKit signals launch is complete. State
  /// restoration finishes before this fires, so the placeholder
  /// window can wait on this flag instead of a fixed timeout
  /// before deciding to show the FTUE open panel.
  private(set) var didFinishLaunching = false

  override init() {
    super.init()
    self.recentURLs = NSDocumentController.shared.recentDocumentURLs
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    didFinishLaunching = true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      record(url)
      dispatch(url)
    }
  }

  /// Single entry point all "open this URL" requests funnel through.
  /// Honors `ViewerSettings.openBehavior` when at least one window is
  /// already on screen; with no windows, every mode collapses to
  /// "spawn a new window" since there's no frontmost to tab onto.
  func dispatch(_ url: URL) {
    let behavior = settings?.openBehavior ?? .newWindow

    // Pre-launch (or no windows yet): only newWindow makes sense.
    // Queue if the SwiftUI handler isn't installed; otherwise just
    // hand off and let WindowGroup spawn a fresh window.
    guard let openHandler else {
      pending.append(url)
      return
    }

    switch behavior {
    case .newWindow:
      openHandler(url)

    case .newTab:
      // Mark the current frontmost as the tab host. The freshly
      // spawned window will read this in its WindowAccessor and
      // merge itself into that window's tab group.
      if let host = frontmostRegisteredWindow() {
        pendingTabHosts.append(host)
      }
      openHandler(url)

    case .replaceCurrent:
      // Rebind the frontmost window in place; fall back to a new
      // window if there's nothing to reuse.
      if let registration = frontmostRegistration() {
        registration.rebind(url)
      } else {
        openHandler(url)
      }
    }
  }

  // MARK: - Window registry

  /// Called by every `ContentView` once its `NSWindow` resolves. The
  /// `rebind` closure swaps the window's WindowGroup binding and the
  /// underlying `DocumentModel` to a new URL.
  func registerWindow(
    _ window: NSWindow,
    rebind: @escaping @MainActor (URL) -> Void
  ) {
    registrations[ObjectIdentifier(window)] = WindowRegistration(
      window: window, rebind: rebind)
  }

  func unregisterWindow(_ window: NSWindow) {
    registrations.removeValue(forKey: ObjectIdentifier(window))
  }

  /// Consume the oldest pending `newTab` host. The new window calls
  /// this after attaching, then merges itself onto the returned host.
  func consumePendingTabHost() -> NSWindow? {
    pendingTabHosts.isEmpty ? nil : pendingTabHosts.removeFirst()
  }

  /// Pick the registered window that should receive the next "replace"
  /// or "new tab" request. Prefers the system's main window, falls
  /// back to the key window, then to any still-live registration.
  private func frontmostRegistration() -> WindowRegistration? {
    let keys = [NSApp.mainWindow, NSApp.keyWindow]
      .compactMap { $0 }
      .map { ObjectIdentifier($0) }
    for key in keys {
      if let registration = registrations[key],
         registration.window != nil
      {
        return registration
      }
    }
    return registrations.values.first { $0.window != nil }
  }

  private func frontmostRegisteredWindow() -> NSWindow? {
    frontmostRegistration()?.window
  }

  /// Allow an untitled placeholder window so SwiftUI has a host view
  /// up early enough to install the `openWindow` handler — otherwise
  /// URLs queued during launch never flush. The placeholder shows a
  /// "no document" prompt; users get File > Open / Open Recent there.
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    true
  }

  /// Opt in to secure state restoration so macOS persists the open
  /// windows (and SwiftUI persists their `@SceneStorage` payloads)
  /// across launches without warning about insecure coding.
  func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    true
  }

  /// Called by the first SwiftUI view that comes up. Installs the
  /// `openWindow` action and flushes any URLs queued during launch.
  /// Returns `true` when pending URLs were flushed — the caller can
  /// use that signal to drop a placeholder welcome window since real
  /// document windows are about to appear.
  @discardableResult
  func install(_ handler: @escaping (URL) -> Void) -> Bool {
    let hadPending = !pending.isEmpty
    openHandler = handler
    let queue = pending
    pending.removeAll()
    for url in queue { handler(url) }
    return hadPending
  }

  /// Open one or more files via NSOpenPanel and dispatch them through
  /// the same routing path as Finder opens.
  func presentOpenPanel() {
    application(NSApp, open: runOpenPanel())
  }

  /// Run NSOpenPanel synchronously and return the picked URLs without
  /// dispatching anywhere. Used by the launch flow so the caller can
  /// load the file into the placeholder window rather than spawning
  /// a new one.
  func runOpenPanel() -> [URL] {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = Self.openPanelContentTypes
    guard panel.runModal() == .OK else { return [] }
    return panel.urls
  }

  /// Stay alive after the last window closes — the user can launch
  /// the open panel again from File > Open.
  func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    false
  }

  /// Open a single previously-opened URL through the same dispatch
  /// path as Finder/NSOpenPanel — used by the Open Recent menu.
  func openRecent(_ url: URL) {
    application(NSApp, open: [url])
  }

  /// Record a URL as recently opened. Called from
  /// `application(_:open:)`, but also exposed so other entry points
  /// (e.g. ContentView's task on initial bind) can keep the list in
  /// sync.
  func record(_ url: URL) {
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
    recentURLs = NSDocumentController.shared.recentDocumentURLs
  }

  func clearRecents() {
    NSDocumentController.shared.clearRecentDocuments(nil)
    recentURLs = NSDocumentController.shared.recentDocumentURLs
  }

  /// Weak link to a `ContentView`'s `NSWindow` plus the closure that
  /// rebinds that window's WindowGroup binding + `DocumentModel` to a
  /// new URL. Closures live for the lifetime of the registration —
  /// they capture `self` from the enclosing view, so the registry
  /// must drop entries when the window goes away to avoid leaks.
  private struct WindowRegistration {
    weak var window: NSWindow?
    let rebind: @MainActor (URL) -> Void
  }

  private static let openPanelContentTypes: [UTType] = {
    var types: [UTType] = []
    types.append(UTType(importedAs: "net.daringfireball.markdown"))
    for ext in MarkdownFileTypes.extensions {
      if let type = UTType(filenameExtension: ext) { types.append(type) }
    }
    types.append(.plainText)
    return types
  }()
}

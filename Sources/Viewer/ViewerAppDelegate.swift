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

  /// Mirrors `NSDocumentController.shared.recentDocumentURLs`. Updated
  /// whenever we record or clear a recent URL. Bind from the File
  /// menu's Open Recent submenu.
  private(set) var recentURLs: [URL] = []

  override init() {
    super.init()
    self.recentURLs = NSDocumentController.shared.recentDocumentURLs
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      record(url)
      if let openHandler {
        openHandler(url)
      } else {
        pending.append(url)
      }
    }
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

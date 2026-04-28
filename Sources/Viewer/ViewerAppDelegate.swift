import AppKit
import GalleyCoreKit
import SwiftUI
import UniformTypeIdentifiers

/// Routes Finder double-click and `application(_:open:)` URLs into a
/// SwiftUI `WindowGroup(for: URL.self)`. The chicken-and-egg problem
/// here is that `openWindow(value:)` is a SwiftUI environment value —
/// only available inside a view — but `application(_:open:)` may fire
/// before any window has appeared. We buffer URLs until a window comes
/// up and installs its open handler, then flush.
@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
  private(set) var openHandler: ((URL) -> Void)?
  private var pending: [URL] = []

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
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

  /// Called by the first SwiftUI view that comes up. Installs the
  /// `openWindow` action and flushes any URLs queued during launch.
  func install(_ handler: @escaping (URL) -> Void) {
    openHandler = handler
    let queue = pending
    pending.removeAll()
    for url in queue { handler(url) }
  }

  /// Open one or more files via NSOpenPanel and dispatch them through
  /// the same routing path as Finder opens.
  func presentOpenPanel() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = Self.openPanelContentTypes
    guard panel.runModal() == .OK else { return }
    application(NSApp, open: panel.urls)
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

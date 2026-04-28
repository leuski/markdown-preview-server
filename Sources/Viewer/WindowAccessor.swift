import AppKit
import SwiftUI

/// Hands the host `NSWindow` back to a SwiftUI view so it can drive
/// AppKit-only properties (title, proxy icon, etc.) that DocumentGroup
/// otherwise manages itself.
///
/// Most callers want the higher-level `.documentURL(_:)` modifier
/// declared below; reach for `WindowAccessor` directly only if you
/// need raw window access for something else.
struct WindowAccessor: NSViewRepresentable {
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

/// Drives the host NSWindow's title and proxy icon from the supplied
/// URL. Necessary because DocumentGroup pins the window title to the
/// originally-opened FileDocument's URL and ignores
/// `.navigationTitle` / `.navigationDocument` once the window is up;
/// this modifier reaches the underlying NSWindow and updates it
/// directly whenever the URL changes.
private struct DocumentURLModifier: ViewModifier {
  let url: URL?

  @State private var hostWindow: NSWindow?

  func body(content: Content) -> some View {
    content
      .background(WindowAccessor { hostWindow = $0 })
      .onChange(of: url, initial: true) { _, _ in apply() }
      .onChange(of: hostWindow) { _, _ in apply() }
  }

  private func apply() {
    guard let hostWindow else { return }
    if let url {
      hostWindow.title = url.deletingPathExtension().lastPathComponent
      hostWindow.representedURL = url.isFileURL ? url : nil
    } else {
      hostWindow.representedURL = nil
    }
  }
}

extension View {
  /// Bind the host NSWindow's title and proxy icon to a URL,
  /// re-applying whenever the URL changes. Pass `nil` to clear.
  ///
  /// Use in a DocumentGroup-hosted view to make the window title
  /// follow in-window navigation rather than the fixed file the
  /// document was originally opened from.
  func documentURL(_ url: URL?) -> some View {
    modifier(DocumentURLModifier(url: url))
  }
}

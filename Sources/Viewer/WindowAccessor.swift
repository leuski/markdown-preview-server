import AppKit
import SwiftUI

/// Hands the host `NSWindow` back to a SwiftUI view so it can drive
/// AppKit-only properties (title, proxy icon, etc.) that DocumentGroup
/// otherwise manages itself.
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

extension View {
  /// Convenience: receive the host window once it's resolved.
  func hostingWindow(_ onResolve: @escaping (NSWindow?) -> Void) -> some View {
    background(WindowAccessor(onResolve: onResolve))
  }
}

import AppKit
import SwiftUI

@main
struct ViewerApp: App {
  @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) var appDelegate
  @State private var settings = ViewerSettings()

  var body: some Scene {
    WindowGroup(for: URL.self) { $url in
      ContentView(fileURL: url)
        .environment(settings)
        .background(OpenWindowInstaller(delegate: appDelegate))
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Open…") { appDelegate.presentOpenPanel() }
          .keyboardShortcut("o", modifiers: .command)
      }
      NavigationCommands()
      RenderingCommands(settings: settings)
    }
  }
}

/// Hidden helper that captures the SwiftUI `openWindow` action and
/// hands it to the app delegate. The first window to come up wires
/// the handler; any URLs queued by `application(_:open:)` during
/// launch flush at that point.
private struct OpenWindowInstaller: View {
  let delegate: ViewerAppDelegate
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .task {
        guard delegate.openHandler == nil else { return }
        delegate.install { url in openWindow(value: url) }
      }
  }
}

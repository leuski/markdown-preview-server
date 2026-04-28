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
        .environment(appDelegate)
        .background(OpenWindowInstaller(delegate: appDelegate))
    }
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      FileCommands(delegate: appDelegate)
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

/// File menu — Open and Open Recent. SwiftUI's `WindowGroup` does not
/// install a system Open Recent menu (that's NSDocument's job), so we
/// build it ourselves from the delegate's observed list.
struct FileCommands: Commands {
  @Bindable var delegate: ViewerAppDelegate

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Open…") { delegate.presentOpenPanel() }
        .keyboardShortcut("o", modifiers: .command)

      Menu("Open Recent") {
        ForEach(delegate.recentURLs, id: \.self) { url in
          Button(url.lastPathComponent) {
            delegate.openRecent(url)
          }
        }
        if !delegate.recentURLs.isEmpty {
          Divider()
        }
        Button("Clear Menu") { delegate.clearRecents() }
          .disabled(delegate.recentURLs.isEmpty)
      }
    }
  }
}

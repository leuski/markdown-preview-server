import AppKit
import SwiftUI

@main
struct ViewerApp: App {
  @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) var appDelegate
  @State private var settings = ViewerSettings()

  var body: some Scene {
    WindowGroup(for: URL.self) { $url in
      ContentView(fileURL: $url)
        .environment(settings)
        .environment(appDelegate)
    }
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      FileCommands(delegate: appDelegate)
      NavigationCommands()
      RenderingCommands(settings: settings)
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

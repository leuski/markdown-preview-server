import AppKit
import SwiftUI

@main
struct ViewerApp: App {
  @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) var appDelegate
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup(for: URL.self) { $url in
      ContentView(fileURL: $url)
        .environment(model)
        .environment(appDelegate)
    }
    .defaultSize(width: 600, height: 400)
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      FileCommands(delegate: appDelegate)
      NavigationCommands()
      RenderingCommands(appModel: model)
    }

    Settings {
      SettingsView(appModel: model)
    }
  }
}

/// File menu — Open and Open Recent. SwiftUI's `WindowGroup` does not
/// install a system Open Recent menu (that's NSDocument's job), so we
/// build it ourselves from the delegate's observed list.
struct FileCommands: Commands {
  @Bindable var delegate: ViewerAppDelegate
  @FocusedValue(\.viewerModel) private var model
  @FocusedValue(\.viewerRenameContext) private var renameContext

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

    CommandGroup(after: .saveItem) {
      Button("Rename…") {
        guard let model, let context = renameContext, let url = context.url
        else { return }
        runRenamePopup(currentURL: url, model: model, context: context)
      }
      .disabled(renameContext?.url == nil)

      Button("Open in Editor") {
        guard let model else { return }
        Task { await model.openInEditor(line: nil) }
      }
      .keyboardShortcut("e", modifiers: .command)
      .disabled(model?.documentURL == nil)
    }
  }
}

@MainActor
private func runRenamePopup(
  currentURL: URL,
  model: DocumentModel,
  context: RenameContext
) {
  let alert = NSAlert()
  alert.messageText = "Rename Document"
  alert.informativeText = "Enter a new file name for this document."
  alert.alertStyle = .informational
  alert.addButton(withTitle: "Rename")
  alert.addButton(withTitle: "Cancel")

  let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
  field.stringValue = currentURL.lastPathComponent
  field.placeholderString = currentURL.lastPathComponent
  alert.accessoryView = field
  alert.window.initialFirstResponder = field

  guard alert.runModal() == .alertFirstButtonReturn else { return }
  let newName = field.stringValue
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard !newName.isEmpty, newName != currentURL.lastPathComponent
  else { return }

  Task { @MainActor in
    do {
      let newURL = try await model.renameCurrentDocument(toName: newName)
      context.apply(newURL)
    } catch {
      NSSound.beep()
    }
  }
}

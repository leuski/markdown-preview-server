import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ALFoundation
import GalleyCoreKit

struct MenuBarContent: View {
  let model: AppModel
  let server: PreviewServerController
  let templateStore: TemplateStore

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Group {
      statusItem

      Divider()

      templatesMenu
      rendererMenu

      Divider()

      Button("Open File…") { openFile() }
        .keyboardShortcut("o")

      Divider()

      Button("Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
      }
      .keyboardShortcut(",")

      Button("Quit") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
    }
  }

  @ViewBuilder
  private var statusItem: some View {
    switch server.state {
    case .running(let url):
      Text("Listening on \(url.hostAndPort)")
    case .stopped:
      Text("Server stopped")
    case .failed(let message):
      Text("Server error: \(message)")
    }
  }

  @ViewBuilder
  private var templatesMenu: some View {
    Menu("Template") {
      DividedSections(sections: [
        templateStore.templates.filter({$0 is BuiltInTemplate}),
        templateStore.templates.filter({$0 is UserTemplate})
      ], id: \.id) { item in
        Toggle(item.name, isOn: Binding(
          get: { item.id == templateStore.selectedID },
          set: { _ in templateStore.select(item) }
        ))
      }
      Divider()
      Button("Reveal Templates Folder") {
        NSWorkspace.shared
          .activateFileViewerSelecting([templateStore.directoryURL])
      }
    }
  }

  @ViewBuilder
  private var rendererMenu: some View {
    Menu("Processor") {
      RendererMenu(model: model)
    }
  }

  private func openFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = Routes.markdownExtensions
      .compactMap { ext in UTType(filenameExtension: ext) }
    + [ UTType.plainText ]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false

    guard
      panel.runModal() == .OK,
      let url = panel.url,
      let base = server.serverURL
    else { return }

    NSWorkspace.shared.open(base.appendingPreviewPath(url.path))
  }
}

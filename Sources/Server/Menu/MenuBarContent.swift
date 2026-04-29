import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ALFoundation
import GalleyCoreKit
import GalleyServerKit

struct MenuBarContent: View {
  let model: AppModel
  let server: PreviewServerController
  let templateStore: TemplateStore
  @Bindable var templateChoice: TemplateChoice

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
      let values = templateChoice.values
      DividedSections(sections: [
        values.filter { $0.kind == .builtIn },
        values.filter { $0.kind == .userDefined }
      ], id: \.self) { item in
        Toggle(item.name, isOn: templateChoice.selectedBinding(item))
      }
      Divider()
      Button("Reveal Templates Folder") {
        templateStore.revealFolder()
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
    panel.allowedContentTypes = MarkdownFileTypes.extensions
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

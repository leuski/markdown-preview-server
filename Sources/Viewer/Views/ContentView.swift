import GalleyCoreKit
import SwiftUI
import WebKit

struct ContentView: View {
  let fileURL: URL?
  @Environment(ViewerSettings.self) private var settings
  @Environment(ViewerAppDelegate.self) private var appDelegate
  @State private var model = ViewerModel()
  @State private var didRestore = false

  /// Per-window persisted back/forward stack. SwiftUI's `@SceneStorage`
  /// gives each WindowGroup window its own keyspace, so two windows
  /// each get their own history that survives app relaunch.
  @SceneStorage("MarkdownEye.history") private var historyJSON: String = ""

  var body: some View {
    Group {
      if fileURL == nil {
        WelcomeView()
      } else {
        WebView(model.page)
          .overlay(alignment: .bottom) {
            if let error = model.lastError {
              Text(error)
                .padding(8)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                .padding()
            }
          }
      }
    }
    .toolbar { toolbarContent }
    .focusedSceneValue(\.viewerModel, model)
    .navigationTitle(model.documentURL?.lastPathComponent
      ?? fileURL?.lastPathComponent
      ?? "Markdown Preview")
    .task(id: fileURL) {
      model.bindSettings(settings)
      if !didRestore, let snapshot = decodeHistory(historyJSON) {
        didRestore = true
        await model.restore(snapshot: snapshot)
      } else if let fileURL {
        await model.bind(to: fileURL)
      }
      if let current = model.documentURL {
        appDelegate.record(current)
      }
    }
    .onChange(of: model.documentURL) { _, _ in
      saveHistory()
    }
    .onChange(of: settings.selectedRendererID) { _, _ in
      Task { await model.reload() }
    }
    .onChange(of: settings.templateStore.selectedID) { _, _ in
      Task { await model.reload() }
    }
  }

  private func saveHistory() {
    guard let snapshot = model.historySnapshot else {
      historyJSON = ""
      return
    }
    if let data = try? JSONEncoder().encode(snapshot),
       let text = String(data: data, encoding: .utf8)
    {
      historyJSON = text
    }
  }

  private func decodeHistory(_ text: String) -> HistorySnapshot? {
    guard !text.isEmpty,
          let data = text.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(
            HistorySnapshot.self, from: data),
          !snapshot.urls.isEmpty
    else { return nil }
    return snapshot
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        Task { await model.goBack() }
      } label: {
        Label("Back", systemImage: "chevron.backward")
      }
      .disabled(!model.canGoBack)
      .help("Back (⌘[)")

      Button {
        Task { await model.goForward() }
      } label: {
        Label("Forward", systemImage: "chevron.forward")
      }
      .disabled(!model.canGoForward)
      .help("Forward (⌘])")
    }
    ToolbarItem(placement: .primaryAction) {
      RendererToolbarPicker(settings: settings)
    }
    ToolbarItem(placement: .primaryAction) {
      TemplateToolbarPicker(settings: settings)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        Task { await model.reload() }
      } label: {
        Label("Reload", systemImage: "arrow.clockwise")
      }
      .help("Reload (⌘R)")
    }
  }
}

private struct WelcomeView: View {
  @Environment(ViewerSettings.self) private var settings

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 56, weight: .light))
        .foregroundStyle(.secondary)
      Text("No document open")
        .font(.title2)
      Text("Use File > Open… (⌘O) or pick a recent document.")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(48)
  }
}

private struct RendererToolbarPicker: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    Menu {
      ProcessorMenu(settings: settings)
    } label: {
      Label(label, systemImage: "wand.and.stars")
    }
    .help("Markdown processor")
  }

  private var label: String {
    settings.activeEntry?.displayName ?? "No processor"
  }
}

private struct TemplateToolbarPicker: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    Menu {
      TemplateMenu(settings: settings)
    } label: {
      Label(label, systemImage: "doc.richtext")
    }
    .help("Template")
  }

  private var label: String {
    settings.templateStore.selected.name
  }
}

import GalleyCoreKit
import SwiftUI
import WebKit

struct ContentView: View {
  let fileURL: URL?
  @Environment(ViewerSettings.self) private var settings
  @Environment(ViewerAppDelegate.self) private var appDelegate
  @State private var model = ViewerModel()

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
      guard let fileURL else { return }
      appDelegate.record(fileURL)
      await model.bind(to: fileURL)
    }
    .onChange(of: settings.selectedRendererID) { _, _ in
      Task { await model.reload() }
    }
    .onChange(of: settings.templateStore.selectedID) { _, _ in
      Task { await model.reload() }
    }
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

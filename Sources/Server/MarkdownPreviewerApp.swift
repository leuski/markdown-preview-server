//
//  MarkdownPreviewerApp.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/25/26.
//

import SwiftUI
import GalleyCoreKit
import GalleyServerKit

@main
struct MarkdownPreviewerApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContent(
        model: model,
        server: model.server,
        templateStore: model.templateStore,
        templates: model.templates)
    } label: {
      MenuBarLabel(state: model.server.state)
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(model: model)
    }
  }

  init() {
    // Auto-start the server on launch.
  }
}

private struct MenuBarLabel: View {
  let state: PreviewServerController.State

  var body: some View {
    Image("MenuBarIcon")
  }

  private var tint: AnyShapeStyle {
    switch state {
    case .running: AnyShapeStyle(.primary)
    case .stopped: AnyShapeStyle(.secondary)
    case .failed: AnyShapeStyle(.red)
    }
  }
}

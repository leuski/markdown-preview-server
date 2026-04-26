//
//  MarkdownPreviewerApp.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/25/26.
//

import SwiftUI

@main
struct MarkdownPreviewerApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContent(
        model: model,
        server: model.server,
        templateStore: model.templateStore)
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
    switch state {
    case .running:
      Text("MD")
    case .stopped:
      Text("MD")
        .foregroundStyle(.secondary)
    case .failed:
      Text("MD!")
        .foregroundStyle(.red)
    }
  }
}

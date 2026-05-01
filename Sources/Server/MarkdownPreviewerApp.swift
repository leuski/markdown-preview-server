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
  @State private var boot = AppBoot()

  var body: some Scene {
    MenuBarExtra {
      if let model = boot.model {
        MenuBarContent(
          model: model,
          server: model.server,
          templateStore: model.templateStore,
          templates: model.templates)
      } else {
        Text("Starting…")
      }
    } label: {
      MenuBarLabel(state: boot.model?.server.state ?? .stopped)
    }
    .menuBarExtraStyle(.menu)

    Settings {
      if let model = boot.model {
        SettingsView(model: model)
      } else {
        ProgressView("Starting…")
          .padding()
          .frame(minWidth: 320, minHeight: 200)
      }
    }
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

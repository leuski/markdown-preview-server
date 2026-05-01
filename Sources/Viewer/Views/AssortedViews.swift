//
//  AssortedViews.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/28/26.
//

import SwiftUI
import GalleyCoreKit

struct TemplateMenu: View {
  let localTitle: String
  let globalTitle: String
  @Bindable var appModel: AppModel
  let templates: SceneTemplateChoice?

  var title: String {
    appModel.enablePerDocumentOverrides && templates != nil
    ? localTitle : globalTitle
  }

  var body: some View {
    Menu(title, systemImage: "doc.richtext") {
      if appModel.enablePerDocumentOverrides, let templates {
        MenuCore(model: templates)
      } else {
        MenuCore(model: appModel.templates)
      }
      Divider()
      Button("Reveal Templates Folder", systemImage: "folder") {
        appModel.revealTemplatesFolder()
      }
    }
  }
}

struct ProcessorMenu: View {
  let localTitle: String
  let globalTitle: String
  @Bindable var appModel: AppModel
  let processors: SceneProcessorChoice?

  var title: String {
    appModel.enablePerDocumentOverrides && processors != nil
    ? localTitle : globalTitle
  }

  var body: some View {
    Menu(title, systemImage: "wand.and.stars") {
      if appModel.enablePerDocumentOverrides, let processors {
        MenuCore(model: processors)
      } else {
        MenuCore(model: appModel.processors)
      }
      Divider()
      Button(
        "Rescan Installed Processors",
        systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
      {
        Task { await appModel.rediscoverRenderers() }
      }
    }
  }
}

struct SubtitleModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

extension View {
  func subtitle() -> some View {
    self.modifier(SubtitleModifier())
  }
}

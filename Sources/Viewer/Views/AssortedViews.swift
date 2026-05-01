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

  var body: some View {
    Menu {
      if appModel.enablePerDocumentOverrides, let templates {
        MenuCore(model: templates)
      } else {
        MenuCore(model: appModel.templates)
      }
      Divider()
      Button("Reveal Templates Folder") {
        appModel.revealTemplatesFolder()
      }
    } label: {
      Label(
        appModel.enablePerDocumentOverrides && templates != nil
        ? localTitle : globalTitle, systemImage: "doc.richtext")
    }
  }
}

struct ProcessorMenu: View {
  let localTitle: String
  let globalTitle: String
  @Bindable var appModel: AppModel
  let processors: SceneProcessorChoice?

  var body: some View {
    Menu {
      if appModel.enablePerDocumentOverrides, let processors {
        MenuCore(model: processors)
      } else {
        MenuCore(model: appModel.processors)
      }
      Divider()
      Button("Rescan Installed Processors") {
        Task { await appModel.rediscoverRenderers() }
      }
    } label: {
      Label(
        appModel.enablePerDocumentOverrides && processors != nil
        ? localTitle : globalTitle, systemImage: "wand.and.stars")
    }
  }
}

//
//  AssortedViews.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/28/26.
//

import SwiftUI
import GalleyCoreKit

struct TemplateMenu<Model>: View
where Model: ChoiceModel, Model.Element: SectionedChoiceValue
{
  let model: Model
  @Bindable var appModel: AppModel

  init(model: Model, appModel: AppModel) {
    self.model = model
    self.appModel = appModel
  }

  var body: some View {
    MenuCore(model: model)
    Divider()
    Button("Reveal Templates Folder") {
      appModel.revealTemplatesFolder()
    }
  }
}

extension TemplateMenu where Model == TemplateChoice {
  init(appModel: AppModel) {
    self.init(model: appModel.templates, appModel: appModel)
  }
}

struct ProcessorMenu<Model>: View
where Model: ChoiceModel, Model.Element: SectionedChoiceValue
{
  let model: Model
  @Bindable var appModel: AppModel

  init(model: Model, appModel: AppModel) {
    self.model = model
    self.appModel = appModel
  }

  var body: some View {
    MenuCore(model: model)
    Divider()
    Button("Rescan Installed Processors") {
      Task { await appModel.rediscoverRenderers() }
    }
  }
}

extension ProcessorMenu where Model == ProcessorChoice {
  init(appModel: AppModel) {
    self.init(model: appModel.processors, appModel: appModel)
  }
}

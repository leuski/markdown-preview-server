//
//  AssortedViews.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/28/26.
//

import SwiftUI
import GalleyCoreKit

/// Renders an array of arrays as a single ForEach with `Divider()`
/// between non-empty sections. Used to group built-in and
/// user-installed renderers in the menu.
struct DividedSections<Item, ID, Content: View>: View where ID: Hashable {
  let sections: [[Item]]
  let id: KeyPath<Item, ID>
  @ViewBuilder let content: (Item) -> Content

  var body: some View {
    let nonEmpty = sections.filter { !$0.isEmpty }
    ForEach(Array(nonEmpty.enumerated()), id: \.offset) { index, section in
      if index > 0 { Divider() }
      ForEach(section, id: id) { content($0) }
    }
  }
}

struct TemplateMenuCore<Model>: View
where Model: ChoiceModel, Model.Value: TemplateModel
{
  let model: Model

  var body: some View {
    // `Picker` with `.inline` style is the canonical macOS pattern
    // for a single-selection menu. Unlike a row of `Toggle`s with
    // custom bindings, Picker keeps the NSMenu item checkmarks in
    // sync with the current selection automatically.
    let values = model.values
    Picker(selection: pickerBinding) {
      DividedSections(sections: [
        values.filter { $0.kind == .global },
        values.filter { $0.kind == .builtIn },
        values.filter { $0.kind == .userDefined }
      ], id: \.self) { value in
        Text(value.name).tag(value)
      }
    } label: { EmptyView() }
    .pickerStyle(.inline)
  }

  private var pickerBinding: Binding<Model.Value> {
    Binding(
      get: { model.selected },
      set: { model.selected = $0 })
  }
}

struct TemplateMenu<Model>: View
where Model: ChoiceModel, Model.Value: TemplateModel
{
  let model: Model
  @Bindable var appModel: AppModel

  init(model: Model, appModel: AppModel) {
    self.model = model
    self.appModel = appModel
  }

  var body: some View {
    TemplateMenuCore(model: model)
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

struct ProcessorMenuCore<Model>: View
where Model: ChoiceModel, Model.Value: ProcessorModel
{
  let model: Model

  var body: some View {
    // See `TemplateMenuCore` — Picker with .inline keeps NSMenu
    // checkmarks in sync; Toggle-with-custom-bindings did not.
    let values = model.values
    Picker(selection: pickerBinding) {
      DividedSections(sections: [
        values.filter { $0.kind == .global },
        values.filter { $0.kind == .builtIn },
        values.filter { $0.kind == .userDefined }
      ], id: \.self) { value in
        Text(value.name).tag(value)
          .disabled(!value.isAvailable)
      }
    } label: { EmptyView() }
    .pickerStyle(.inline)
  }

  private var pickerBinding: Binding<Model.Value> {
    Binding(
      get: { model.selected },
      set: { model.selected = $0 })
  }
}

struct ProcessorMenu<Model>: View
where Model: ChoiceModel, Model.Value: ProcessorModel
{
  let model: Model
  @Bindable var appModel: AppModel

  init(model: Model, appModel: AppModel) {
    self.model = model
    self.appModel = appModel
  }

  var body: some View {
    ProcessorMenuCore(model: model)
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

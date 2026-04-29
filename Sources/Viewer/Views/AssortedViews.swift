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
    let values = model.values
    DividedSections(sections: [
      values.filter { $0.kind == .global },
      values.filter { $0.kind == .builtIn },
      values.filter { $0.kind == .userDefined }
    ], id: \.self) { value in
      Toggle(value.name, isOn: model.selectedBinding(value))
    }
  }
}

struct TemplateMenu<Model>: View
where Model: ChoiceModel, Model.Value: TemplateModel
{
  init(model: Model, settings: ViewerSettings) {
    self.model = model
    self.settings = settings
  }

  let model: Model
  @Bindable var settings: ViewerSettings

  var body: some View {
    TemplateMenuCore(model: model)
    Divider()
    Button("Reveal Templates Folder") {
      settings.revealTemplatesFolder()
    }
  }
}

extension TemplateMenu where Model == TemplateChoice {
  init(settings: ViewerSettings) {
    self.init(model: settings.templateChoice, settings: settings)
  }
}

struct ProcessorMenuCore: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    DividedSections(sections: [
      settings.processors.filter(\.isBuiltIn),
      settings.processors.filter { !$0.isBuiltIn }
    ], id: \.id) { processor in
      Toggle(
        processor.name,
        isOn: settings.rendererBinding(processor))
      .disabled(!processor.isAvailable)
    }
  }
}

struct ProcessorMenu: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    ProcessorMenuCore(settings: settings)
    Divider()
    Button("Rescan Installed Processors") {
      Task { await settings.rediscoverRenderers() }
    }
  }
}

/// Per-window renderer override picker. Only used when the
/// per-document-overrides flag is on. Selecting "Use Global Setting"
/// clears the override; selecting any concrete entry pins it for this
/// window.
struct WindowOverrideProcessorMenu: View {
  let settings: ViewerSettings
  @Bindable var model: ViewerModel

  var body: some View {
    Toggle("Use Global Setting", isOn: Binding(
      get: { model.overrideRendererID == nil },
      set: { isOn in
        if isOn {
          Task { await model.setOverrideRenderer(nil) }
        }
      }))
    Divider()
    DividedSections(sections: [
      settings.processors.filter(\.isBuiltIn),
      settings.processors.filter { !$0.isBuiltIn }
    ], id: \.id) { entry in
      Toggle(entry.name, isOn: Binding(
        get: { model.overrideRendererID == entry.id },
        set: { isOn in
          if isOn {
            Task { await model.setOverrideRenderer(entry.id) }
          }
        }))
      .disabled(!entry.isAvailable)
    }
  }
}

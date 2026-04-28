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

struct TemplateMenu: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    DividedSections(sections: [
      settings.templateStore.templates.filter({$0 is BuiltInTemplate}),
      settings.templateStore.templates.filter({$0 is UserTemplate})
    ], id: \.id) { template in
      Toggle(template.name, isOn: settings.templateBinding(template))
    }
    Divider()
    Button("Reveal Templates Folder") {
      NSWorkspace.shared
        .activateFileViewerSelecting([settings.templateStore.directoryURL])
    }
  }
}

struct ProcessorMenu: View {
  @Bindable var settings: ViewerSettings

  var body: some View {
    DividedSections(sections: [
      settings.rendererEntries.filter(\.isBuiltIn),
      settings.rendererEntries.filter { !$0.isBuiltIn }
    ], id: \.id) { entry in
      Toggle(
        entry.displayName,
        isOn: settings.rendererBinding(entry))
      .disabled(!entry.isAvailable)
    }
    Divider()
    Button("Rescan Installed Processors") {
      Task { await settings.rediscoverRenderers() }
    }
  }
}

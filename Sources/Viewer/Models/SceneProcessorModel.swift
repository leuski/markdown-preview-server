//
//  SceneProcessorModel.swift
//  MarkdownPreviewer
//

import GalleyCoreKit
import SwiftUI

typealias SceneProcessorChoiceValue = SceneChoiceModelValue<ProcessorChoice>

extension SceneProcessorChoiceValue: @retroactive ProcessorModel {
  public var name: String {
    switch self {
    case .local(let value):
      return value.name
    case .global(let value):
      return "Global (\(value.selected.name))"
    }
  }

  public var value: Processor {
    switch self {
    case .local(let value):
      return value.value
    case .global(let value):
      return value.selected.value
    }
  }

  public var isAvailable: Bool {
    switch self {
    case .local(let value):
      return value.isAvailable
    case .global:
      // The global resolution always returns a usable entry — the
      // ProcessorChoice.selected getter falls back to the built-in
      // when the persisted pick is missing or unavailable.
      return true
    }
  }

  public var kind: ProcessorModelKind {
    switch self {
    case .local(let value):
      return value.kind
    case .global:
      return .global
    }
  }
}

/// Per-window processor choice. Reference type for the same reason as
/// `SceneTemplateChoice` — Observation tracks `selected` so menus
/// rebuild when the per-window override id flips. The id itself is
/// persisted through a `Binding<String?>` the owning view derives
/// from `@SceneStorage`.
@Observable @MainActor
final class SceneProcessorChoice: ChoiceModel {
  typealias Value = SceneProcessorChoiceValue

  @ObservationIgnored public let source: ProcessorChoice
  /// See `SceneTemplateChoice.owner`.
  @ObservationIgnored private weak var owner: DocumentModel?

  init(source: ProcessorChoice, owner: DocumentModel) {
    self.source = source
    self.owner = owner
  }

  public var values: [Value] {
    [.global(source)] + source.values.map { .local($0) }
  }

  public var selected: Value {
    get {
      if let id = owner?.overrideRendererID,
         let value = source.values.first(where: { $0.value.id == id })
      {
        return .local(value)
      }
      return .global(source)
    }
    set {
      switch newValue {
      case .local(let value):
        owner?.overrideRendererID = value.value.id
      case .global:
        owner?.overrideRendererID = nil
      }
    }
  }

  /// The current global selection, ignoring any window-local override.
  /// Used when per-document overrides are turned off so the window
  /// renders with the global processor even if a stale local pick is
  /// still stored.
  public var globalProcessor: ProcessorChoice.Value {
    source.selected
  }
}

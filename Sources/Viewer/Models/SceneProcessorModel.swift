//
//  SceneProcessorModel.swift
//  MarkdownPreviewer
//

import GalleyCoreKit
import SwiftUI

/// Per-window processor choice. Reference type for the same reason as
/// `SceneTemplateChoice` — Observation tracks `selected` so menus
/// rebuild when the per-window override id flips. The id itself is
/// persisted through a `Binding<String?>` the owning view derives
/// from `@SceneStorage`.
@Observable @MainActor
public final class SceneProcessorChoice: ChoiceModel {
  public enum Value: ProcessorModel {
    case local(ProcessorChoice.Value)
    case global(ProcessorChoice)

    nonisolated public static func == (lhs: Value, rhs: Value) -> Bool {
      switch (lhs, rhs) {
      case (.local(let lhs), .local(let rhs)):
        return lhs == rhs
      case (.global(let lhs), .global(let rhs)):
        return lhs == rhs
      default:
        return false
      }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
      switch self {
      case .local(let value):
        0.hash(into: &hasher)
        value.hash(into: &hasher)
      case .global(let value):
        1.hash(into: &hasher)
        value.hash(into: &hasher)
      }
    }

    public var name: String {
      switch self {
      case .local(let value):
        return value.name
      case .global(let value):
        return "Global (\(value.active.name))"
      }
    }

    public var processor: Processor {
      switch self {
      case .local(let value):
        return value.processor
      case .global(let value):
        return value.active.processor
      }
    }

    public var isAvailable: Bool {
      switch self {
      case .local(let value):
        return value.isAvailable
      case .global:
        // The global resolution always falls back to something
        // available — even when the user's pick is unavailable, the
        // catalog's first-available entry stands in.
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
         let value = source.values.first(where: { $0.processor.id == id })
      {
        return .local(value)
      }
      return .global(source)
    }
    set {
      switch newValue {
      case .local(let value):
        owner?.overrideRendererID = value.processor.id
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
    source.active
  }
}

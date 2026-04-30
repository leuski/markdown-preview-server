//
//  SceneTemplateModel.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/29/26.
//

import GalleyCoreKit
import SwiftUI

/// Per-window template choice. A reference type so SwiftUI's
/// Observation tracks `selected` automatically — value-type
/// conformers couldn't propagate scene-storage writes to the menu
/// because manually-built `Binding(get:set:)` toggles don't carry
/// dependency tracking on their own. Backed by a `Binding<String?>`
/// that the owning view derives from `@SceneStorage`, so the
/// per-window override id persists with the rest of the scene state.
@Observable @MainActor
public final class SceneTemplateChoice: ChoiceModel {
  public enum Value: TemplateModel {
    case local(TemplateChoice.Value)
    case global(TemplateChoice)

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
        return "Global (\(value.selected.name))"
      }
    }

    public var template: any Template {
      switch self {
      case .local(let value):
        return value.template
      case .global(let value):
        return value.selected.template
      }
    }

    public var kind: TemplateModelKind {
      switch self {
      case .local(let value):
        return value.kind
      case .global:
        return .global
      }
    }
  }

  @ObservationIgnored public let source: TemplateChoice
  /// Reads/writes `owner.overrideTemplateID`, which is itself an
  /// Observable property — so view bodies that read `selected`
  /// participate in Observation through the owner, the same way
  /// `TemplateChoice.selected` works through UserDefaults +
  /// `withMutation`.
  @ObservationIgnored private weak var owner: DocumentModel?

  init(source: TemplateChoice, owner: DocumentModel) {
    self.source = source
    self.owner = owner
  }

  public var values: [Value] {
    [.global(source)] + source.values.map { .local($0) }
  }

  public var selected: Value {
    get {
      if let id = owner?.overrideTemplateID,
         let value = source.values.first(where: { $0.template.id == id })
      {
        return .local(value)
      }
      return .global(source)
    }
    set {
      switch newValue {
      case .local(let value):
        owner?.overrideTemplateID = value.template.id
      case .global:
        owner?.overrideTemplateID = nil
      }
    }
  }

  /// The current global selection, ignoring any window-local override.
  /// Used when per-document overrides are turned off so the window
  /// renders with the global template even if a stale local pick is
  /// still stored.
  public var globalTemplate: any Template {
    source.selected.template
  }
}

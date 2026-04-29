//
//  SceneTemplateModel.swift
//  MarkdownPreviewer
//
//  Created by Anton Leuski on 4/29/26.
//

import GalleyCoreKit
import SwiftUI

public struct SceneTemplateChoice: ChoiceModel {

  private let source: TemplateChoice
  private let storage: Binding<String?>

  public init(source: TemplateChoice, storage: Binding<String?>) {
    self.source = source
    self.storage = storage
  }

  public enum Value: TemplateModel {
    case local(TemplateChoice.Value)
    case global(TemplateChoice)

    nonisolated public static func == (lhs: Value, rhs: Value) -> Bool {
      switch (lhs, rhs) {
      case (.local(let l), .local(let r)):
        return l == r
      case (.global(let l), .global(let r)):
        return l == r
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

  public var values: [Value] {
    [.global(source)] + source.values.map { value in .local(value) }
  }

  public var selected: Value {
    get {
      let id = storage.wrappedValue
      return source.values
        .first(where: { $0.template.id == id })
        .map { .local($0) }
      ?? .global(source)
    }
    set {
      switch newValue {
      case .local(let value):
        storage.wrappedValue = value.template.id
      case .global:
        storage.wrappedValue = nil
      }
    }
  }
}

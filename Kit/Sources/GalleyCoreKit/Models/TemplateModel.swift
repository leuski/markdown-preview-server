//
//  TemplateModel.swift
//  GalleyKit
//
//  Created by Anton Leuski on 4/29/26.
//

import SwiftUI

public enum TemplateModelKind {
  case builtIn, userDefined, global
}

public protocol TemplateModel: ChoiceValue {
  var template: any Template { get }
  var name: String { get }
  var kind: TemplateModelKind { get }
}

@Observable @MainActor
public final class TemplateChoice: ChoiceModel, Hashable {
  public struct Value: TemplateModel {
    public let template: any Template
    public var kind: TemplateModelKind {
      if template is BuiltInTemplate {
        .builtIn
      } else {
        .userDefined
      }
    }
    public var name: String {
      template.name
    }

    nonisolated public static func == (lhs: Value, rhs: Value) -> Bool {
      lhs.template.id == rhs.template.id
    }

    nonisolated public func hash(into hasher: inout Hasher) {
      hasher.combine(template.id)
    }
  }

  nonisolated public static func == (
    lhs: TemplateChoice, rhs: TemplateChoice) -> Bool
  {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  @ObservationIgnored private let store: TemplateStore
  @ObservationIgnored private let key: String

  public var values: [Value] {
    store.templates.map(Value.init)
  }

  public var selected: Value {
    get {
      access(keyPath: \.selected)
      return Value(template: UserDefaults.standard.string(forKey: key)
        .flatMap { id in
          store.templates.first(where: { $0.id == id })
        } ?? .default)
    }
    set {
      let oldValue = UserDefaults.standard.string(forKey: key)
      let newValue = newValue.template.id
      guard oldValue != newValue else { return }
      withMutation(keyPath: \.selected) {
        UserDefaults.standard.set(newValue, forKey: key)
      }
    }
  }

  init(store: TemplateStore, key: String) {
    self.store = store
    self.key = key
  }
}

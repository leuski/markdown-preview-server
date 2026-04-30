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
  var value: Template { get }
  var name: String { get }
  var kind: TemplateModelKind { get }
}

public typealias TemplateChoiceValue = AnyChoiceValue<Template>

extension TemplateChoiceValue: TemplateModel {
  public var name: String { value.name }
  public var kind: TemplateModelKind {
    switch value {
    case .builtIn: .builtIn
    case .userDefined: .userDefined
    }
  }
}

@Observable @MainActor
public final class TemplateChoice: ChoiceModel, Hashable {
  public typealias Value = TemplateChoiceValue

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
      return Value(store.template(
        forID: UserDefaults.standard.string(forKey: key)))
    }
    set {
      let oldValue = UserDefaults.standard.string(forKey: key)
      let newValue = newValue.value.id
      guard oldValue != newValue else { return }
      withMutation(keyPath: \.selected) {
        UserDefaults.standard.set(newValue, forKey: key)
      }
    }
  }

  public init(store: TemplateStore, key: String) {
    self.store = store
    self.key = key
  }
}

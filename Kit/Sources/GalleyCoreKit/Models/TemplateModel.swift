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

  /// The current pick, always usable. Resolves to the persisted entry
  /// when it exists in the catalog; otherwise to the default template.
  /// Persisted state is only rewritten by `reconcile()` — callers
  /// reading `selected` never see a missing template.
  public var selected: Value {
    get {
      access(keyPath: \.selected)
      let persisted = readPersisted()
      if let entry = store.existingTemplate(forID: persisted?.id) {
        return Value(entry)
      }
      return Value(.default)
    }
    set {
      let new = PersistedChoice(
        id: newValue.value.id, name: newValue.name)
      guard new != readPersisted() else { return }
      withMutation(keyPath: \.selected) {
        writePersisted(new)
      }
    }
  }

  /// If the persisted pick is missing from the catalog, write the
  /// default through and return the lost name so the caller can
  /// surface a notification. Returns nil when no heal was needed.
  /// Run after `TemplateStore.reload()` settles the catalog.
  @discardableResult
  public func reconcile() -> String? {
    guard let persisted = readPersisted() else { return nil }
    if store.existingTemplate(forID: persisted.id) != nil { return nil }
    selected = Value(.default)
    return persisted.name
  }

  public init(store: TemplateStore, key: String) {
    self.store = store
    self.key = key
  }

  private func readPersisted() -> PersistedChoice? {
    guard let data = UserDefaults.standard.data(forKey: key) else {
      return nil
    }
    return try? JSONDecoder().decode(PersistedChoice.self, from: data)
  }

  private func writePersisted(_ value: PersistedChoice) {
    let data = try? JSONEncoder().encode(value)
    UserDefaults.standard.set(data, forKey: key)
  }
}

private struct PersistedChoice: Codable, Equatable {
  let id: String
  let name: String
}

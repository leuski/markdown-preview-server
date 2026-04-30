//
//  ProcessorModel.swift
//  GalleyKit
//

import SwiftUI

public enum ProcessorModelKind {
  case builtIn, userDefined, global
}

public protocol ProcessorModel: ChoiceValue {
  var value: Processor { get }
  var name: String { get }
  var kind: ProcessorModelKind { get }
  var isAvailable: Bool { get }
}

public typealias ProcessorChoiceValue = AnyChoiceValue<Processor>

extension ProcessorChoiceValue: ProcessorModel {
  public var name: String { value.name }
  public var isAvailable: Bool { value.isAvailable }
  public var kind: ProcessorModelKind {
    value.isBuiltIn ? .builtIn : .userDefined
  }
}

@Observable @MainActor
public final class ProcessorChoice: ChoiceModel, Hashable {
  public typealias Value = ProcessorChoiceValue

  nonisolated public static func == (
    lhs: ProcessorChoice, rhs: ProcessorChoice) -> Bool
  {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  @ObservationIgnored private let store: ProcessorStore
  @ObservationIgnored private let key: String

  public var values: [Value] {
    store.processors.map(Value.init)
  }

  /// The current pick, always usable. Resolves to the persisted entry
  /// when it exists in the catalog and is available; otherwise to the
  /// built-in. Persisted state is only rewritten by `reconcile()` —
  /// callers reading `selected` never see an unavailable processor.
  public var selected: Value {
    get {
      access(keyPath: \.selected)
      let persisted = readPersisted()
      if let entry = store.processors.first(
        where: { $0.id == persisted?.id }),
         entry.isAvailable
      {
        return Value(entry)
      }
      return Value(.builtIn)
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

  /// If the persisted pick is missing or unavailable, write the
  /// built-in through and return the lost name so the caller can
  /// surface a notification. Returns nil when no heal was needed.
  /// Run after `ProcessorStore.discover()` settles the catalog.
  @discardableResult
  public func reconcile() -> String? {
    guard let persisted = readPersisted() else { return nil }
    if let entry = store.processors.first(where: { $0.id == persisted.id }),
       entry.isAvailable
    {
      return nil
    }
    selected = Value(.builtIn)
    return persisted.name
  }

  public init(store: ProcessorStore, key: String) {
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

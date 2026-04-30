//
//  ProcessorModel.swift
//  GalleyKit
//

import SwiftUI

public enum ProcessorModelKind {
  case builtIn, userDefined, global
}

public protocol ProcessorModel: ChoiceValue {
  var processor: Processor { get }
  var name: String { get }
  var kind: ProcessorModelKind { get }
  var isAvailable: Bool { get }
}

public typealias ProcessorChoiceValue = AnyChoiceValue<Processor>

extension ProcessorChoiceValue: ProcessorModel {
  public var processor: Processor { value }
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

  /// The user's literal pick, or the first processor in the catalog
  /// when no pick is recorded. May refer to an unavailable entry —
  /// the menu should display it as checked-but-disabled, and renderers
  /// should resolve via `active` to fall back to something usable.
  public var selected: Value {
    get {
      access(keyPath: \.selected)
      return Value(store.processor1(
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

  /// User's pick if currently available, otherwise the first
  /// available entry in the catalog. Use this to drive rendering;
  /// use `selected` for what the menu should mark as checked.
  public var active: Value {
    let pick = selected
    if pick.isAvailable { return pick }
    if let firstAvailable = store.processors.first(where: \.isAvailable) {
      return Value(firstAvailable)
    }
    return Value(.builtIn)
  }

  /// Non-nil when the user's literal pick exists in the catalog but
  /// the underlying tool is not installed — UI surfaces this so the
  /// fallback isn't silent.
  public var preferredButUnavailable: Value? {
    let pick = selected
    return pick.isAvailable ? nil : pick
  }

  public init(store: ProcessorStore, key: String) {
    self.store = store
    self.key = key
  }
}

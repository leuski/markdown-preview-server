//
//  ChoiceModel.swift
//  GalleyKit
//
//  Created by Anton Leuski on 4/29/26.
//

import SwiftUI

@MainActor
public protocol ChoiceValue: Hashable, Sendable {
}

public struct AnyChoiceValue<Value>: ChoiceValue
where Value: Identifiable & Sendable
{
  public let value: Value
  public init(_ value: Value) {
    self.value = value
  }

  nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value.id == rhs.value.id
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(value.id)
  }
}

@MainActor
public protocol ChoiceModel<Value> {
  associatedtype Value: ChoiceValue
  var values: [Value] { get }
  var selected: Value { get nonmutating set }
}

public extension ChoiceModel {
  /// A `Toggle`-friendly binding that reports whether `value` is the
  /// current selection and selects it when toggled on.
  ///
  /// Works for both reference-type conformers (e.g. `TemplateChoice`)
  /// and value-type conformers whose `selected` setter is
  /// `nonmutating` and writes through external storage (e.g.
  /// `SceneTemplateChoice` writing through a `Binding`). A
  /// value-type conformer with a mutating setter cannot satisfy the
  /// closure capture, and won't compile here.
  func isSelectedBinding(_ value: Value) -> Binding<Bool> {
    Binding(
      get: { self.selected == value },
      set: { newValue in if newValue { self.selected = value } }
    )
  }
}

public enum SceneChoiceModelValue<Choice>: ChoiceValue
where Choice: ChoiceModel & Equatable & Hashable
{
  case local(Choice.Value)
  case global(Choice)

  nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
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
}

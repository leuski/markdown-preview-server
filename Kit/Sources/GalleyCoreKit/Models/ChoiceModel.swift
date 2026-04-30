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

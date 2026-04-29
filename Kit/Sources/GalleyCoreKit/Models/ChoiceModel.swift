//
//  ChoiceModel.swift
//  GalleyKit
//
//  Created by Anton Leuski on 4/29/26.
//

@MainActor
public protocol ChoiceValue: Hashable, Sendable {
}

@MainActor
public protocol ChoiceModel<Value> {
  associatedtype Value: ChoiceValue
  var values: [Value] { get }
  var selected: Value { get set }
}


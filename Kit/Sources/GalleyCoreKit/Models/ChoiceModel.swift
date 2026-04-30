//
//  ChoiceModel.swift
//  GalleyKit
//
//  Created by Anton Leuski on 4/29/26.
//

import SwiftUI
import ALFoundation

public protocol ChoiceValueProtocol: CustomStringConvertible, Sendable {
  associatedtype PersistentID: Hashable, Codable
  var persistentID: PersistentID { get }
}

struct PersistentChoiceValue<Value>: Codable
where Value: ChoiceValueProtocol
{
  internal init(id: Value.PersistentID, name: String) {
    self.id = id
    self.name = name
  }

  let id: Value.PersistentID
  let name: String

  init(from string: String) throws {
    let decoder = JSONDecoder()
    self = try decoder.decode(Self.self, from: string.utf8Data)
  }

  var encoded: String {
    get throws {
      let encoder = JSONEncoder()
      return try encoder.encode(self).utf8String
    }
  }
}

extension ChoiceValueProtocol {
  var persisted: String {
    get throws {
      try PersistentChoiceValue<Self>(
        id: persistentID, name: description).encoded
    }
  }
}

public protocol ChoiceValueProtocolDecodingContext<Value>
where Value: ChoiceValueProtocol
{
  associatedtype Value
  func findValue(forID id: Value.PersistentID) -> Value?
}

enum AnyChoiceValueDecodingError: LocalizedError {
  case noContext
  case missingValue(String)
}

@MainActor
public protocol ChoiceValue: Hashable {
  var name: String { get }
}

@MainActor
public protocol SectionedChoiceValue {
  var section: Int { get }
  var isAvailable: Bool { get }
}

public protocol ChoiceValueEnvelopeProtocol<Value>: ChoiceValue
{
  associatedtype Value: ChoiceValueProtocol
  nonisolated var value: Value { get }
  init (_ value: Value)
}

extension ChoiceValueEnvelopeProtocol {
  public var name: String { value.description }
  nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value.persistentID == rhs.value.persistentID
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(value.persistentID)
  }
}

@MainActor
public protocol ChoiceModel<Element> {
  associatedtype Element: ChoiceValue
  var values: [Element] { get }
  var selected: Element { get nonmutating set }
  var persistent: String? { get }
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
  func isSelectedBinding(_ value: Element) -> Binding<Bool> {
    Binding(
      get: { self.selected == value },
      set: { newValue in if newValue { self.selected = value } }
    )
  }
}

public protocol ChoiceModelEnvelope<Element>: ChoiceModel
where Element: ChoiceValueEnvelopeProtocol
{
  func findValue(forID id: Element.Value.PersistentID) -> Element.Value?
}

extension ChoiceModelEnvelope {
  public var persistent: String? {
    do {
      return try selected.value.persisted
    } catch {
      return nil
    }
  }

  func decode(_ persistent: String) throws -> Element {
    let persistent = try PersistentChoiceValue<Element.Value>(from: persistent)
    guard let value = findValue(forID: persistent.id)
    else {
      throw AnyChoiceValueDecodingError.missingValue(persistent.name)
    }
    return Element(value)
  }
}

@Observable @MainActor
final public class ConcreteChoiceModel<Element, Source>: ChoiceModelEnvelope,
                                                         ChoiceModelObject
where Element: ChoiceValueEnvelopeProtocol,
      Source: ChoiceModelSource<Element.Value>
{
  private let source: Source
  public var values: [Element] { source.values.map(Element.init) }
  public var selected: Element

  public func findValue(
    forID id: Element.Value.PersistentID) -> Element.Value?
  {
    source.values.first(where: { $0.persistentID == id })
  }

  public static func create(source: Source, persistent: String?)
  -> (ConcreteChoiceModel<Element, Source>, String?)
  {
    let choice = Self(source: source, selected: Element(source.defaultValue))
    if let persistent {
      do {
        choice.selected = try choice.decode(persistent)
      } catch AnyChoiceValueDecodingError.missingValue(let name) {
        return (choice, name)
      } catch {
        // ignore the rest
      }
    }
    return (choice, nil)
  }

  private init(source: Source, selected: Element) {
    self.source = source
    self.selected = selected
  }
}

@MainActor
public protocol ChoiceModelSource<Value>
{
  associatedtype Value: ChoiceValueProtocol
  var values: [Value] { get }
  var defaultValue: Value { get }
}

public protocol ChoiceModelObject: ChoiceModel, Hashable, AnyObject {
}

public extension ChoiceModelObject {
  nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

public enum SceneChoiceValueEnvelope<Choice>: ChoiceValue
where Choice: ChoiceModel & Equatable & Hashable
{
  case local(Choice.Element)
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

  public var name: String {
    switch self {
    case .local(let value):
      return value.name
    case .global(let value):
      return "Global (\(value.selected.name))"
    }
  }
}

extension SceneChoiceValueEnvelope: SectionedChoiceValue
where Choice.Element: SectionedChoiceValue
{
  public var section: Int {
    switch self {
    case .local(let value):
      return value.section
    case .global(let choice):
      return -1
    }
  }

  public var isAvailable: Bool {
    switch self {
    case .local(let value):
      return value.isAvailable
    case .global:
      return true
    }
  }
}

@Observable @MainActor
final public class SceneChoice<Choice>: ChoiceModel
where Choice: ChoiceModelEnvelope & Equatable & Hashable
{
  public typealias Element = SceneChoiceValueEnvelope<Choice>
  private let source: Choice

  public var values: [Element] {
    [.global(source)] + source.values.map { .local($0) }
  }

  public var selected: Element

  private init(source: Choice, selected: Element) {
    self.source = source
    self.selected = selected
  }

  public static func create(
    from source: Choice, persistent: String?)
  -> (SceneChoice<Choice>, String?)
  {
    let choice = Self(source: source, selected: .global(source))
    if let persistent {
      do {
        choice.selected = .local(try source.decode(persistent))
      } catch AnyChoiceValueDecodingError.missingValue(let name) {
        return (choice, name)
      } catch {
        // ignore the rest
      }
    }
    return (choice, nil)
  }

  public var persistent: String? {
    switch selected {
    case .local(let value):
      do {
        return try value.value.persisted
      } catch {
        return nil
      }
    case .global:
      return nil
    }
  }
}

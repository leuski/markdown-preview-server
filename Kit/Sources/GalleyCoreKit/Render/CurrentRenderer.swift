import Foundation
import os

/// Thread-safe holder for the active markdown renderer. Read off-main
/// from request handlers; written from the main actor when the user
/// changes the selection or when discovery completes.
public final class CurrentRenderer: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock<(any MarkdownRenderer)?>(
    initialState: nil)

  public init() {}

  public func get() -> (any MarkdownRenderer)? {
    lock.withLock { $0 }
  }

  public func set(_ renderer: (any MarkdownRenderer)?) {
    lock.withLock { $0 = renderer }
  }
}

import Foundation
import os

/// Thread-safe holder for the active markdown renderer. Read off-main
/// from request handlers; written from the main actor when the user
/// changes the selection or when discovery completes.
final class CurrentRenderer: @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock<(any MarkdownRenderer)?>(initialState: nil)

  func get() -> (any MarkdownRenderer)? {
    lock.withLock { $0 }
  }

  func set(_ renderer: (any MarkdownRenderer)?) {
    lock.withLock { $0 = renderer }
  }
}

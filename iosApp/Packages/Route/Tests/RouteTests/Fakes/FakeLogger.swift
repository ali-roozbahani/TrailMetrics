//
//  FakeLogger.swift
//  RouteTests
//

import Foundation
import SharedKit

/// Keeps every logged message; the Kotlin writer logs from its own thread.
final class FakeLogger: NSObject, Logger {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] { lock.withLock { recordedMessages } }

    func debug(tag: String, message: String) {
        lock.withLock { recordedMessages.append(message) }
    }
}

//
//  FakeLogger.swift
//  TrackingTests
//

import Foundation
import SharedKit

final class FakeLogger: NSObject, Logger {
    func debug(tag: String, message: String) {}
}

//
//  FakeClock.swift
//  TrackingTests
//

import Foundation
import SharedKit

/// Returns `nowMillis`, then advances it by `stepMillis`. A non-zero step gives the real
/// TrackingSessionManager increasing timestamps (so elapsed time and average speed become
/// non-zero) without the test knowing how many times it reads the clock.
final class FakeClock: NSObject, Clock {

    private let lock = NSLock()
    private var currentMillis: Int64
    private let stepMillis: Int64

    init(nowMillis: Int64, stepMillis: Int64 = 0) {
        self.currentMillis = nowMillis
        self.stepMillis = stepMillis
    }

    func setNowMillis(_ millis: Int64) {
        lock.withLock { currentMillis = millis }
    }

    func nowMillis() -> Int64 {
        lock.withLock {
            defer { currentMillis += stepMillis }
            return currentMillis
        }
    }
}

//
//  FakeClock.swift
//  TrackingTests
//

import Foundation
import SharedKit

/// Two independent clocks. `nowMillis()` (wall clock) returns a fixed value until
/// `setNowMillis(_:)` changes it. `elapsedRealtimeMillis()` (monotonic) returns its current value,
/// then advances it by `stepMillis`. A non-zero step gives the real TrackingSessionManager
/// increasing readings (so elapsed time and average speed become non-zero) without the test
/// knowing how many times it reads the clock.
final class FakeClock: NSObject, Clock {

    private let lock = NSLock()
    private var wallClockMillis: Int64
    private var currentElapsedRealtimeMillis: Int64
    private let stepMillis: Int64

    init(nowMillis: Int64, elapsedRealtimeMillis: Int64 = 0, stepMillis: Int64 = 0) {
        self.wallClockMillis = nowMillis
        self.currentElapsedRealtimeMillis = elapsedRealtimeMillis
        self.stepMillis = stepMillis
    }

    func setNowMillis(_ millis: Int64) {
        lock.withLock { wallClockMillis = millis }
    }

    func nowMillis() -> Int64 {
        lock.withLock { wallClockMillis }
    }

    func elapsedRealtimeMillis() -> Int64 {
        lock.withLock {
            defer { currentElapsedRealtimeMillis += stepMillis }
            return currentElapsedRealtimeMillis
        }
    }
}

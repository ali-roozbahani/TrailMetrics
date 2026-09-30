//
//  FakeTrackingServiceLauncher.swift
//  TrackingTests
//

import Foundation
import SharedKit

final class FakeTrackingServiceLauncher: NSObject, TrackingServiceLauncher {

    private let lock = NSLock()
    private var recordedStartCount = 0
    private var recordedStopCount = 0

    var startCount: Int {
        lock.withLock { recordedStartCount }
    }

    var stopCount: Int {
        lock.withLock { recordedStopCount }
    }

    func start() {
        lock.withLock { recordedStartCount += 1 }
    }

    func stop() {
        lock.withLock { recordedStopCount += 1 }
    }
}

//
//  WaitUntil.swift
//  HistoryTests
//

import XCTest

/// Suspends until `condition` is true, polling on the main actor, or fails the test after
/// `timeout`. For ViewModel work started in a fire-and-forget `Task { }` that a test can't
/// `await` directly. Wait on an observable outcome (published state, a fake's recorded
/// calls), never on a fixed delay.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            XCTFail("Condition not met within \(timeout)", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

//
//  WaitUntil.swift
//  TestSupport
//

import XCTest

/// The timeout of the first `waitUntil` in a test process, used instead of a shorter `timeout`.
/// The first test after a freshly booted CI simulator has stalled once for 52.9 s (it usually
/// takes under 1.1 s, later tests under 0.1 s), so the first wait gets a little over twice
/// that. Every later wait keeps its own `timeout`, so a hung wait still fails fast there.
private let coldStartTimeout: Duration = .seconds(120)

/// Whether a `waitUntil` has started in this test process. Each package's `xcodebuild test`
/// is its own process, so each package's first wait gets `coldStartTimeout`.
@MainActor private var hasWaitStarted = false

/// Suspends until `condition` is true, polling on the main actor, or fails the test after
/// `timeout` (at least `coldStartTimeout` for the first wait in the process). For ViewModel
/// work started in a fire-and-forget `Task { }` that a test can't `await` directly. Wait on an
/// observable outcome (published state, a fake's recorded calls), never on a fixed delay.
@MainActor
public func waitUntil(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let effectiveTimeout = hasWaitStarted ? timeout : max(timeout, coldStartTimeout)
    hasWaitStarted = true
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: effectiveTimeout)
    while !condition() {
        guard clock.now < deadline else {
            XCTFail("Condition not met within \(effectiveTimeout)", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

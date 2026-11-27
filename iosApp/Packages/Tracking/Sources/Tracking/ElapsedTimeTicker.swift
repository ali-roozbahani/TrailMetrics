//
//  ElapsedTimeTicker.swift
//  Tracking
//

import Foundation
import SharedKit

/// The elapsed time the metrics panel shows, from `domain`'s `displayedElapsedMillis` (the rule Android uses too).
/// The session manager emits only on location events and controls, so while the state is Tracking the time is
/// computed again when the shown time reaches its next full second, and the displayed seconds change on time.
/// One ticking at a time: it ends at the next `show` and with the ticker (its owner's deinit).
@MainActor
final class ElapsedTimeTicker {
    private static let millisPerSecond: Int64 = 1_000

    private var task: Task<Void, Never>?

    /// Publishes the shown time of `state` now and, while `state` is Tracking, at each full second of it.
    /// `publish` should hold its owner weakly: the ticker keeps it while ticking.
    func show(_ state: TrackingState, clock: Clock, publish: @escaping @MainActor (Int64) -> Void) {
        task?.cancel()
        task = nil
        let shown = state.displayedElapsedMillis(nowElapsedRealtimeMillis: clock.elapsedRealtimeMillis())
        publish(shown)
        guard case .tracking = onEnum(of: state) else { return }
        // Made on the main actor, so the Task and `publish` run there.
        task = Task {
            var lastShown = shown
            while true {
                let wait = Self.millisPerSecond - lastShown % Self.millisPerSecond
                do {
                    try await Task.sleep(for: .milliseconds(wait))
                } catch {
                    // Task.sleep throws only CancellationError: the state changed or the owner is gone.
                    return
                }
                // A sleep that ended just before a cancellation must not publish the old state's time.
                guard !Task.isCancelled else { return }
                lastShown = state.displayedElapsedMillis(nowElapsedRealtimeMillis: clock.elapsedRealtimeMillis())
                publish(lastShown)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

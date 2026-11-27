//
//  ElapsedTimeTicker.swift
//  Tracking
//

import Foundation
import SharedKit

/// The elapsed time the metrics panel shows, from `domain`'s `displayedElapsedMillis` (the rule Android uses too).
/// The session manager emits only on location events and controls, so while the state is Tracking the time is
/// computed again when the shown time reaches its next full second, and the displayed seconds change on time.
/// An object of its own, observed by `MetricsDisplay` only: a tick re-renders the metrics panel, not the whole
/// tracking screen and its map. One ticking at a time: it ends at the next `show` and with the ticker.
@MainActor
final class ElapsedTimeTicker: ObservableObject {
    private static let millisPerSecond: Int64 = 1_000

    @Published private(set) var displayedElapsedMillis: Int64 = 0

    private var task: Task<Void, Never>?

    /// Publishes the shown time of `state` now and, while `state` is Tracking, at each full second of it.
    func show(_ state: TrackingState, clock: Clock) {
        task?.cancel()
        task = nil
        let shown = state.displayedElapsedMillis(nowElapsedRealtimeMillis: clock.elapsedRealtimeMillis())
        displayedElapsedMillis = shown
        guard case .tracking = onEnum(of: state) else { return }
        // Made on the main actor, so the Task runs there. It holds the ticker weakly: the ticker's deinit cancels it.
        task = Task { [weak self] in
            var lastShown = shown
            while true {
                let wait = Self.millisPerSecond - lastShown % Self.millisPerSecond
                do {
                    try await Task.sleep(for: .milliseconds(wait))
                } catch {
                    // Task.sleep throws only CancellationError: the state changed or the ticker is gone.
                    return
                }
                // A sleep that ended just before a cancellation must not publish the old state's time.
                guard !Task.isCancelled, let self else { return }
                lastShown = state.displayedElapsedMillis(nowElapsedRealtimeMillis: clock.elapsedRealtimeMillis())
                self.displayedElapsedMillis = lastShown
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

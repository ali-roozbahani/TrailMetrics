//
//  TrackingEventChannel.swift
//  Tracking
//

/// TrackingViewModel's one-shot events. Not a stored `let events` created once: an AsyncStream has one consumer for
/// its whole life, so a screen covered by a push would leave it dead (see RouteViewModel.makeEventsStream()).
///
/// Before TrackingView's first `.task` runs nobody consumes, and the profile load started in init() can fail by
/// then. An event emitted while no consumer is active is kept, at most `maxPending`, oldest dropped first (location
/// issues can repeat while nobody consumes; TrackingView shows one error at a time), and the next stream delivers it
/// first, as in RouteViewModel.
@MainActor
final class TrackingEventChannel {
    static let maxPending = 10

    private var continuation: AsyncStream<TrackingUiEvent>.Continuation?
    /// Events emitted while no consumer was active, oldest first.
    private var pending: [TrackingUiEvent] = []

    /// A new stream. It first delivers the kept events, then `.sessionNotSaved` when `isSessionNotSavedRaised` and the
    /// kept events do not hold it: the warning stays raised until the View has shown it, so a consumer cancelled
    /// before it showed the message, or an event dropped from the kept ones, is offered it again.
    func makeStream(isSessionNotSavedRaised: Bool) -> AsyncStream<TrackingUiEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TrackingUiEvent.self)
        var events = pending
        if isSessionNotSavedRaised, !events.contains(where: \.isSessionNotSaved) {
            events.append(.sessionNotSaved)
        }
        for event in events {
            continuation.yield(event)
        }
        pending.removeAll()
        self.continuation = continuation
        return stream
    }

    func emit(_ event: TrackingUiEvent) {
        if case .enqueued = continuation?.yield(event) { return }
        pending.append(event)
        if pending.count > Self.maxPending {
            pending.removeFirst()
        }
    }
}

private extension TrackingUiEvent {
    var isSessionNotSaved: Bool {
        guard case .sessionNotSaved = self else { return false }
        return true
    }
}

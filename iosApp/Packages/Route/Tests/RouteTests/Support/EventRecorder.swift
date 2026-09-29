//
//  EventRecorder.swift
//  RouteTests
//

import Route

/// Collects a `makeEventsStream()` stream from a `Task`, as the one-shot events bullet in
/// HistoryTests/Fakes/FakeActivityHistoryRepository.swift describes. A class so the
/// consuming `Task` and the test share one list. Call `stop()` when the test is done.
@MainActor
final class EventRecorder {
    private(set) var events: [RouteUiEvent] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<RouteUiEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}

//
//  FakeLiveActivityClient.swift
//  TrackingTests
//
//  An in-memory stand-in for ActivityKit: the Activities the "system" holds, and every call made on it.
//

@testable import Tracking

@MainActor
final class FakeLiveActivityClient: LiveActivityClient {
    struct EndCall: Equatable {
        let id: String
        let finalState: TrackingActivityAttributes.ContentState?
        let dismissal: LiveActivityDismissal
    }

    var areActivitiesEnabled = true
    private(set) var existingIDs: [String]
    private(set) var requestedTypes: [String] = []
    private(set) var endCalls: [EndCall] = []
    private(set) var updatedIDs: [String] = []
    private var nextID = 1

    init(existingIDs: [String] = []) {
        self.existingIDs = existingIDs
    }

    func addExisting(_ id: String) {
        existingIDs.append(id)
    }

    func dropAll() {
        existingIDs = []
    }

    func request(activityType: String) -> String? {
        requestedTypes.append(activityType)
        let id = "new-\(nextID)"
        nextID += 1
        existingIDs.append(id)
        return id
    }

    func update(id: String, state: TrackingActivityAttributes.ContentState) async {
        updatedIDs.append(id)
    }

    func end(id: String, finalState: TrackingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        endCalls.append(EndCall(id: id, finalState: finalState, dismissal: dismissal))
        existingIDs.removeAll { $0 == id }
    }
}

//
//  TrackingViewModelFinishTests.swift
//  TrackingTests
//
//  Repeated Finish: one save and one `onSaved` per finished session, a retry after a
//  failed save, and a new save after a new session.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelFinishTests: TrackingTestCase {

    func test_onFinishClicked_twiceBackToBack_savesOnceAndCallsOnSavedOnce() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        let viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "first") { onSavedCallCount += 1 }
        viewModel.onFinishClicked(snapshotFilePath: "second") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        await finishBarrier(sharing: activityHistoryRepository)
        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(
            activityHistoryRepository.savedActivities.map(\.snapshotFilePath).filter { $0 != "barrier" },
            ["first"]
        )
    }

    func test_onFinishClicked_afterFailedSave_savesAgain() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        activityHistoryRepository.setFailing(true)
        let viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "failed") { onSavedCallCount += 1 }
        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        guard case .showError(let error) = recorder.events.first else {
            return XCTFail("Expected showError, got \(recorder.events)")
        }
        XCTAssertTrue(error is RouteUiErrorGeneral)
        XCTAssertEqual(onSavedCallCount, 0)
        XCTAssertTrue(activityHistoryRepository.savedActivities.isEmpty)

        activityHistoryRepository.setFailing(false)
        viewModel.onFinishClicked(snapshotFilePath: "retried") { onSavedCallCount += 1 }

        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()
        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["retried"])
        XCTAssertEqual(recorder.events.count, 1)
    }

    func test_onFinishClicked_afterStartOfNewSession_savesAgain() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        let subject = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository)
        let viewModel = subject.viewModel
        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "first") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount == 1 }

        // Stop cancelled the ViewModel's state observation (the known limitation in tm-ios,
        // "ViewModel shape"), so wait on the session manager's
        // second location collection instead; Stop reads the manager's state directly.
        viewModel.onStartClicked()
        await waitUntil { subject.locationRepository.observeCallCount == 2 }
        viewModel.onStopClicked()
        viewModel.onFinishClicked(snapshotFilePath: "second") { onSavedCallCount += 1 }

        await waitUntil { onSavedCallCount == 2 }
        await Task.yield()
        XCTAssertEqual(onSavedCallCount, 2)
        XCTAssertEqual(activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["first", "second"])
    }

    // MARK: - Finish without a loaded profile

    func test_onFinishClicked_withoutProfile_readsProfileAgainAndSavesWhenReadable() async {
        let subject = await makeStoppedSubjectWithoutProfile()
        subject.userProfileRepository.setProfile(UserProfile(weightKg: Self.weightKg))

        var onSavedCallCount = 0
        subject.viewModel.onFinishClicked(snapshotFilePath: "retried") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["retried"])
        XCTAssertEqual(subject.userProfileRepository.getUserProfileCallCount, 2)
    }

    func test_onFinishClicked_withProfileStillMissing_emitsGeneralErrorAndCanFinishAgain() async {
        let subject = await makeStoppedSubjectWithoutProfile()
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "missing") { onSavedCallCount += 1 }
        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(recorder.events.count, 1)
        guard case .showError(let error) = recorder.events.first else {
            return XCTFail("Expected showError, got \(recorder.events)")
        }
        XCTAssertTrue(error is RouteUiErrorGeneral)
        XCTAssertEqual(onSavedCallCount, 0)
        XCTAssertTrue(subject.activityHistoryRepository.savedActivities.isEmpty)
        guard case .finished = onEnum(of: viewModel.trackingState) else {
            return XCTFail("The session must stay finished, got \(viewModel.trackingState)")
        }

        subject.userProfileRepository.setProfile(UserProfile(weightKg: Self.weightKg))
        viewModel.onFinishClicked(snapshotFilePath: "again") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["again"])
        XCTAssertEqual(recorder.events.count, 1)
    }

    func test_onFinishClicked_whenProfileReadFails_emitsGeneralErrorAndCanFinishAgain() async {
        let subject = await makeStoppedSubjectWithoutProfile()
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        subject.userProfileRepository.setProfile(UserProfile(weightKg: Self.weightKg))
        subject.userProfileRepository.setFailing(true)

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "failed") { onSavedCallCount += 1 }
        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(recorder.events.count, 1)
        guard case .showError(let error) = recorder.events.first else {
            return XCTFail("Expected showError, got \(recorder.events)")
        }
        XCTAssertTrue(error is RouteUiErrorGeneral)
        XCTAssertEqual(onSavedCallCount, 0)
        XCTAssertTrue(subject.activityHistoryRepository.savedActivities.isEmpty)
        XCTAssertEqual(subject.userProfileRepository.getUserProfileCallCount, 2)

        subject.userProfileRepository.setFailing(false)
        viewModel.onFinishClicked(snapshotFilePath: "again") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["again"])
    }

    func test_onFinishClicked_twiceWhileProfileIsReadAgain_readsAndSavesOnce() async {
        let subject = await makeStoppedSubjectWithoutProfile()
        let viewModel = subject.viewModel
        subject.userProfileRepository.setProfile(UserProfile(weightKg: Self.weightKg))
        subject.userProfileRepository.holdReads()

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "first") { onSavedCallCount += 1 }
        viewModel.onFinishClicked(snapshotFilePath: "second") { onSavedCallCount += 1 }
        await waitUntil { subject.userProfileRepository.getUserProfileCallCount == 2 }
        subject.userProfileRepository.releaseReads()
        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()

        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["first"])
        XCTAssertEqual(subject.userProfileRepository.getUserProfileCallCount, 2)
    }

    func test_onFinishClicked_whileProfileIsLoading_doesNothingAndLaterFinishSaves() async {
        let profileRepositoryHeld = FakeUserProfileRepository(profile: UserProfile(weightKg: Self.weightKg))
        profileRepositoryHeld.holdReads()
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: nil,
            userProfileRepository: profileRepositoryHeld
        )
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        viewModel.onStopClicked()

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "loading") { onSavedCallCount += 1 }
        await Task.yield()
        XCTAssertEqual(profileRepositoryHeld.getUserProfileCallCount, 1)
        profileRepositoryHeld.releaseReads()
        // The load's result reaches the ViewModel on a later turn, and a tap before that does
        // nothing; repeated taps are harmless, as only one save is ever started.
        await waitUntil {
            viewModel.onFinishClicked(snapshotFilePath: "loaded") { onSavedCallCount += 1 }
            return onSavedCallCount > 0
        }

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["loaded"])
    }

    // MARK: - Helpers

    /// A session recorded and stopped while the profile load at init has finished with no profile.
    private func makeStoppedSubjectWithoutProfile() async -> TrackingSubject {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, profile: nil)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count
                && subject.userProfileRepository.getUserProfileCallCount == 1
        }
        // The load's result is applied after the call is counted; let it finish.
        await Task.yield()
        viewModel.onStopClicked()
        return subject
    }

    /// Barrier: a valid finish on a second ViewModel sharing the same repository, saved as
    /// "barrier". A save another ViewModel had already started reaches the repository first.
    private func finishBarrier(sharing activityHistoryRepository: FakeActivityHistoryRepository) async {
        let barrier = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository)
        var barrierOnSavedCallCount = 0
        barrier.viewModel.onFinishClicked(snapshotFilePath: "barrier") { barrierOnSavedCallCount += 1 }
        await waitUntil { barrierOnSavedCallCount > 0 }
        await Task.yield()
    }
}

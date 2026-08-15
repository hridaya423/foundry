import XCTest
import FoundryServices

final class OperationCoordinatorTests: XCTestCase {
    func testLegalUpdatesTerminalImmutabilityAndIdentity() {
        let coordinator = OperationCoordinator()
        let id = coordinator.start()
        for phase in [OperationPhase.awaitingConsent, .provisioning, .downloading, .verifying, .processing, .committing] { XCTAssertTrue(coordinator.update(id: id, phase: phase, progress: .items(completed: 1, total: 2))) }
        XCTAssertTrue(coordinator.update(id: id, phase: .completed, progress: .items(completed: 2, total: 2)))
        XCTAssertFalse(coordinator.update(id: id, phase: .processing, progress: nil))
        XCTAssertFalse(coordinator.update(id: UUID(), phase: .processing, progress: nil))
        XCTAssertEqual(coordinator.snapshot(id: id)?.phase, .completed)
    }

    func testCannotSkipConsentOrMoveBackward() {
        let coordinator = OperationCoordinator()
        let id = coordinator.start()
        XCTAssertFalse(coordinator.update(id: id, phase: .committing, progress: nil))
        XCTAssertTrue(coordinator.update(id: id, phase: .awaitingConsent, progress: nil))
        XCTAssertFalse(coordinator.update(id: id, phase: .assessing, progress: nil))
        XCTAssertTrue(coordinator.update(id: id, phase: .cancelled, progress: nil))
    }

    func testRetryCreatesFreshIdentityAndPreservesDescriptor() {
        let coordinator = OperationCoordinator()
        let descriptor = RetryDescriptor(maxAttempts: 2)
        let original = coordinator.start(retryDescriptor: descriptor)
        XCTAssertTrue(coordinator.update(id: original, phase: .awaitingConsent, progress: nil))
        XCTAssertTrue(coordinator.update(id: original, phase: .cancelled, progress: nil))
        let retry = coordinator.retry(id: original)
        XCTAssertNotEqual(retry?.id, original)
        XCTAssertEqual(retry?.retryDescriptor?.currentAttempt, 2)
        XCTAssertNotEqual(retry?.request, coordinator.snapshot(id: original)?.request)
        XCTAssertEqual(coordinator.snapshot(id: original)?.phase, .cancelled)
        XCTAssertNil(coordinator.retry(id: coordinator.start()))
    }

    func testRetryRefusedWhileActiveAndWhenExhausted() {
        let c = OperationCoordinator(); let active = c.start(retryDescriptor: RetryDescriptor(maxAttempts: 3)); XCTAssertNil(c.retry(id: active))
        let id = c.start(retryDescriptor: RetryDescriptor(maxAttempts: 1)); XCTAssertTrue(c.update(id: id, phase: .failed, progress: nil)); XCTAssertNil(c.retry(id: id))
    }

    func testRetryPreservesOriginalTerminalSnapshot() {
        let c = OperationCoordinator(); let id = c.start(retryDescriptor: RetryDescriptor(maxAttempts: 3)); XCTAssertTrue(c.update(id: id, phase: .failed, progress: nil)); let before = c.snapshot(id: id); _ = c.retry(id: id); XCTAssertEqual(c.snapshot(id: id), before)
    }

    func testStaleProgressCannotMutateTerminalOrUnknownOperation() {
        let coordinator = OperationCoordinator()
        let id = coordinator.start()
        XCTAssertTrue(coordinator.updateProgress(id: id, progress: .items(completed: 1, total: 2)))
        XCTAssertTrue(coordinator.update(id: id, phase: .awaitingConsent, progress: nil))
        XCTAssertTrue(coordinator.update(id: id, phase: .cancelled, progress: nil))
        XCTAssertFalse(coordinator.updateProgress(id: id, progress: .items(completed: 2, total: 2)))
        XCTAssertFalse(coordinator.updateProgress(id: UUID(), progress: .indeterminate))
    }

    func testProvisioningCanCompleteWithoutConversion() {
        let coordinator = OperationCoordinator()
        let id = coordinator.start()
        XCTAssertTrue(coordinator.update(id: id, phase: .provisioning, progress: nil))
        XCTAssertTrue(coordinator.update(id: id, phase: .completed, progress: nil))
    }

    func testAssessingAndProvisioningCanEnterProcessingDirectly() {
        let coordinator = OperationCoordinator()
        let assessing = coordinator.start()
        XCTAssertTrue(coordinator.update(id: assessing, phase: .processing, progress: nil))

        let provisioning = coordinator.start()
        XCTAssertTrue(coordinator.update(id: provisioning, phase: .provisioning, progress: nil))
        XCTAssertTrue(coordinator.update(id: provisioning, phase: .processing, progress: nil))
    }
}

import XCTest
@testable import MenoCore

final class OwnedIntentRuntimeTests: XCTestCase {
    @MainActor private final class Model {}

    @MainActor
    func testColdCallerWaitsUntilTheOwnerPublishesItsStartedModel() async throws {
        let runtime = OwnedIntentRuntime<Model>()
        let model = Model()
        var completed = false
        let caller = Task { @MainActor in
            let result = try await runtime.model()
            completed = true
            return result
        }
        await Task.yield()
        XCTAssertFalse(completed)
        XCTAssertNil(runtime.available)
        runtime.publish(model)
        let result = try await caller.value
        XCTAssertTrue(result === model)
        XCTAssertTrue(runtime.owns(model))
    }

    @MainActor
    func testSecondaryAndTerminatedInstancesCannotPublishOrReturnAModel() async throws {
        for reason in [OwnedIntentRuntime<Model>.Failure.secondaryInstance, .terminated] {
            let runtime = OwnedIntentRuntime<Model>()
            let model = Model()
            runtime.fail(reason)
            runtime.publish(model)
            XCTAssertFalse(runtime.owns(model))
            do { _ = try await runtime.model(); XCTFail("An unavailable instance returned a model") }
            catch let failure as OwnedIntentRuntime<Model>.Failure { XCTAssertEqual(failure, reason) }
        }
    }

    @MainActor
    func testReadinessDeadlineAndPreCancelledReadyCallerFailPromptly() async throws {
        let runtime = OwnedIntentRuntime<Model>()
        do { _ = try await runtime.model(timeout: .zero); XCTFail("An unstarted model was returned") }
        catch let failure as OwnedIntentRuntime<Model>.Failure { XCTAssertEqual(failure, .notReady) }
        runtime.publish(Model())
        let caller = Task { @MainActor in try await runtime.model() }
        caller.cancel()
        do { _ = try await caller.value; XCTFail("Cancellation returned a ready model") }
        catch is CancellationError {}
    }

    @MainActor
    func testTerminationInvalidatesAnAlreadyIssuedModel() async throws {
        let runtime = OwnedIntentRuntime<Model>()
        let model = Model()
        runtime.publish(model)
        runtime.fail(.terminated)
        XCTAssertFalse(runtime.owns(model))
        XCTAssertNil(runtime.available)
    }
}

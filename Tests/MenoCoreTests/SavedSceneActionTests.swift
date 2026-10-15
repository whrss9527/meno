import Foundation
import XCTest
@testable import MenoCore

final class SavedSceneActionTests: XCTestCase {
    func testIdentifiersSurviveRenamesAndNeverFallBackToADuplicateName() {
        var scene = LayoutScene(name: "Work", layout: SceneLayout())
        let other = LayoutScene(name: "Work", layout: SceneLayout())
        let identifier = scene.id.uuidString
        scene.name = "Renamed"
        XCTAssertEqual(SceneSelection.resolve([identifier.lowercased()], in: [other, scene]).map(\.name), ["Renamed"])
        XCTAssertTrue(SceneSelection.resolve([identifier], in: [other]).isEmpty)
        XCTAssertTrue(SceneSelection.resolve(["invalid", UUID().uuidString], in: [scene]).isEmpty)
        XCTAssertTrue(SceneSelection.resolve([identifier], in: []).isEmpty)
    }

    @MainActor private final class Context {
        var scenes = [LayoutScene(name: "Work", layout: SceneLayout())]
        var owner = true
        var gate: CheckedContinuation<Void, Never>?
        var completed = false
        var proceedsAfterSuspension = false
    }

    @MainActor
    private func waitForOperation(_ context: Context) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while context.gate == nil && clock.now < deadline { await Task.yield() }
        XCTAssertNotNil(context.gate)
    }

    @MainActor
    func testCompletionWaitsForTheRealOperationAndAcceptsARename() async throws {
        let context = Context()
        let caller = Task { @MainActor in
            let result = try await SavedSceneAction.apply(id: context.scenes[0].id.uuidString,
                scenes: { context.scenes }, isOwner: { context.owner }, operation: { _, proceeds in
                    await withCheckedContinuation { context.gate = $0 }
                    context.proceedsAfterSuspension = proceeds()
                    return true
                })
            context.completed = true
            return result
        }
        try await waitForOperation(context)
        XCTAssertFalse(context.completed)
        context.scenes[0].name = "Renamed"
        context.gate?.resume()
        let result = try await caller.value
        XCTAssertTrue(result)
        XCTAssertTrue(context.proceedsAfterSuspension)
    }

    @MainActor
    func testDeletionOwnershipLossAndCancellationRejectHeldResults() async throws {
        for change in ["delete", "owner", "cancel", "layout"] {
            let context = Context()
            let caller = Task { @MainActor in
                try await SavedSceneAction.apply(id: context.scenes[0].id.uuidString,
                    scenes: { context.scenes }, isOwner: { context.owner }, operation: { _, proceeds in
                        await withCheckedContinuation { context.gate = $0 }
                        context.proceedsAfterSuspension = proceeds()
                        return true
                    })
            }
            try await waitForOperation(context)
            switch change {
            case "delete": context.scenes = []
            case "owner": context.owner = false
            case "cancel": caller.cancel()
            default: context.scenes[0].layout.visible = [MenuItemKey(owner: "test", token: "item")]
            }
            context.gate?.resume()
            do { _ = try await caller.value; XCTFail("An invalidated action reported success: \(change)") }
            catch is CancellationError { XCTAssertEqual(change, "cancel") }
            catch let failure as SavedSceneAction.Failure {
                XCTAssertEqual(failure, change == "owner" ? .notOwner : .missingScene)
            }
            XCTAssertFalse(context.proceedsAfterSuspension, change)
        }
    }

    @MainActor
    func testFailedOrMissingSceneCannotReportSuccess() async throws {
        let scene = LayoutScene(name: "Work", layout: SceneLayout())
        do {
            _ = try await SavedSceneAction.apply(id: scene.id.uuidString, scenes: { [scene] }, isOwner: { true }, operation: { _, _ in false })
            XCTFail("A rejected layout was reported as applied")
        } catch let failure as SavedSceneAction.Failure { XCTAssertEqual(failure, .notApplied) }
        do {
            _ = try await SavedSceneAction.apply(id: scene.id.uuidString, scenes: { [] }, isOwner: { true }, operation: { _, _ in XCTFail("Missing scene executed"); return true })
            XCTFail("A missing scene was reported as applied")
        } catch let failure as SavedSceneAction.Failure { XCTAssertEqual(failure, .missingScene) }
    }
}

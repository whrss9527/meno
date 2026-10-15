import Foundation

/// Intents may arrive before application launch completes. Only the running
/// owner publishes a model; handoff, termination and cancellation never return
/// an unstarted model or leave a caller waiting indefinitely.
@MainActor
public final class OwnedIntentRuntime<Model: AnyObject> {
    public enum Failure: Error, Equatable {
        case notReady, secondaryInstance, terminated
    }
    private enum State {
        case starting, ready(Model), failed(Failure)
    }
    private var state: State = .starting

    public init() {}

    public var available: Model? {
        if case .ready(let model) = state { return model }
        return nil
    }

    public func publish(_ model: Model) {
        guard case .starting = state else { return }
        state = .ready(model)
    }

    public func fail(_ reason: Failure) { state = .failed(reason) }

    public func owns(_ model: Model) -> Bool { available === model }

    public func model(timeout: Duration = .seconds(5)) async throws -> Model {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            switch state {
            case .ready(let model): return model
            case .failed(let failure): throw failure
            case .starting:
                guard clock.now < deadline else { throw Failure.notReady }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

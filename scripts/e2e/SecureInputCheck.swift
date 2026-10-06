import Carbon
import Foundation

private actor Completion {
    var finished = false
    func finish() { finished = true }
}

/// Exercises the real Carbon gate without touching menu items or settings.
@main
struct SecureInputCheck {
    static func main() async throws {
        precondition(!SecureInput.isEnabled, "Run on a Mac without another secure-input holder")
        try await SecureInput.waitUntilDisabled()
        precondition(EnableSecureEventInput() == noErr)
        defer { DisableSecureEventInput() }
        precondition(SecureInput.isEnabled)
        let completion = Completion()
        let waiting = Task {
            try await SecureInput.waitUntilDisabled()
            await completion.finish()
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let premature = await completion.finished
        precondition(!premature, "A blocked move resumed before secure input ended")
        precondition(DisableSecureEventInput() == noErr)
        try await waiting.value
        precondition(!SecureInput.isEnabled)
        print("Secure input wait resumes after the holder releases it")

        precondition(EnableSecureEventInput() == noErr)
        let cancelled = Task { try await SecureInput.waitUntilDisabled() }
        try await Task.sleep(nanoseconds: 150_000_000)
        cancelled.cancel()
        do {
            try await cancelled.value
            preconditionFailure("A cancelled move resumed")
        } catch is CancellationError {
            print("Secure input wait is cancellable without a failed drag")
        }
        precondition(SecureInput.isEnabled, "Waiting must not turn off secure input")
    }
}

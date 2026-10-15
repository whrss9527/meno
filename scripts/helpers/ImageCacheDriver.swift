import AppKit
import MenoCore

/// Suspends the real cache's capture dependency without reading any windows.
@MainActor
private final class CaptureBackend {
    private var pending: [Int: CheckedContinuation<[MenuItemKey: CGImage], Never>] = [:]
    private(set) var calls = 0
    private(set) var completed: Set<Int> = []

    func capture(_ requests: [WindowCapture.Request]) async -> [MenuItemKey: CGImage] {
        calls += 1
        let call = calls
        let images = await withCheckedContinuation { continuation in
            pending[call] = continuation
        }
        completed.insert(call)
        return images
    }

    func waitForCall(_ call: Int) async {
        await wait { self.pending[call] != nil }
    }

    func finish(_ call: Int, images: [MenuItemKey: CGImage] = [:]) async {
        guard let continuation = pending.removeValue(forKey: call) else { fatalError("Missing capture \(call)") }
        continuation.resume(returning: images)
        await wait { self.completed.contains(call) }
        // The cache commits synchronously after its same-actor dependency
        // returns; let that job finish before inspecting the dictionaries.
        await Task.yield()
    }

    func schedulingCheckpoint() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func wait(until condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { fatalError("Capture checkpoint timed out") }
            await Task.yield()
        }
    }
}

@MainActor
private final class TestClock {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

@main
private enum ImageCacheDriver {
    @MainActor
    static func main() async {
        guard ItemImageCache.captureIsSupported else {
            print("Image-cache capture checks need macOS 14–26; capture is disabled on this OS.")
            return
        }
        await removesCachedItemsWithoutAnotherCapture()
        await invalidatesDisabledCaptureAndCanEnableAgain()
        await removesItemsDuringCaptureWithoutThrottlingSurvivors()
        await rejectsResultsFromAnEarlierLifetime()
        await oldFullCaptureCannotClearANewBatch()
        await cancelledFullCaptureDoesNotDelayRenewal()
        await cleansFailedAttemptsAndKeepsRetryThrottle()
        await reusesCompletedCapturesForThirtySeconds()
        print("Image-cache lifecycle: 8 production-cache checks passed")
    }

    @MainActor
    private static func fixture() -> (ItemImageCache, CaptureBackend, TestClock) {
        let backend = CaptureBackend()
        let clock = TestClock()
        let cache = ItemImageCache(capture: { await backend.capture($0) }, now: { clock.date })
        return (cache, backend, clock)
    }

    private static func item(_ name: String) -> MenuBarItem {
        MenuBarItem(key: MenuItemKey(owner: "image-cache-test", token: name), kind: .app,
                    pid: 0, bundleID: nil, appName: name, displayName: name,
                    detail: nil, identifier: nil, frame: CGRect(x: 100, y: 0, width: 24, height: 24),
                    section: .hidden, isMovable: true, element: nil, keywords: [], markerID: nil)
    }

    private static func image(red: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor
    private static func removesCachedItemsWithoutAnotherCapture() async {
        let (cache, backend, _) = fixture()
        let a = item("a"), b = item("b")
        cache.refresh(for: [a, b], captureAllowed: true)
        await backend.waitForCall(1)
        await backend.finish(1, images: [a.key: image(), b.key: image()])
        require(cache.captured.count == 2, "Initial captures did not arrive")
        let bImage = cache.captured[b.key]
        let revision = cache.revision
        cache.refresh(for: [b], captureAllowed: true)
        require(Set(cache.captured.keys) == [b.key], "Empty wanted list kept a removed image")
        require(Set(cache.attempts.keys) == [b.key], "Empty wanted list kept a removed attempt")
        require(cache.captured[b.key] === bImage, "Removing A discarded B")
        require(cache.revision > revision, "Removing artwork did not notify its views")
        await backend.schedulingCheckpoint()
        require(backend.calls == 1, "Removing artwork started an unnecessary capture")
        cache.refresh(for: [], captureAllowed: true)
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "An empty inventory retained cache state")
    }

    @MainActor
    private static func invalidatesDisabledCaptureAndCanEnableAgain() async {
        let (cache, backend, _) = fixture()
        let a = item("a")
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.waitForCall(1)
        cache.refresh(for: [a], captureAllowed: false)
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "Disabled cache retained state")
        await backend.finish(1, images: [a.key: image()])
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "Disabled cache accepted an old result")
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.waitForCall(2)
        await backend.finish(2, images: [a.key: image(red: 0)])
        require(cache.captured[a.key] != nil, "Re-enabling was throttled by the cancelled capture")
        cache.refresh(for: [a], captureAllowed: false)
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "Disabling completed artwork did not clear it")
    }

    @MainActor
    private static func removesItemsDuringCaptureWithoutThrottlingSurvivors() async {
        let (cache, backend, _) = fixture()
        let a = item("a"), b = item("b")
        cache.refresh(for: [a, b], captureAllowed: true)
        await backend.waitForCall(1)
        cache.refresh(for: [b], captureAllowed: true)
        await backend.waitForCall(2)
        await backend.finish(1, images: [a.key: image(), b.key: image()])
        require(cache.captured.isEmpty, "A superseded batch returned artwork")
        await backend.finish(2, images: [b.key: image(red: 0)])
        require(Set(cache.captured.keys) == [b.key], "Surviving item did not capture immediately")
        require(Set(cache.attempts.keys) == [b.key], "Deleted item kept its attempt")
    }

    @MainActor
    private static func rejectsResultsFromAnEarlierLifetime() async {
        let (cache, backend, _) = fixture()
        let a = item("a")
        cache.refresh(for: [a], captureAllowed: true)
        await backend.waitForCall(1)
        cache.refresh(for: [], captureAllowed: true)
        cache.refresh(for: [a], captureAllowed: true)
        await backend.waitForCall(2)
        await backend.finish(2, images: [a.key: image(red: 0)])
        let newImage = cache.captured[a.key]
        require(newImage != nil, "The new lifetime did not capture")
        await backend.finish(1, images: [a.key: image()])
        require(cache.captured[a.key] === newImage, "The earlier lifetime replaced the current image")
    }

    @MainActor
    private static func oldFullCaptureCannotClearANewBatch() async {
        let (cache, backend, clock) = fixture()
        let a = item("a"), b = item("b")
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.waitForCall(1)
        cache.refresh(for: [b], captureAllowed: true, renew: true)
        await backend.waitForCall(2)
        await backend.finish(1, images: [a.key: image()])
        clock.date.addTimeInterval(30)
        cache.refresh(for: [b], captureAllowed: true)
        await backend.schedulingCheckpoint()
        require(backend.calls == 2, "An old result cleared the newer full batch")
        await backend.finish(2, images: [b.key: image()])
        require(Set(cache.captured.keys) == [b.key], "The new full batch did not complete")
    }

    @MainActor
    private static func cancelledFullCaptureDoesNotDelayRenewal() async {
        let (cache, backend, clock) = fixture()
        let a = item("a"), b = item("b")
        cache.refresh(for: [a, b], captureAllowed: true, renew: true)
        await backend.waitForCall(1)
        await backend.finish(1, images: [a.key: image(), b.key: image()])
        clock.date.addTimeInterval(30)
        cache.refresh(for: [a, b], captureAllowed: true, renew: true)
        await backend.waitForCall(2)
        cache.refresh(for: [b], captureAllowed: true)
        cache.refresh(for: [b], captureAllowed: true, renew: true)
        await backend.waitForCall(3)
        await backend.finish(3, images: [b.key: image(red: 0)])
        let renewedImage = cache.captured[b.key]
        await backend.finish(2, images: [a.key: image(), b.key: image()])
        require(Set(cache.captured.keys) == [b.key] && cache.captured[b.key] === renewedImage,
                "Cancelled full capture delayed or replaced the next renewal")
    }

    @MainActor
    private static func cleansFailedAttemptsAndKeepsRetryThrottle() async {
        let (cache, backend, clock) = fixture()
        let items = (0..<1_000).map { item("item-\($0)") }
        cache.refresh(for: items, captureAllowed: true)
        await backend.waitForCall(1)
        await backend.finish(1)
        require(cache.attempts.count == 1_000, "Failure attempts were not recorded")
        let initial = clock.date
        clock.date = initial.addingTimeInterval(29.9)
        cache.refresh(for: items, captureAllowed: true)
        await backend.schedulingCheckpoint()
        require(backend.calls == 1, "Failed captures retried before 30 seconds")
        clock.date = initial.addingTimeInterval(30)
        cache.refresh(for: items, captureAllowed: true)
        await backend.waitForCall(2)
        cache.refresh(for: [], captureAllowed: true)
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "Removed failed keys retained state")
        await backend.finish(2)
        require(cache.captured.isEmpty && cache.attempts.isEmpty, "Cancelled retry restored failed keys")
    }

    @MainActor
    private static func reusesCompletedCapturesForThirtySeconds() async {
        let (cache, backend, clock) = fixture()
        let a = item("a")
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.waitForCall(1)
        await backend.finish(1, images: [a.key: image()])
        let initial = clock.date
        clock.date = initial.addingTimeInterval(29.9)
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.schedulingCheckpoint()
        require(backend.calls == 1, "Completed captures renewed before 30 seconds")
        clock.date = initial.addingTimeInterval(30)
        cache.refresh(for: [a], captureAllowed: true, renew: true)
        await backend.waitForCall(2)
        await backend.finish(2, images: [a.key: image(red: 0)])
        require(cache.captured[a.key] != nil, "Expired artwork did not renew")
    }
}

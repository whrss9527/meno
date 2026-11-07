import AppKit

@main
enum MenoMain {
    static func main() {
#if MENO_UI_FIXTURE
        MenoUIFixture.run()
#else
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
#endif
    }
}

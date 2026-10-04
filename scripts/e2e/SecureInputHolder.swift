import Carbon
import Foundation

// A separate process owns secure input, like Terminal or a password field.
// SIGUSR1 releases it; exiting also releases the process-owned claim.
guard EnableSecureEventInput() == noErr else { exit(1) }
signal(SIGUSR1, SIG_IGN)
let release = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
release.setEventHandler {
    DisableSecureEventInput()
    exit(0)
}
release.resume()
print("SECURE_INPUT_HOLDER ready")
fflush(stdout)
RunLoop.main.run()

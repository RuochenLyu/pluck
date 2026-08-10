import AppKit

// SwiftPM builds a bare executable with no Info.plist, so the activation policy cannot be
// declared statically; it is set here before the run loop starts. Pluck is a plain Dock
// app — `Scripts/bundle.sh` supplies the Info.plist for the packaged shape.
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

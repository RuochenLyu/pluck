import AppKit

// SwiftPM builds a bare executable with no Info.plist, so LSUIElement cannot be declared
// statically; the accessory policy is set here and again on launch. The Xcode app shell
// (v0.2) will carry the plist and this stays as the belt to its braces.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

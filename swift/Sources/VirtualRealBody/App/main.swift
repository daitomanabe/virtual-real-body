import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.activate(ignoringOtherApps: true)
application.run()

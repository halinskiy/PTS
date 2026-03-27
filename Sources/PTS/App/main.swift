import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let debugEnabled = CommandLine.arguments.contains("--debug")
let controller = AppController(debugEnabled: debugEnabled)
app.delegate = controller
app.run()

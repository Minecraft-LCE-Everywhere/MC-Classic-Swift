import Foundation
import AppKit

// Entry point - use struct with static main() to call NSApplicationMain
@main
struct AppEntry {
    static func main() {
        let appDelegate = AppDelegate()
        NSApplication.shared.delegate = appDelegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

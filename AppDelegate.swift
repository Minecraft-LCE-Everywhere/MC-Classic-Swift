import Foundation
import AppKit
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var metalView: MTKView?
    var renderer: MetalRenderer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[SWIFT] applicationDidFinishLaunching called")
        fflush(stdout)

        // Ensure app appears in dock and can be frontmost
        NSApp.setActivationPolicy(.regular)

        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[SWIFT] ERROR: Metal device creation failed!")
            fflush(stdout)
            return
        }

        print("[SWIFT] Metal device created: \(device.name)")
        fflush(stdout)

        // Create window
        let windowRect = NSRect(x: 100, y: 100, width: 1280, height: 720)
        window = NSWindow(contentRect: windowRect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window?.title = "Minecraft - Swift Metal Test"
        window?.isReleasedWhenClosed = false

        print("[SWIFT] Window created")
        fflush(stdout)

        // Create Metal view with content bounds (not absolute position)
        let contentRect = NSRect(x: 0, y: 0, width: 1280, height: 720)
        metalView = MTKView(frame: contentRect, device: device)
        metalView?.clearColor = MTLClearColor(red: 0.44, green: 0.62, blue: 1.0, alpha: 1.0)  // Minecraft sky blue
        metalView?.isPaused = false

        print("[SWIFT] MTKView created with black clear color")
        fflush(stdout)

        // Create renderer
        if let view = metalView {
            renderer = MetalRenderer(metalView: view, device: device)
            renderer?.window = window
            view.delegate = renderer

            print("[SWIFT] MetalRenderer created and set as delegate")
            fflush(stdout)

            // Add view to window
            window?.contentView = view
            window?.makeFirstResponder(view)

            print("[SWIFT] View added to window")
            fflush(stdout)
        }

        // Create menu bar with quit option (ported from C++ CocoaWindow.mm)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitMenuItem = NSMenuItem(
            title: "Quit Minecraft",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitMenuItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        // Enable mouse moved events for FPS camera
        window?.acceptsMouseMovedEvents = true

        // Show window and keep it focused
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Ensure window stays in foreground
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKey()
        }

        print("[SWIFT] ✅ App setup complete - window focused and ready!")
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

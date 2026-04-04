import Foundation
import AppKit
import MetalKit

class MetalViewContainer: NSView {
    private let metalView: MTKView
    private let renderer: MetalRenderer

    override init(frame: NSRect) {
        print("[SWIFT] MetalViewContainer.init starting")
        fflush(stdout)

        // Create Metal view
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[SWIFT] ERROR: Metal device creation failed!")
            fflush(stdout)
            fatalError("Metal is not supported on this device")
        }

        print("[SWIFT] Metal device created: \(device.name)")
        fflush(stdout)

        metalView = MTKView(frame: frame, device: device)
        metalView.delegate = nil  // Will set delegate after renderer is created
        metalView.clearColor = MTLClearColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        metalView.isPaused = false

        print("[SWIFT] MTKView created")
        fflush(stdout)

        // Create renderer
        renderer = MetalRenderer(metalView: metalView, device: device)

        print("[SWIFT] MetalRenderer created")
        fflush(stdout)

        super.init(frame: frame)

        // Add metal view to this container
        addSubview(metalView)
        metalView.frame = bounds
        metalView.autoresizingMask = [.width, .height]

        // Set delegate after view is added
        metalView.delegate = renderer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        metalView.frame = bounds
    }
}

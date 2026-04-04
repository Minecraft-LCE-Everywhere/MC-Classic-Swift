import Foundation
import MetalKit
import simd

class TriangleRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private var frameCount: Int = 0

    private let triangle: SimpleTriangle?
    private let shaderLibrary: ShaderLibrary?
    private var pipelineState: MTLRenderPipelineState?

    init(metalView: MTKView, device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.triangle = SimpleTriangle(device: device)
        self.shaderLibrary = ShaderLibrary(device: device)

        super.init()

        setupPipeline()

        print("[SWIFT] TriangleRenderer initialized")
        print("[SWIFT] Metal device: \(device.name)")
    }

    private func setupPipeline() {
        guard let library = shaderLibrary?.library else {
            print("[SWIFT] ERROR: Shader library not available")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Triangle Render Pipeline"
        pipelineDescriptor.vertexFunction = shaderLibrary?.getVertexFunction()
        pipelineDescriptor.fragmentFunction = shaderLibrary?.getFragmentFunction()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].offset = 28
        vertexDescriptor.attributes[2].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("[SWIFT] Triangle pipeline created successfully")
        } catch {
            print("[SWIFT] ERROR: Failed to create pipeline: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[SWIFT] Drawable size will change: \(size)")
    }

    func draw(in view: MTKView) {
        frameCount += 1

        if frameCount <= 3 || frameCount % 60 == 0 {
            print("[SWIFT] Frame \(frameCount): Rendering triangle")
            fflush(stdout)
        }

        guard let drawable = view.currentDrawable else {
            print("[SWIFT] ERROR: No drawable")
            return
        }
        guard let descriptor = view.currentRenderPassDescriptor else {
            print("[SWIFT] ERROR: No render pass descriptor")
            return
        }
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            print("[SWIFT] ERROR: No command buffer")
            return
        }
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            print("[SWIFT] ERROR: No render encoder")
            return
        }
        guard let pipelineState = pipelineState else {
            print("[SWIFT] ERROR: No pipeline state")
            return
        }
        guard let triangle = triangle else {
            print("[SWIFT] ERROR: No triangle")
            return
        }

        // Use the MTKView's clear color (black background)
        // descriptor.colorAttachments[0].clearColor is already set by MTKView

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setCullMode(.none)

        // Simple identity matrices - no transformation
        let identity = matrix_identity_float4x4
        var uniforms = Uniforms(modelViewProjectionMatrix: identity, normalMatrix: identity)

        renderEncoder.setVertexBuffer(triangle.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Draw triangle as 3 vertices
        if frameCount <= 3 {
            print("[SWIFT] Drawing triangle with vertexBuffer=\(triangle.vertexBuffer != nil), pipelineState=\(pipelineState != nil)")
            fflush(stdout)
        }
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        if frameCount == 1 {
            print("[SWIFT] First triangle frame!")
        }
    }
}

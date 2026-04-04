import Foundation
import Metal

class SimpleTriangle {
    let vertexBuffer: MTLBuffer?
    let indexCount: Int

    init(device: MTLDevice) {
        // Define a larger colored triangle to fill the screen
        var vertices: [Vertex] = [
            Vertex(position: ( 0.0,  0.9,  0.0), color: (1.0, 0.0, 0.0, 1.0), normal: (0.0, 0.0, 1.0), uv: (0.5, 0.0)),  // Red top
            Vertex(position: (-0.9, -0.9,  0.0), color: (0.0, 1.0, 0.0, 1.0), normal: (0.0, 0.0, 1.0), uv: (0.0, 1.0)),  // Green left
            Vertex(position: ( 0.9, -0.9,  0.0), color: (0.0, 0.0, 1.0, 1.0), normal: (0.0, 0.0, 1.0), uv: (1.0, 1.0)),  // Blue right
        ]

        self.indexCount = 3

        let vertexDataSize = vertices.count * MemoryLayout<Vertex>.stride
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertexDataSize, options: .storageModeShared)
        self.vertexBuffer?.label = "Triangle Vertices"

        print("[SWIFT] SimpleTriangle created: 3 vertices, 1 triangle")
    }
}

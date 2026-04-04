import Foundation
import Metal

// Vertex structure with texture coordinates
struct Vertex {
    var position: (Float, Float, Float)       // 12 bytes, offset 0
    var color: (Float, Float, Float, Float)    // 16 bytes, offset 12
    var normal: (Float, Float, Float)           // 12 bytes, offset 28
    var uv: (Float, Float)                      //  8 bytes, offset 40
}
// Total stride: 48 bytes

class CubeMesh {
    let vertexBuffer: MTLBuffer?
    let indexBuffer: MTLBuffer?
    let indexCount: Int

    init(device: MTLDevice) {
        let s: Float = 0.5

        // Each face gets full 0-1 UV mapping
        let vertices: [Vertex] = [
            // Front face (z = +s) - dirt side
            Vertex(position: (-s, -s,  s), color: (1,1,1,1), normal: ( 0, 0, 1), uv: (0, 1)),  // 0: BL
            Vertex(position: ( s, -s,  s), color: (1,1,1,1), normal: ( 0, 0, 1), uv: (1, 1)),  // 1: BR
            Vertex(position: ( s,  s,  s), color: (1,1,1,1), normal: ( 0, 0, 1), uv: (1, 0)),  // 2: TR
            Vertex(position: (-s,  s,  s), color: (1,1,1,1), normal: ( 0, 0, 1), uv: (0, 0)),  // 3: TL

            // Back face (z = -s)
            Vertex(position: ( s, -s, -s), color: (1,1,1,1), normal: ( 0, 0,-1), uv: (0, 1)),  // 4
            Vertex(position: (-s, -s, -s), color: (1,1,1,1), normal: ( 0, 0,-1), uv: (1, 1)),  // 5
            Vertex(position: (-s,  s, -s), color: (1,1,1,1), normal: ( 0, 0,-1), uv: (1, 0)),  // 6
            Vertex(position: ( s,  s, -s), color: (1,1,1,1), normal: ( 0, 0,-1), uv: (0, 0)),  // 7

            // Top face (y = +s)
            Vertex(position: (-s,  s,  s), color: (1,1,1,1), normal: ( 0, 1, 0), uv: (0, 1)),  // 8
            Vertex(position: ( s,  s,  s), color: (1,1,1,1), normal: ( 0, 1, 0), uv: (1, 1)),  // 9
            Vertex(position: ( s,  s, -s), color: (1,1,1,1), normal: ( 0, 1, 0), uv: (1, 0)),  // 10
            Vertex(position: (-s,  s, -s), color: (1,1,1,1), normal: ( 0, 1, 0), uv: (0, 0)),  // 11

            // Bottom face (y = -s)
            Vertex(position: (-s, -s, -s), color: (1,1,1,1), normal: ( 0,-1, 0), uv: (0, 1)),  // 12
            Vertex(position: ( s, -s, -s), color: (1,1,1,1), normal: ( 0,-1, 0), uv: (1, 1)),  // 13
            Vertex(position: ( s, -s,  s), color: (1,1,1,1), normal: ( 0,-1, 0), uv: (1, 0)),  // 14
            Vertex(position: (-s, -s,  s), color: (1,1,1,1), normal: ( 0,-1, 0), uv: (0, 0)),  // 15

            // Right face (x = +s)
            Vertex(position: ( s, -s,  s), color: (1,1,1,1), normal: ( 1, 0, 0), uv: (0, 1)),  // 16
            Vertex(position: ( s, -s, -s), color: (1,1,1,1), normal: ( 1, 0, 0), uv: (1, 1)),  // 17
            Vertex(position: ( s,  s, -s), color: (1,1,1,1), normal: ( 1, 0, 0), uv: (1, 0)),  // 18
            Vertex(position: ( s,  s,  s), color: (1,1,1,1), normal: ( 1, 0, 0), uv: (0, 0)),  // 19

            // Left face (x = -s)
            Vertex(position: (-s, -s, -s), color: (1,1,1,1), normal: (-1, 0, 0), uv: (0, 1)),  // 20
            Vertex(position: (-s, -s,  s), color: (1,1,1,1), normal: (-1, 0, 0), uv: (1, 1)),  // 21
            Vertex(position: (-s,  s,  s), color: (1,1,1,1), normal: (-1, 0, 0), uv: (1, 0)),  // 22
            Vertex(position: (-s,  s, -s), color: (1,1,1,1), normal: (-1, 0, 0), uv: (0, 0)),  // 23
        ]

        let indices: [UInt16] = [
            0,  1,  2,   0,  2,  3,   // Front
            4,  5,  6,   4,  6,  7,   // Back
            8,  9, 10,   8, 10, 11,   // Top
           12, 13, 14,  12, 14, 15,   // Bottom
           16, 17, 18,  16, 18, 19,   // Right
           20, 21, 22,  20, 22, 23,   // Left
        ]

        self.indexCount = indices.count

        let vertexDataSize = vertices.count * MemoryLayout<Vertex>.stride
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertexDataSize, options: .storageModeShared)
        self.vertexBuffer?.label = "Cube Vertices"

        let indexDataSize = indices.count * MemoryLayout<UInt16>.stride
        self.indexBuffer = device.makeBuffer(bytes: indices, length: indexDataSize, options: .storageModeShared)
        self.indexBuffer?.label = "Cube Indices"

        print("[SWIFT] CubeMesh created: \(vertices.count) vertices, \(indices.count) indices")
    }
}

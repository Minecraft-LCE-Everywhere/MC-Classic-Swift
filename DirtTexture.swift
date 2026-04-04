import Foundation
import Metal

class DirtTexture {
    let texture: MTLTexture?
    let sampler: MTLSamplerState?

    init(device: MTLDevice) {
        // 16x16 Minecraft-style dirt texture
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4) // RGBA

        // Simple seeded random for reproducibility
        var seed: UInt32 = 12345
        func nextRand() -> UInt32 {
            seed = seed &* 1103515245 &+ 12345
            return (seed >> 16) & 0x7FFF
        }

        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4

                // Base dirt brown: RGB ~(134, 96, 67)
                let baseR: Float = 134.0 / 255.0
                let baseG: Float = 96.0 / 255.0
                let baseB: Float = 67.0 / 255.0

                // Add noise variation (-0.12 to +0.12)
                let noise = (Float(nextRand() % 100) / 100.0 - 0.5) * 0.24

                // Occasional darker spots (like Minecraft dirt particles)
                let spot = nextRand() % 10
                let spotDarken: Float = spot < 2 ? -0.08 : (spot < 3 ? 0.06 : 0.0)

                let r = min(1.0, max(0.0, baseR + noise + spotDarken))
                let g = min(1.0, max(0.0, baseG + noise * 0.8 + spotDarken))
                let b = min(1.0, max(0.0, baseB + noise * 0.6 + spotDarken))

                pixels[i + 0] = UInt8(r * 255)
                pixels[i + 1] = UInt8(g * 255)
                pixels[i + 2] = UInt8(b * 255)
                pixels[i + 3] = 255
            }
        }

        // Create Metal texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        let tex = device.makeTexture(descriptor: descriptor)
        tex?.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )
        tex?.label = "Dirt Texture"
        self.texture = tex

        // Nearest-neighbor sampler for pixelated Minecraft look
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.sampler = device.makeSamplerState(descriptor: samplerDesc)

        print("[SWIFT] Dirt texture created: \(size)x\(size)")
    }
}

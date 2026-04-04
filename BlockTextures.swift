import Foundation
import Metal
import AppKit

class BlockTextures {
    let dirtTexture: MTLTexture?
    let stoneTexture: MTLTexture?
    let grassSideTexture: MTLTexture?
    let grassTopTexture: MTLTexture?
    let crosshairTexture: MTLTexture?
    let sampler: MTLSamplerState?

    init(device: MTLDevice) {
        // Load terrain.png atlas
        let atlasPath = BlockTextures.findTerrainAtlas()
        let atlas = BlockTextures.loadAtlas(path: atlasPath)

        if atlas != nil {
            print("[SWIFT] Loaded terrain.png atlas")
        } else {
            print("[SWIFT] WARNING: Could not load terrain.png, using fallback")
        }

        // Extract 16x16 tiles from the atlas (16x16 grid)
        self.stoneTexture = BlockTextures.extractTile(device: device, atlas: atlas, col: 1, row: 0, label: "Stone")
        self.dirtTexture = BlockTextures.extractTile(device: device, atlas: atlas, col: 2, row: 0, label: "Dirt")
        self.grassSideTexture = BlockTextures.extractTile(device: device, atlas: atlas, col: 3, row: 0, label: "Grass Side")
        self.grassTopTexture = BlockTextures.extractTile(device: device, atlas: atlas, col: 0, row: 0, label: "Grass Top")

        // Load crosshair from gui/icons.png (top-left 16x16 sprite)
        let iconsPath = BlockTextures.findAsset("gui/icons.png")
        let iconsAtlas = BlockTextures.loadAtlas(path: iconsPath)
        self.crosshairTexture = BlockTextures.extractSprite(device: device, atlas: iconsAtlas, x: 0, y: 0, w: 16, h: 16, label: "Crosshair")

        // Nearest-neighbor sampler for pixelated Minecraft look
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.sampler = device.makeSamplerState(descriptor: samplerDesc)

        print("[SWIFT] Block textures loaded from terrain.png")
    }

    private static func findAsset(_ relativePath: String) -> String {
        let basePath = "/Users/Apple/Documents/dev/MinecraftConsoles-main/Minecraft.Client/Common/res/"
        let fullPath = basePath + relativePath
        if FileManager.default.fileExists(atPath: fullPath) { return fullPath }
        print("[SWIFT] WARNING: Asset not found: \(relativePath)")
        return fullPath
    }

    /// Extract an arbitrary rectangle from an atlas image using raw pixel data
    static func extractSprite(device: MTLDevice, atlas: NSImage?, x: Int, y: Int, w: Int, h: Int, label: String) -> MTLTexture? {
        guard let atlas = atlas,
              let tiffData = atlas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let bitmapData = bitmap.bitmapData else {
            return generateFallback(device: device, label: label)
        }

        let bw = bitmap.pixelsWide
        let bh = bitmap.pixelsHigh
        let bpp = bitmap.bitsPerPixel / 8  // bytes per pixel
        let rowBytes = bitmap.bytesPerRow

        print("[SWIFT] Crosshair atlas bitmap: \(bw)x\(bh), bpp=\(bpp), hasAlpha=\(bitmap.hasAlpha)")

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for py in 0..<h {
            for px in 0..<w {
                let srcX = x + px
                let srcY = y + py
                guard srcX < bw && srcY < bh else { continue }
                let srcOffset = srcY * rowBytes + srcX * bpp
                let i = (py * w + px) * 4
                pixels[i + 0] = bitmapData[srcOffset + 0]  // R
                pixels[i + 1] = bitmapData[srcOffset + 1]  // G
                pixels[i + 2] = bitmapData[srcOffset + 2]  // B
                pixels[i + 3] = bpp >= 4 ? bitmapData[srcOffset + 3] : 255  // A
            }
        }

        // Debug: count non-transparent pixels
        var nonTransparent = 0
        for py in 0..<h {
            for px in 0..<w {
                let i = (py * w + px) * 4
                if pixels[i + 3] > 0 { nonTransparent += 1 }
            }
        }
        print("[SWIFT] Crosshair sprite: \(nonTransparent)/\(w*h) opaque pixels")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        descriptor.usage = .shaderRead
        let tex = device.makeTexture(descriptor: descriptor)
        tex?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        tex?.label = label
        print("[SWIFT] Extracted \(label) sprite: \(w)x\(h) from bitmap \(bw)x\(bh)")
        return tex
    }

    private static func findTerrainAtlas() -> String {
        // Try to find terrain.png relative to the executable
        let candidates = [
            // Relative to Swift_Render
            "../Minecraft.Client/Common/res/terrain.png",
            // Absolute fallback
            ""
        ]

        // Get the project directory (parent of Swift_Render)
        let execPath = CommandLine.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        let projectDir = (execDir as NSString).deletingLastPathComponent
        let swiftRenderParent = (projectDir as NSString).deletingLastPathComponent

        // Try direct path first
        let directPath = swiftRenderParent + "/Minecraft.Client/Common/res/terrain.png"
        if FileManager.default.fileExists(atPath: directPath) {
            return directPath
        }

        // Try relative to current working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/Minecraft.Client/Common/res/terrain.png"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        // Hardcoded project path as last resort
        let hardPath = "/Users/Apple/Documents/dev/MinecraftConsoles-main/Minecraft.Client/Common/res/terrain.png"
        if FileManager.default.fileExists(atPath: hardPath) {
            return hardPath
        }

        print("[SWIFT] WARNING: terrain.png not found!")
        return hardPath
    }

    private static func loadAtlas(path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            print("[SWIFT] Atlas file not found at: \(path)")
            return nil
        }
        guard let image = NSImage(contentsOfFile: path) else {
            print("[SWIFT] Failed to load image: \(path)")
            return nil
        }
        print("[SWIFT] Atlas loaded: \(Int(image.size.width))x\(Int(image.size.height)) from \(path)")
        return image
    }

    private static func extractTile(device: MTLDevice, atlas: NSImage?, col: Int, row: Int, label: String) -> MTLTexture? {
        guard let atlas = atlas else {
            return generateFallback(device: device, label: label)
        }

        // Get the bitmap representation
        guard let tiffData = atlas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            print("[SWIFT] Failed to get bitmap from atlas")
            return generateFallback(device: device, label: label)
        }

        let atlasWidth = bitmap.pixelsWide
        let atlasHeight = bitmap.pixelsHigh
        let tileSize = atlasWidth / 16  // Usually 16 pixels for a 256px atlas

        // Extract tile pixels
        let startX = col * tileSize
        let startY = row * tileSize

        var pixels = [UInt8](repeating: 0, count: tileSize * tileSize * 4)

        for y in 0..<tileSize {
            for x in 0..<tileSize {
                let srcX = startX + x
                let srcY = startY + y

                guard srcX < atlasWidth && srcY < atlasHeight else { continue }

                let i = (y * tileSize + x) * 4

                if let color = bitmap.colorAt(x: srcX, y: srcY) {
                    // Convert to sRGB to get proper values
                    let r = color.redComponent
                    let g = color.greenComponent
                    let b = color.blueComponent
                    let a = color.alphaComponent

                    pixels[i + 0] = UInt8(min(255, max(0, r * 255)))
                    pixels[i + 1] = UInt8(min(255, max(0, g * 255)))
                    pixels[i + 2] = UInt8(min(255, max(0, b * 255)))
                    pixels[i + 3] = UInt8(min(255, max(0, a * 255)))
                } else {
                    pixels[i + 0] = 255
                    pixels[i + 1] = 0
                    pixels[i + 2] = 255
                    pixels[i + 3] = 255
                }
            }
        }

        print("[SWIFT] Extracted \(label) tile: \(tileSize)x\(tileSize) from atlas pos (\(col),\(row))")
        return makeTexture(device: device, pixels: pixels, size: tileSize, label: label)
    }

    private static func makeTexture(device: MTLDevice, pixels: [UInt8], size: Int, label: String) -> MTLTexture? {
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
        tex?.label = label
        return tex
    }

    private static func generateFallback(device: MTLDevice, label: String) -> MTLTexture? {
        // Magenta checkerboard fallback so missing textures are obvious
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let checker = ((x / 4) + (y / 4)) % 2 == 0
                pixels[i + 0] = checker ? 255 : 0
                pixels[i + 1] = 0
                pixels[i + 2] = checker ? 255 : 0
                pixels[i + 3] = 255
            }
        }
        return makeTexture(device: device, pixels: pixels, size: size, label: "\(label) (fallback)")
    }
}

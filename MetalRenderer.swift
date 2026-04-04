import Foundation
import MetalKit
import AppKit
import simd
import CoreGraphics

// MARK: - Uniforms

struct Uniforms {
    var modelViewProjectionMatrix: simd_float4x4
    var normalMatrix: simd_float4x4
}

// MARK: - Matrix helpers

func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let yScale = 1.0 / tan(fovY * 0.5)
    let xScale = yScale / aspect
    let zScale = far / (near - far)
    let wzScale = near * far / (near - far)
    return simd_float4x4(
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zScale, -1),
        SIMD4<Float>(0, 0, wzScale, 0)
    )
}

func translationMatrix(_ t: SIMD3<Float>) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(t.x, t.y, t.z, 1)
    )
}

func rotationYMatrix(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle); let s = sin(angle)
    return simd_float4x4(
        SIMD4<Float>(c, 0, -s, 0), SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(s, 0, c, 0), SIMD4<Float>(0, 0, 0, 1)
    )
}

func rotationXMatrix(_ angle: Float) -> simd_float4x4 {
    let c = cos(angle); let s = sin(angle)
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, c, s, 0),
        SIMD4<Float>(0, -s, c, 0), SIMD4<Float>(0, 0, 0, 1)
    )
}

func fpViewMatrix(position: SIMD3<Float>, yaw: Float, pitch: Float) -> simd_float4x4 {
    let cosPitch = cos(pitch)
    let forward = SIMD3<Float>(sin(yaw) * cosPitch, sin(pitch), -cos(yaw) * cosPitch)
    let worldUp = SIMD3<Float>(0, 1, 0)
    let right = normalize(cross(forward, worldUp))
    let up = cross(right, forward)
    let rot = simd_float4x4(
        SIMD4<Float>(right.x, up.x, -forward.x, 0),
        SIMD4<Float>(right.y, up.y, -forward.y, 0),
        SIMD4<Float>(right.z, up.z, -forward.z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
    return rot * translationMatrix(-position)
}

// MARK: - Block type

enum BlockType: Int {
    case dirt = 1
    case stone = 2
}

// MARK: - Block position

struct BlockPos: Hashable {
    let x: Int, y: Int, z: Int
    init(_ x: Int, _ y: Int, _ z: Int) { self.x = x; self.y = y; self.z = z }
}

struct RayHit {
    let blockPos: BlockPos
    let faceNormal: BlockPos
}

// MARK: - Renderer

class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private var frameCount: Int = 0

    private let cubeMesh: CubeMesh?
    private let shaderLibrary: ShaderLibrary?
    private let blockTextures: BlockTextures?
    private var pipelineState: MTLRenderPipelineState?
    private var crosshairPipeline: MTLRenderPipelineState?
    private var outlinePipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var outlineDepthState: MTLDepthStencilState?

    // World
    private var worldBlocks: [BlockPos: BlockType] = [:]
    private var worldDirty = true
    private var dirtInstanceBuffer: MTLBuffer?
    private var dirtInstanceCount: Int = 0
    private var stoneInstanceBuffer: MTLBuffer?
    private var stoneInstanceCount: Int = 0

    // Crosshair
    private var crosshairBuffer: MTLBuffer?

    // Block outline
    private var outlineBuffer: MTLBuffer?
    private let outlineVertexCount = 24  // 12 edges * 2 verts each

    // Block selection
    var currentBlock: BlockType = .dirt

    // Player
    private var playerPos: SIMD3<Float> = SIMD3<Float>(0, 2.2, 0)
    private var playerYaw: Float = 0
    private var playerPitch: Float = 0
    private let moveSpeed: Float = 4.317  // Minecraft walk speed (blocks/sec)
    private let mouseSensitivity: Float = 0.002
    private let eyeHeight: Float = 1.62   // Minecraft eye height
    private let playerHeight: Float = 1.8 // Minecraft player height
    private let playerWidth: Float = 0.6  // Minecraft player width
    private let reach: Float = 6.0
    private var velocityY: Float = 0
    private let gravity: Float = 32.0     // blocks/sec^2 (Minecraft ~32)
    private let jumpVelocity: Float = 8.5 // blocks/sec (Minecraft ~8.5)
    private var onGround: Bool = false

    // Input
    private var keysPressed: Set<UInt16> = []
    private var mouseCaptured = false
    private var lastFrameTime: CFAbsoluteTime = 0

    // FPS
    private var lastFPSTime: CFAbsoluteTime = 0
    private var framesThisSecond: Int = 0
    private var currentFPS: Int = 0
    weak var window: NSWindow?

    // Event monitors
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var mouseMovedMonitor: Any?
    private var leftClickMonitor: Any?
    private var rightClickMonitor: Any?
    private var flagsMonitor: Any?

    init(metalView: MTKView, device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.cubeMesh = CubeMesh(device: device)
        self.shaderLibrary = ShaderLibrary(device: device)
        self.blockTextures = BlockTextures(device: device)
        self.lastFPSTime = CFAbsoluteTimeGetCurrent()
        self.lastFrameTime = CFAbsoluteTimeGetCurrent()
        self.playerPos = SIMD3<Float>(0, 0.5 + eyeHeight + 0.001, 0)

        super.init()

        metalView.depthStencilPixelFormat = .depth32Float
        metalView.clearDepth = 1.0

        if !loadWorld() {
            initWorld()
        }
        setupPipeline()
        setupCrosshairPipeline()
        setupOutlinePipeline()
        setupDepthState()
        setupCrosshair()
        setupOutlineBuffer()
        setupInput()

        print("[SWIFT] MetalRenderer initialized - \(worldBlocks.count) blocks")
        print("[SWIFT] CONTROLS: WASD=move, Mouse=look, LClick=break, RClick=place")
        print("[SWIFT] 1=Dirt, 2=Stone, Space=jump, Esc=release mouse, Cmd+S=save")
    }

    deinit {
        releaseMouse()
        for m in [keyDownMonitor, keyUpMonitor, mouseMovedMonitor, leftClickMonitor, rightClickMonitor, flagsMonitor] {
            if let m = m { NSEvent.removeMonitor(m) }
        }
    }

    // MARK: - World

    private func initWorld() {
        let halfGrid = 8
        for z in -halfGrid..<halfGrid {
            for x in -halfGrid..<halfGrid {
                worldBlocks[BlockPos(x, 0, z)] = .dirt
            }
        }
        worldDirty = true
    }

    private func rebuildInstanceBuffers() {
        var dirtOffsets: [SIMD3<Float>] = []
        var stoneOffsets: [SIMD3<Float>] = []

        for (pos, blockType) in worldBlocks {
            let offset = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
            switch blockType {
            case .dirt:  dirtOffsets.append(offset)
            case .stone: stoneOffsets.append(offset)
            }
        }

        dirtInstanceCount = dirtOffsets.count
        dirtInstanceBuffer = dirtInstanceCount > 0 ? device.makeBuffer(
            bytes: dirtOffsets, length: dirtOffsets.count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared
        ) : nil

        stoneInstanceCount = stoneOffsets.count
        stoneInstanceBuffer = stoneInstanceCount > 0 ? device.makeBuffer(
            bytes: stoneOffsets, length: stoneOffsets.count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared
        ) : nil

        worldDirty = false
    }

    // MARK: - Raycasting

    private func raycast() -> RayHit? {
        let cosPitch = cos(playerPitch)
        let dir = SIMD3<Float>(sin(playerYaw) * cosPitch, sin(playerPitch), -cos(playerYaw) * cosPitch)
        let origin = playerPos

        // Starting block
        var mapX = Int(floor(origin.x + 0.5))
        var mapY = Int(floor(origin.y + 0.5))
        var mapZ = Int(floor(origin.z + 0.5))

        let stepX = dir.x >= 0 ? 1 : -1
        let stepY = dir.y >= 0 ? 1 : -1
        let stepZ = dir.z >= 0 ? 1 : -1

        let invX = dir.x != 0 ? 1.0 / dir.x : Float.greatestFiniteMagnitude
        let invY = dir.y != 0 ? 1.0 / dir.y : Float.greatestFiniteMagnitude
        let invZ = dir.z != 0 ? 1.0 / dir.z : Float.greatestFiniteMagnitude

        var tMaxX = (Float(mapX) + (dir.x >= 0 ? 0.5 : -0.5) - origin.x) * invX
        var tMaxY = (Float(mapY) + (dir.y >= 0 ? 0.5 : -0.5) - origin.y) * invY
        var tMaxZ = (Float(mapZ) + (dir.z >= 0 ? 0.5 : -0.5) - origin.z) * invZ

        let tDeltaX = abs(invX)
        let tDeltaY = abs(invY)
        let tDeltaZ = abs(invZ)

        var faceNormal = BlockPos(0, 0, 0)

        for _ in 0..<Int(reach * 3) {
            if tMaxX < tMaxY && tMaxX < tMaxZ {
                mapX += stepX; tMaxX += tDeltaX
                faceNormal = BlockPos(-stepX, 0, 0)
            } else if tMaxY < tMaxZ {
                mapY += stepY; tMaxY += tDeltaY
                faceNormal = BlockPos(0, -stepY, 0)
            } else {
                mapZ += stepZ; tMaxZ += tDeltaZ
                faceNormal = BlockPos(0, 0, -stepZ)
            }

            let dist = SIMD3<Float>(Float(mapX), Float(mapY), Float(mapZ)) - origin
            if length(dist) > reach { break }

            let pos = BlockPos(mapX, mapY, mapZ)
            if worldBlocks[pos] != nil {
                return RayHit(blockPos: pos, faceNormal: faceNormal)
            }
        }
        return nil
    }

    // MARK: - Break / Place

    private func breakBlock() {
        guard let hit = raycast() else { return }
        worldBlocks.removeValue(forKey: hit.blockPos)
        worldDirty = true
    }

    private func placeBlock() {
        guard let hit = raycast() else { return }
        let p = BlockPos(
            hit.blockPos.x + hit.faceNormal.x,
            hit.blockPos.y + hit.faceNormal.y,
            hit.blockPos.z + hit.faceNormal.z
        )
        if worldBlocks[p] != nil { return }
        // Check if the new block would overlap the player's AABB
        let hw = playerWidth * 0.5
        let feetY = playerPos.y - eyeHeight
        let blockMin = SIMD3<Float>(Float(p.x) - 0.5, Float(p.y) - 0.5, Float(p.z) - 0.5)
        let blockMax = SIMD3<Float>(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        let playerMin = SIMD3<Float>(playerPos.x - hw, feetY, playerPos.z - hw)
        let playerMax = SIMD3<Float>(playerPos.x + hw, feetY + playerHeight, playerPos.z + hw)
        // AABB overlap test
        if blockMax.x > playerMin.x && blockMin.x < playerMax.x &&
           blockMax.y > playerMin.y && blockMin.y < playerMax.y &&
           blockMax.z > playerMin.z && blockMin.z < playerMax.z { return }
        worldBlocks[p] = currentBlock
        worldDirty = true
    }

    // MARK: - Mouse

    private func captureMouse() {
        mouseCaptured = true
        NSCursor.hide()
        if let win = window, let screen = NSScreen.main {
            CGWarpMouseCursorPosition(CGPoint(x: win.frame.midX, y: screen.frame.height - win.frame.midY))
        }
    }

    private func releaseMouse() {
        mouseCaptured = false
        NSCursor.unhide()
    }

    // MARK: - Input

    private func setupInput() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            self.keysPressed.insert(event.keyCode)
            if event.keyCode == 53 && self.mouseCaptured { self.releaseMouse() }
            // Cmd+S to save
            if event.modifierFlags.contains(.command) && event.characters == "s" {
                self.saveWorld()
                return nil
            }
            switch event.characters {
            case "1": self.currentBlock = .dirt
            case "2": self.currentBlock = .stone
            default: break
            }
            return nil  // consume event to prevent macOS alert sound
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.keysPressed.remove(event.keyCode); return nil
        }

        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            guard let self = self, self.mouseCaptured else { return event }
            self.playerYaw += Float(event.deltaX) * self.mouseSensitivity
            self.playerPitch -= Float(event.deltaY) * self.mouseSensitivity
            self.playerPitch = max(-Float.pi * 0.49, min(Float.pi * 0.49, self.playerPitch))
            // Re-center cursor to keep it captured
            if let win = self.window, let screen = NSScreen.main {
                let cx = win.frame.midX
                let cy = screen.frame.height - win.frame.midY
                CGWarpMouseCursorPosition(CGPoint(x: cx, y: cy))
            }
            return event
        }

        leftClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }
            if !self.mouseCaptured { self.captureMouse() } else { self.breakBlock() }
            return event
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self, self.mouseCaptured else { return event }
            self.placeBlock(); return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.modifierFlags.contains(.shift) { self?.keysPressed.insert(56) }
            else { self?.keysPressed.remove(56) }
            return event
        }
    }

    // MARK: - Player

    /// Block at integer coords occupies world space [bx-0.5, bx+0.5] etc.
    private func blockAt(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        return worldBlocks[BlockPos(x, y, z)] != nil
    }

    /// Check if any blocks overlap with an AABB defined by world-space min/max
    private func blocksOverlapping(minX: Float, maxX: Float, minY: Float, maxY: Float, minZ: Float, maxZ: Float) -> Bool {
        // Block at (bx,by,bz) occupies world [bx-0.5, bx+0.5]
        // Block bx overlaps [lo,hi] when bx+0.5 > lo AND bx-0.5 < hi
        // → bx > lo-0.5 AND bx < hi+0.5
        // → bx in [ceil(lo-0.5+eps), floor(hi+0.5-eps)]
        // Simplified: round lo up, round hi down
        let bxMin = Int(floor(minX + 0.5))
        let bxMax = Int(floor(maxX + 0.499))
        let byMin = Int(floor(minY + 0.5))
        let byMax = Int(floor(maxY + 0.499))
        let bzMin = Int(floor(minZ + 0.5))
        let bzMax = Int(floor(maxZ + 0.499))
        guard bxMin <= bxMax && byMin <= byMax && bzMin <= bzMax else { return false }
        for by in byMin...byMax {
            for bx in bxMin...bxMax {
                for bz in bzMin...bzMax {
                    if blockAt(bx, by, bz) { return true }
                }
            }
        }
        return false
    }

    /// Check if the player collides at the given eye position
    private func collidesAt(pos: SIMD3<Float>) -> Bool {
        let hw: Float = playerWidth * 0.5
        let feetY = pos.y - eyeHeight
        return blocksOverlapping(
            minX: pos.x - hw, maxX: pos.x + hw,
            minY: feetY, maxY: feetY + playerHeight,
            minZ: pos.z - hw, maxZ: pos.z + hw
        )
    }

    private func updatePlayer() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(Float(now - lastFrameTime), 0.05)
        lastFrameTime = now

        // Horizontal movement
        let forward = SIMD3<Float>(sin(playerYaw), 0, -cos(playerYaw))
        let right = SIMD3<Float>(cos(playerYaw), 0, sin(playerYaw))
        var moveDir = SIMD3<Float>(0, 0, 0)

        if keysPressed.contains(13) { moveDir += forward }  // W
        if keysPressed.contains(1)  { moveDir -= forward }  // S
        if keysPressed.contains(0)  { moveDir -= right }    // A
        if keysPressed.contains(2)  { moveDir += right }    // D

        let hLen = length(moveDir)
        if hLen > 0.001 {
            let hMove = (moveDir / hLen) * moveSpeed * dt
            var newPos = playerPos
            newPos.x += hMove.x
            if !collidesAt(pos: newPos) { playerPos.x = newPos.x }
            newPos = playerPos
            newPos.z += hMove.z
            if !collidesAt(pos: newPos) { playerPos.z = newPos.z }
        }

        // Gravity
        velocityY -= gravity * dt
        if velocityY < -50 { velocityY = -50 }

        let dy = velocityY * dt
        var newPos = playerPos
        newPos.y += dy

        if !collidesAt(pos: newPos) {
            playerPos.y = newPos.y
            onGround = false
        } else {
            if velocityY < 0 {
                let newFeetY = newPos.y - eyeHeight
                let landBlockY = Int(floor(newFeetY + 0.5))
                playerPos.y = Float(landBlockY) + 0.5 + eyeHeight + 0.001
                onGround = true
            }
            velocityY = 0
        }

        // Jump
        if keysPressed.contains(49) && onGround {
            velocityY = jumpVelocity
            onGround = false
        }

        // Void respawn
        if playerPos.y < -50 {
            playerPos = SIMD3<Float>(0, 5 + eyeHeight, 0)
            velocityY = 0
        }
    }

    // MARK: - Crosshair (textured quad from icons.png)

    private func updateCrosshairBuffer(aspect: Float) {
        // 16px crosshair at 720p → half-size in NDC on Y axis
        let sy: Float = 16.0 / 720.0 * 2.0  // ~0.044 in NDC height
        let sx: Float = sy / aspect           // correct for aspect ratio
        // Each vertex: (x, y, u, v)
        let verts: [SIMD4<Float>] = [
            SIMD4<Float>(-sx, -sy, 0, 1),
            SIMD4<Float>( sx, -sy, 1, 1),
            SIMD4<Float>( sx,  sy, 1, 0),
            SIMD4<Float>(-sx, -sy, 0, 1),
            SIMD4<Float>( sx,  sy, 1, 0),
            SIMD4<Float>(-sx,  sy, 0, 0),
        ]
        crosshairBuffer = device.makeBuffer(
            bytes: verts, length: verts.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared
        )
    }

    private func setupCrosshair() {
        updateCrosshairBuffer(aspect: 1280.0 / 720.0)
    }

    // MARK: - Block outline (wireframe cube)

    private func setupOutlineBuffer() {
        // 12 edges of a cube, slightly expanded to avoid z-fighting
        let e: Float = 0.502
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-e, -e, -e), SIMD3<Float>( e, -e, -e),
            SIMD3<Float>( e,  e, -e), SIMD3<Float>(-e,  e, -e),
            SIMD3<Float>(-e, -e,  e), SIMD3<Float>( e, -e,  e),
            SIMD3<Float>( e,  e,  e), SIMD3<Float>(-e,  e,  e),
        ]
        // 12 edges: bottom 4, top 4, vertical 4
        let edgeIndices: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,0),  // back face
            (4,5),(5,6),(6,7),(7,4),  // front face
            (0,4),(1,5),(2,6),(3,7),  // connecting
        ]
        var verts: [SIMD3<Float>] = []
        for (a, b) in edgeIndices {
            verts.append(corners[a])
            verts.append(corners[b])
        }
        outlineBuffer = device.makeBuffer(
            bytes: verts, length: verts.count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared
        )
    }

    // MARK: - Pipeline setup

    private func setupPipeline() {
        guard shaderLibrary?.library != nil else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = shaderLibrary?.getVertexFunction()
        desc.fragmentFunction = shaderLibrary?.getFragmentFunction()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float4; vd.attributes[1].offset = MemoryLayout<Float>.size * 3; vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float3; vd.attributes[2].offset = MemoryLayout<Float>.size * 7; vd.attributes[2].bufferIndex = 0
        vd.attributes[3].format = .float2; vd.attributes[3].offset = MemoryLayout<Float>.size * 10; vd.attributes[3].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<Vertex>.stride
        vd.layouts[0].stepRate = 1; vd.layouts[0].stepFunction = .perVertex
        desc.vertexDescriptor = vd

        do { pipelineState = try device.makeRenderPipelineState(descriptor: desc) }
        catch { print("[SWIFT] ERROR: Block pipeline: \(error)") }
    }

    private func setupCrosshairPipeline() {
        guard shaderLibrary?.library != nil else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = shaderLibrary?.getCrosshairVertexFunction()
        desc.fragmentFunction = shaderLibrary?.getCrosshairFragmentFunction()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        // Minecraft-style inverse crosshair: inverts background color
        desc.colorAttachments[0].sourceRGBBlendFactor = .oneMinusDestinationColor
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceColor
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .zero
        desc.depthAttachmentPixelFormat = .depth32Float

        do { crosshairPipeline = try device.makeRenderPipelineState(descriptor: desc) }
        catch { print("[SWIFT] ERROR: Crosshair pipeline: \(error)") }
    }

    private func setupOutlinePipeline() {
        guard shaderLibrary?.library != nil else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = shaderLibrary?.getOutlineVertexFunction()
        desc.fragmentFunction = shaderLibrary?.getOutlineFragmentFunction()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float

        do { outlinePipeline = try device.makeRenderPipelineState(descriptor: desc) }
        catch { print("[SWIFT] ERROR: Outline pipeline: \(error)") }
    }

    private func setupDepthState() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .less
        desc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: desc)

        // Outline depth: read but don't write (renders on top of block face)
        let odesc = MTLDepthStencilDescriptor()
        odesc.depthCompareFunction = .lessEqual
        odesc.isDepthWriteEnabled = false
        outlineDepthState = device.makeDepthStencilState(descriptor: odesc)
    }

    private func updateFPS() {
        framesThisSecond += 1
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastFPSTime >= 1.0 {
            currentFPS = framesThisSecond
            framesThisSecond = 0
            lastFPSTime = now
            let blockName = currentBlock == .dirt ? "Dirt" : "Stone"
            let total = worldBlocks.count
            let px = String(format: "%.1f", playerPos.x)
            let py = String(format: "%.1f", playerPos.y - eyeHeight)  // show feet Y
            let pz = String(format: "%.1f", playerPos.z)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.title = "Minecraft | \(blockName) | \(self.currentFPS) FPS | \(total) blocks | XYZ: \(px) \(py) \(pz)"
            }
        }
    }

    // MARK: - Draw

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if size.height > 0 {
            updateCrosshairBuffer(aspect: Float(size.width / size.height))
        }
    }

    func draw(in view: MTKView) {
        frameCount += 1
        updatePlayer()
        updateFPS()
        if worldDirty { rebuildInstanceBuffers() }

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let pipelineState = pipelineState,
              let cubeMesh = cubeMesh else { return }

        // --- 1. Draw blocks ---
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        if let ds = depthState { renderEncoder.setDepthStencilState(ds) }

        let viewMatrix = fpViewMatrix(position: playerPos, yaw: playerYaw, pitch: playerPitch)
        let aspect = Float(view.bounds.width / view.bounds.height)
        let projection = perspectiveMatrix(fovY: Float.pi / 3.0, aspect: aspect, near: 0.1, far: 100.0)
        let mvp = projection * viewMatrix
        var uniforms = Uniforms(modelViewProjectionMatrix: mvp, normalMatrix: matrix_identity_float4x4)

        renderEncoder.setVertexBuffer(cubeMesh.vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Dirt
        if dirtInstanceCount > 0, let buf = dirtInstanceBuffer {
            if let tex = blockTextures?.dirtTexture, let samp = blockTextures?.sampler {
                renderEncoder.setFragmentTexture(tex, index: 0)
                renderEncoder.setFragmentSamplerState(samp, index: 0)
            }
            renderEncoder.setVertexBuffer(buf, offset: 0, index: 2)
            if let ib = cubeMesh.indexBuffer {
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: cubeMesh.indexCount,
                    indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0, instanceCount: dirtInstanceCount)
            }
        }

        // Stone
        if stoneInstanceCount > 0, let buf = stoneInstanceBuffer {
            if let tex = blockTextures?.stoneTexture, let samp = blockTextures?.sampler {
                renderEncoder.setFragmentTexture(tex, index: 0)
                renderEncoder.setFragmentSamplerState(samp, index: 0)
            }
            renderEncoder.setVertexBuffer(buf, offset: 0, index: 2)
            if let ib = cubeMesh.indexBuffer {
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: cubeMesh.indexCount,
                    indexType: .uint16, indexBuffer: ib, indexBufferOffset: 0, instanceCount: stoneInstanceCount)
            }
        }

        // --- 2. Draw block outline for targeted block ---
        if let hit = raycast(), let olPipeline = outlinePipeline, let olBuf = outlineBuffer {
            renderEncoder.setRenderPipelineState(olPipeline)
            renderEncoder.setCullMode(.none)
            if let ods = outlineDepthState { renderEncoder.setDepthStencilState(ods) }

            // Offset outline to the targeted block position
            let blockCenter = SIMD3<Float>(Float(hit.blockPos.x), Float(hit.blockPos.y), Float(hit.blockPos.z))
            let outlineMVP = mvp * translationMatrix(blockCenter)
            var outlineUniforms = Uniforms(modelViewProjectionMatrix: outlineMVP, normalMatrix: matrix_identity_float4x4)

            renderEncoder.setVertexBuffer(olBuf, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&outlineUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: outlineVertexCount)
        }

        // --- 3. Draw crosshair ---
        if let chPipeline = crosshairPipeline, let chBuf = crosshairBuffer {
            renderEncoder.setRenderPipelineState(chPipeline)
            renderEncoder.setCullMode(.none)
            renderEncoder.setVertexBuffer(chBuf, offset: 0, index: 0)
            if let tex = blockTextures?.crosshairTexture, let samp = blockTextures?.sampler {
                renderEncoder.setFragmentTexture(tex, index: 0)
                renderEncoder.setFragmentSamplerState(samp, index: 0)
            }
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if frameCount == 1 {
            print("[SWIFT] First frame rendered!")
            fflush(stdout)
        }
    }

    // MARK: - Save / Load (.SMCW format)

    private static let saveFilePath: String = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".minecraft_swift").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/world.smcw"
    }()

    func saveWorld() {
        // Format: first line is player pos/rotation, then one line per block: type,x,y,z
        var lines: [String] = []
        lines.append("SMCW1")  // version header
        lines.append("player,\(playerPos.x),\(playerPos.y),\(playerPos.z),\(playerYaw),\(playerPitch)")
        for (pos, blockType) in worldBlocks {
            lines.append("\(blockType.rawValue),\(pos.x),\(pos.y),\(pos.z)")
        }
        let data = lines.joined(separator: "\n")
        do {
            try data.write(toFile: MetalRenderer.saveFilePath, atomically: true, encoding: .utf8)
            print("[SWIFT] World saved: \(worldBlocks.count) blocks → \(MetalRenderer.saveFilePath)")
        } catch {
            print("[SWIFT] ERROR saving world: \(error)")
        }
    }

    func loadWorld() -> Bool {
        guard FileManager.default.fileExists(atPath: MetalRenderer.saveFilePath) else { return false }
        do {
            let data = try String(contentsOfFile: MetalRenderer.saveFilePath, encoding: .utf8)
            let lines = data.components(separatedBy: "\n")
            guard lines.first == "SMCW1" else {
                print("[SWIFT] Invalid save file format")
                return false
            }
            var newBlocks: [BlockPos: BlockType] = [:]
            for line in lines.dropFirst() {
                let parts = line.components(separatedBy: ",")
                if parts.count == 6 && parts[0] == "player" {
                    if let px = Float(parts[1]), let py = Float(parts[2]), let pz = Float(parts[3]),
                       let yaw = Float(parts[4]), let pitch = Float(parts[5]) {
                        playerPos = SIMD3<Float>(px, py, pz)
                        playerYaw = yaw
                        playerPitch = pitch
                    }
                } else if parts.count == 4 {
                    if let typeRaw = Int(parts[0]), let bx = Int(parts[1]),
                       let by = Int(parts[2]), let bz = Int(parts[3]),
                       let blockType = BlockType(rawValue: typeRaw) {
                        newBlocks[BlockPos(bx, by, bz)] = blockType
                    }
                }
            }
            worldBlocks = newBlocks
            worldDirty = true
            velocityY = 0
            print("[SWIFT] World loaded: \(worldBlocks.count) blocks from \(MetalRenderer.saveFilePath)")
            return true
        } catch {
            print("[SWIFT] ERROR loading world: \(error)")
            return false
        }
    }
}

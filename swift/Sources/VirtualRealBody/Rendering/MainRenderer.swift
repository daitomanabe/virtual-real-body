import Foundation
import Metal
import MetalKit
import Satin
import simd

final class MainRenderer: MetalViewRenderer {
    private let poseReceiver = PoseReceiver()
    private var cameraCapture: CameraCapture?
    private var startTime = CACurrentMediaTime()

    private var jointBuffer: MTLBuffer?
    private var boneBuffer: MTLBuffer?
    private var virtualUniformBuffer: MTLBuffer?
    private var overlayUniformBuffer: MTLBuffer?

    private var virtualPipeline: MTLRenderPipelineState?
    private var overlayPipeline: MTLRenderPipelineState?
    private var compositorPipeline: MTLRenderPipelineState?

    private var virtualBodyTexture: MTLTexture?
    private var overlayTexture: MTLTexture?

    private var poseFrame = PoseFrame.empty
    private var viewportSize = SIMD2<Float>(2560, 720)

    override func setup() {
        poseReceiver.start()
        cameraCapture = CameraCapture(device: device)
        cameraCapture?.start()
        makeBuffers()
        buildPipelines()
    }

    override func cleanup() {
        poseReceiver.stop()
        cameraCapture?.stop()
    }

    override func update() {
        poseFrame = poseReceiver.latestFrame()

        let time = Float(CACurrentMediaTime() - startTime)
        let jointUniforms = (0..<JOINT_COUNT).map { index in
            let landmark = poseFrame.landmarks[index]
            let velocity = poseFrame.velocities[index]
            let speed = poseFrame.speeds[index]
            return JointUniform(
                positionXY: SIMD2<Float>(landmark.x, landmark.y),
                speed: speed,
                energy: simd_length(velocity),
                visibility: landmark.w
            )
        }

        updateBuffer(jointBuffer, with: jointUniforms)
        updateBuffer(boneBuffer, with: BONES.map { BoneUniform(joints: $0) })

        var virtualUniform = VirtualBodyUniform(
            time: time,
            resolution: viewportSize / SIMD2<Float>(2, 1),
            jointCount: UInt32(JOINT_COUNT),
            boneCount: UInt32(BONES.count)
        )
        updateBytes(virtualUniformBuffer, value: &virtualUniform)

        var overlayUniform = OverlayUniform(
            resolution: viewportSize / SIMD2<Float>(2, 1),
            detected: poseFrame.detected ? 1 : 0
        )
        updateBytes(overlayUniformBuffer, value: &overlayUniform)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let drawableTexture = renderPassDescriptor.colorAttachments[0].texture else { return }

        ensureRenderTargets(width: drawableTexture.width, height: drawableTexture.height)

        if let virtualPass = makeOffscreenPass(texture: virtualBodyTexture, label: "Virtual Body Pass"),
           let pipeline = virtualPipeline {
            encodeFullscreenPass(
                descriptor: virtualPass,
                pipeline: pipeline,
                commandBuffer: commandBuffer,
                fragmentTextures: [],
                label: "VirtualBody"
            ) { encoder in
                if let jointBuffer { encoder.setFragmentBuffer(jointBuffer, offset: 0, index: 0) }
                if let boneBuffer { encoder.setFragmentBuffer(boneBuffer, offset: 0, index: 1) }
                if let virtualUniformBuffer { encoder.setFragmentBuffer(virtualUniformBuffer, offset: 0, index: 2) }
            }
        }

        if let overlayPass = makeOffscreenPass(texture: overlayTexture, label: "Overlay Pass"),
           let pipeline = overlayPipeline {
            let fragmentTextures = cameraCapture?.currentTexture().map { [$0] } ?? []
            encodeFullscreenPass(
                descriptor: overlayPass,
                pipeline: pipeline,
                commandBuffer: commandBuffer,
                fragmentTextures: fragmentTextures,
                label: "PoseOverlay"
            ) { encoder in
                if let jointBuffer { encoder.setFragmentBuffer(jointBuffer, offset: 0, index: 0) }
                if let boneBuffer { encoder.setFragmentBuffer(boneBuffer, offset: 0, index: 1) }
                if let overlayUniformBuffer { encoder.setFragmentBuffer(overlayUniformBuffer, offset: 0, index: 2) }
            }
        }

        if let pipeline = compositorPipeline {
            encodeFullscreenPass(
                descriptor: renderPassDescriptor,
                pipeline: pipeline,
                commandBuffer: commandBuffer,
                fragmentTextures: [virtualBodyTexture, overlayTexture].compactMap { $0 },
                label: "Compositor"
            ) { _ in }
        }
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        viewportSize = SIMD2<Float>(size.width * scaleFactor, size.height * scaleFactor)
        virtualBodyTexture = nil
        overlayTexture = nil
    }

    override func keyDown(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            NSApplication.shared.terminate(nil)
            return true
        }
        return false
    }

    private func buildPipelines() {
        do {
            let library = try makeLibrary()
            virtualPipeline = try makePipeline(library: library, fragment: "virtualBodyFragment", label: "VirtualBodyPipeline")
            overlayPipeline = try makePipeline(library: library, fragment: "poseOverlayFragment", label: "PoseOverlayPipeline")
            compositorPipeline = try makePipeline(library: library, fragment: "compositorFragment", label: "CompositorPipeline")
        } catch {
            NSLog("MainRenderer pipeline build failed: \(error.localizedDescription)")
        }
    }

    private func makeLibrary() throws -> MTLLibrary {
        guard let shadersURL = Bundle.module.resourceURL?.appendingPathComponent("Shaders") else {
            throw NSError(domain: "vrb.render", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing shader resources"])
        }
        let files = ["VirtualBody.metal", "PoseOverlay.metal", "Compositor.metal"]
        let sources = try files.map { file in
            try LygiaResolver.resolve(url: shadersURL.appendingPathComponent(file))
        }
        return try device.makeLibrary(source: sources.joined(separator: "\n"), options: nil)
    }

    private func makePipeline(library: MTLLibrary, fragment: String, label: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func ensureRenderTargets(width: Int, height: Int) {
        let halfWidth = max(width / 2, 1)
        if virtualBodyTexture?.width != halfWidth || virtualBodyTexture?.height != height {
            virtualBodyTexture = makeRenderTarget(width: halfWidth, height: height, label: "VirtualBodyTexture")
        }
        if overlayTexture?.width != halfWidth || overlayTexture?.height != height {
            overlayTexture = makeRenderTarget(width: halfWidth, height: height, label: "OverlayTexture")
        }
        viewportSize = SIMD2<Float>(Float(width), Float(height))
    }

    private func makeRenderTarget(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private func makeOffscreenPass(texture: MTLTexture?, label: String) -> MTLRenderPassDescriptor? {
        guard let texture else { return nil }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.renderTargetWidth = texture.width
        descriptor.renderTargetHeight = texture.height
        descriptor.label = label
        return descriptor
    }

    private func encodeFullscreenPass(
        descriptor: MTLRenderPassDescriptor,
        pipeline: MTLRenderPipelineState,
        commandBuffer: MTLCommandBuffer,
        fragmentTextures: [MTLTexture],
        label: String,
        configure: (MTLRenderCommandEncoder) -> Void
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in fragmentTextures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeBuffers() {
        jointBuffer = device.makeBuffer(length: MemoryLayout<JointUniform>.stride * JOINT_COUNT)
        boneBuffer = device.makeBuffer(length: MemoryLayout<BoneUniform>.stride * BONES.count)
        virtualUniformBuffer = device.makeBuffer(length: MemoryLayout<VirtualBodyUniform>.stride)
        overlayUniformBuffer = device.makeBuffer(length: MemoryLayout<OverlayUniform>.stride)
    }

    private func updateBuffer<T>(_ buffer: MTLBuffer?, with values: [T]) {
        guard let buffer else { return }
        let size = MemoryLayout<T>.stride * values.count
        values.withUnsafeBytes { rawBuffer in
            memcpy(buffer.contents(), rawBuffer.baseAddress, size)
        }
    }

    private func updateBytes<T>(_ buffer: MTLBuffer?, value: inout T) {
        guard let buffer else { return }
        memcpy(buffer.contents(), &value, MemoryLayout<T>.stride)
    }
}

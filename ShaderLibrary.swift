import Foundation
import Metal

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float3 normal [[attribute(2)]];
    float2 uv [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
    float2 uv;
};

struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 normalMatrix;
};

vertex VertexOut vertexShader(VertexIn vertexIn [[stage_in]],
                               constant Uniforms& uniforms [[buffer(1)]],
                               constant float3* instanceOffsets [[buffer(2)]],
                               uint instanceID [[instance_id]]) {
    VertexOut out;
    float3 worldPos = vertexIn.position + instanceOffsets[instanceID];
    out.position = uniforms.modelViewProjectionMatrix * float4(worldPos, 1.0);
    out.color = vertexIn.color;
    out.normal = normalize((uniforms.normalMatrix * float4(vertexIn.normal, 0.0)).xyz);
    out.uv = vertexIn.uv;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                texture2d<float> blockTex [[texture(0)]],
                                sampler texSampler [[sampler(0)]]) {
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(float3(1.0, 1.0, 1.0));

    float ambient = 0.6;
    float diffuse = max(0.0, dot(normal, lightDir)) * 0.4;
    float lighting = ambient + diffuse;

    float4 texColor = blockTex.sample(texSampler, in.uv);
    float3 color = texColor.rgb * lighting;
    return float4(color, 1.0);
}

// --- Crosshair shaders (textured quad with alpha) ---

struct UIOut {
    float4 position [[position]];
    float2 uv;
};

vertex UIOut crosshairVertex(uint vid [[vertex_id]],
                              constant float4* verts [[buffer(0)]]) {
    // verts: xy = position (NDC), zw = uv
    UIOut out;
    out.position = float4(verts[vid].xy, 0.0, 1.0);
    out.uv = verts[vid].zw;
    return out;
}

fragment float4 crosshairFragment(UIOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler samp [[sampler(0)]]) {
    float4 c = tex.sample(samp, in.uv);
    if (c.a < 0.1) discard_fragment();
    // Return white - blending will invert the destination color
    return float4(1.0, 1.0, 1.0, 1.0);
}

// --- Block outline shaders ---

struct OutlineOut {
    float4 position [[position]];
};

vertex OutlineOut outlineVertex(uint vid [[vertex_id]],
                                 constant float3* verts [[buffer(0)]],
                                 constant Uniforms& uniforms [[buffer(1)]]) {
    OutlineOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(verts[vid], 1.0);
    return out;
}

fragment float4 outlineFragment() {
    return float4(0.0, 0.0, 0.0, 1.0);  // solid black
}
"""

class ShaderLibrary {
    let library: MTLLibrary?

    init(device: MTLDevice) {
        do {
            self.library = try device.makeLibrary(source: shaderSource, options: nil)
            print("[SWIFT] Shader library created successfully")
        } catch {
            print("[SWIFT] ERROR: Failed to create shader library: \(error)")
            self.library = nil
        }
    }

    func getVertexFunction() -> MTLFunction? { library?.makeFunction(name: "vertexShader") }
    func getFragmentFunction() -> MTLFunction? { library?.makeFunction(name: "fragmentShader") }
    func getCrosshairVertexFunction() -> MTLFunction? { library?.makeFunction(name: "crosshairVertex") }
    func getCrosshairFragmentFunction() -> MTLFunction? { library?.makeFunction(name: "crosshairFragment") }
    func getOutlineVertexFunction() -> MTLFunction? { library?.makeFunction(name: "outlineVertex") }
    func getOutlineFragmentFunction() -> MTLFunction? { library?.makeFunction(name: "outlineFragment") }
}

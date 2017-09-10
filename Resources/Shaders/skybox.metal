//
//  skybox.metal
//  Viewer
//
//  Created by Warren Moore on 9/10/17.
//  Copyright © 2017 Warren Moore. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexUniforms {
    float4x4 modelMatrix;
    float4x4 modelViewProjectionMatrix;
};

struct VertexOut {
    float4 clipPosition [[position]];
    float4 worldPosition;
};

vertex VertexOut skybox_vertex_main(device packed_float3 *vertices [[buffer(0)]],
                                    constant VertexUniforms &uniforms [[buffer(1)]],
                                    uint vid [[vertex_id]])
{
    VertexOut out;
    float4 position = float4(float3(vertices[vid]), 1);
    out.worldPosition = uniforms.modelMatrix * position;
    out.clipPosition = uniforms.modelViewProjectionMatrix * position;
    return out;
}

typedef VertexOut FragmentIn;

fragment float4 skybox_fragment_main(FragmentIn in [[stage_in]],
                                     texturecube<float, access::sample> skyboxTexture [[texture(0)]])
{
    constexpr sampler linearSampler(coord::normalized, min_filter::linear, mag_filter::linear, mip_filter::linear);
    float3 normal = normalize(in.worldPosition.xyz);
    float4 color = skyboxTexture.sample(linearSampler, normal);
    return color;
}

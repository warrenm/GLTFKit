//
//  Copyright (c) 2018 Warren Moore. All rights reserved.
//
//  Permission to use, copy, modify, and distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
//  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
//  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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

vertex VertexOut skybox_vertex_main(constant packed_float3 *vertices [[buffer(0)]],
                                    constant VertexUniforms &uniforms [[buffer(1)]],
                                    uint vid [[vertex_id]])
{
    VertexOut out;
    float4 position = float4(float3(vertices[vid]), 1);
    out.worldPosition = uniforms.modelMatrix * position;
    out.clipPosition = (uniforms.modelViewProjectionMatrix * position).xyww;
    return out;
}

typedef VertexOut FragmentIn;

fragment half4 skybox_fragment_main(FragmentIn in [[stage_in]],
                                     constant float &environmentIntensity [[buffer(0)]],
                                     texturecube<half, access::sample> skyboxTexture [[texture(0)]])
{
    constexpr sampler linearSampler(coord::normalized, min_filter::linear, mag_filter::linear, mip_filter::linear);
    float3 normal = normalize(in.worldPosition.xyz);
    normal *= float3(1, 1, -1);
    half3 color = skyboxTexture.sample(linearSampler, normal).rgb;
    return half4(color, 1);
}

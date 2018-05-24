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

constexpr sampler linearSampler(coord::normalized, min_filter::linear, mag_filter::linear);

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

vertex VertexOut quad_vertex_main(constant packed_float4 *vertices [[buffer(0)]],
                                  uint vid [[vertex_id]])
{
    VertexOut out;
    float4 in = vertices[vid];
    out.position = float4(in.xy, 0, 1);
    out.texCoords = in.zw;
    return out;
}

typedef VertexOut FragmentIn;

static half3 reinhardToneMapping(half3 color) {
    half exposure = 1.5;
    color *= exposure / (1 + color / exposure);
    return color;
}

fragment half4 tonemap_fragment_main(FragmentIn in [[stage_in]],
                                     texture2d<half, access::sample> sourceTexture [[texture(0)]])
{
    half3 color = sourceTexture.sample(linearSampler, in.texCoords).rgb;
    return half4(reinhardToneMapping(color), 1);
}


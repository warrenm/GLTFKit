//
//  Copyright (c) 2017 Warren Moore. All rights reserved.
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

constant float minRoughness = 0.04;

constant int textureIndexBaseColor           = 0;
constant int textureIndexNormal              = 1;
constant int textureIndexMetallicRoughness   = 2;
constant int textureIndexOcclusion           = 3;
constant int textureIndexEmissive            = 4;
constant int textureIndexDiffuseEnvironment  = 5;
constant int textureIndexSpecularEnvironment = 6;
constant int textureIndexBRDFLookup          = 7;

/*%begin_replace_decls%*/
#define USE_PBR 1
#define USE_IBL 1
#define USE_ALPHA_TEST 0
#define USE_VERTEX_SKINNING 1
#define USE_EXTENDED_VERTEX_SKINNING 1
#define HAS_TEXCOORD_0 1
#define HAS_TEXCOORD_1 1
#define HAS_VERTEX_COLOR 1
#define HAS_VERTEX_ROUGHNESS 1
#define HAS_VERTEX_METALLIC 1
#define HAS_NORMALS 1
#define HAS_TANGENTS 1
#define HAS_BASE_COLOR_MAP 1
#define HAS_NORMAL_MAP 1
#define HAS_METALLIC_ROUGHNESS_MAP 1
#define HAS_OCCLUSION_MAP 1
#define HAS_EMISSIVE_MAP 1
#define MAX_LIGHTS 4

#define baseColorTexCoord          texCoord0
#define normalTexCoord             texCoord0
#define metallicRoughnessTexCoord  texCoord0
#define emissiveTexCoord           texCoord0
#define occlusionTexCoord          texCoord0

#define joints joints0
#define weights weights0

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float4 tangent   [[attribute(2)]];
    float2 texCoord0 [[attribute(3)]];
    float2 texCoord1 [[attribute(4)]];
    float4 color     [[attribute(5)]];
    float4 weights0  [[attribute(6)]];
    float4 weights1  [[attribute(7)]];
    ushort4 joints0  [[attribute(8)]];
    ushort4 joints1  [[attribute(9)]];
    float roughness  [[attribute(10)]];
    float metalness  [[attribute(11)]];
};
/*%end_replace_decls%*/

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float2 texCoord0;
    float2 texCoord1;
    float4 color;
    float3 tangent;
    float3 bitangent;
    float3 normal;
    float roughness;
    float metalness;
};

struct VertexUniforms {
    float4x4 modelMatrix;
    float4x4 modelViewProjectionMatrix;
};

struct Light {
    float4 positionDirection;
    float4 color;
    float intensity;
    float innerConeAngle;
    float outerConeAngle;
    float pad;
};

struct FragmentUniforms {
    float normalScale;
    float3 emissiveFactor;
    float occlusionStrength;
    float2 metallicRoughnessValues;
    float4 baseColorFactor;
    float3 camera;
    float alphaCutoff;
    Light lights[MAX_LIGHTS];
};

struct LightingParameters {
    float NdotL;
    float NdotV;
    float NdotH;
    float LdotH;
    float VdotH;
    float perceptualRoughness;
    float metalness;
    float3 baseColor;
    float3 F0;
    float alphaRoughness;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant VertexUniforms &uniforms [[buffer(16)]]
#if USE_VERTEX_SKINNING
                           , constant float4x4 *jointMatrices  [[buffer(17)]]
#endif
)
{
    VertexOut out = { 0 };
    
    float4x4 normalMatrix = uniforms.modelMatrix;
    
    #if USE_VERTEX_SKINNING
        ushort4 jointIndices = ushort4(in.joints0);
        float4 jointWeights = float4(in.weights0);
        
        float4x4 skinMatrix = jointWeights[0] * jointMatrices[jointIndices[0]] +
                              jointWeights[1] * jointMatrices[jointIndices[1]] +
                              jointWeights[2] * jointMatrices[jointIndices[2]] +
                              jointWeights[3] * jointMatrices[jointIndices[3]];

        #if USE_EXTENDED_VERTEX_SKINNING
            jointIndices = ushort4(in.joints1);
            jointWeights = float4(in.weights1);

            skinMatrix += jointWeights[0] * jointMatrices[jointIndices[0]] +
                          jointWeights[1] * jointMatrices[jointIndices[1]] +
                          jointWeights[2] * jointMatrices[jointIndices[2]] +
                          jointWeights[3] * jointMatrices[jointIndices[3]];
        #endif
        
        float4 skinnedPosition = skinMatrix * float4(in.position.xyz, 1);
        normalMatrix = skinMatrix * normalMatrix;
    #else
        float4 skinnedPosition = float4(in.position.xyz, 1);
    #endif

    float4 position = uniforms.modelMatrix * skinnedPosition;
    out.worldPosition = position.xyz / position.w;
    
    out.position = uniforms.modelViewProjectionMatrix * skinnedPosition;

    #if HAS_NORMALS
        #if HAS_TANGENTS
            float3 normalW = normalize(float3(normalMatrix * float4(in.normal.xyz, 0.0)));
            float3 tangentW = normalize(float3(normalMatrix * float4(in.tangent.xyz, 0.0)));
            float3 bitangentW = cross(normalW, tangentW) * in.tangent.w;
            out.tangent = tangentW;
            out.bitangent = bitangentW;
            out.normal = normalW;
        #else
            out.normal = normalize(float3(normalMatrix * float4(in.normal.xyz, 0.0)));
        #endif
    #endif

    #if HAS_VERTEX_COLOR
        out.color = in.color;
    #endif
    
    #if HAS_VERTEX_ROUGHNESS
        out.roughness = in.roughness;
    #endif
    
    #if HAS_VERTEX_METALLIC
        out.metalness = in.metalness;
    #endif

    #if HAS_TEXCOORD_0
        out.texCoord0 = in.texCoord0;
    #endif
    
    #if HAS_TEXCOORD_1
        out.texCoord1 = in.texCoord1;
    #endif

    return out;
}

static float3 LambertDiffuse(LightingParameters pbrInputs)
{
    return pbrInputs.baseColor / M_PI_F;
}

static float3 FresnelReflectance(LightingParameters pbrInputs)
{
    return pbrInputs.F0 + (1 - pbrInputs.F0) * pow(saturate(1.0 - pbrInputs.VdotH), 5.0);
}

static float SmithG1(float NdotV, float r)
{
    float k = pow(r + 1, 2) * 0.125;
    float g = NdotV / ((NdotV * (1 - k)) + k);
    return g;
}

static float SmithAttenuation(LightingParameters pbrInputs)
{
    return SmithG1(pbrInputs.NdotL, pbrInputs.alphaRoughness) * SmithG1(pbrInputs.NdotV, pbrInputs.alphaRoughness);
}

static float TrowbridgeReitzNDF(LightingParameters pbrInputs)
{
    float roughnessSq = pbrInputs.alphaRoughness * pbrInputs.alphaRoughness;
    float f = (pbrInputs.NdotH * roughnessSq - pbrInputs.NdotH) * pbrInputs.NdotH + 1.0;
    return roughnessSq / (M_PI_F * f * f);
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
#if HAS_BASE_COLOR_MAP
                              texture2d<float, access::sample> baseColorTexture [[texture(textureIndexBaseColor)]],
                              sampler baseColorSampler [[sampler(textureIndexBaseColor)]],
#endif
#if HAS_NORMAL_MAP
                              texture2d<float, access::sample> normalTexture [[texture(textureIndexNormal)]],
                              sampler normalSampler [[sampler(textureIndexNormal)]],
#endif
#if HAS_EMISSIVE_MAP
                              texture2d<float, access::sample> emissiveTexture [[texture(textureIndexEmissive)]],
                              sampler emissiveSampler [[sampler(textureIndexEmissive)]],
#endif
#if HAS_METALLIC_ROUGHNESS_MAP
                              texture2d<float, access::sample> metallicRoughnessTexture [[texture(textureIndexMetallicRoughness)]],
                              sampler metallicRoughnessSampler [[sampler(textureIndexMetallicRoughness)]],
#endif
#if HAS_OCCLUSION_MAP
                              texture2d<float, access::sample> occlusionTexture [[texture(textureIndexOcclusion)]],
                              sampler occlusionSampler [[sampler(textureIndexOcclusion)]],
#endif
#if USE_IBL
                              texturecube<float, access::sample> diffuseEnvTexture [[texture(textureIndexDiffuseEnvironment)]],
                              texturecube<float, access::sample> specularEnvTexture [[texture(textureIndexSpecularEnvironment)]],
                              texture2d<float, access::sample> brdfLUT [[texture(textureIndexBRDFLookup)]],
#endif
                              constant FragmentUniforms &uniforms [[buffer(0)]])
{
    float3x3 tbn;
    #if !HAS_TANGENTS
        float3 pos_dx = dfdx(in.worldPosition);
        float3 pos_dy = dfdy(in.worldPosition);
        float3 tex_dx = dfdx(float3(in.texCoord0, 0));
        float3 tex_dy = dfdy(float3(in.texCoord0, 0));
        float3 t = (tex_dy.y * pos_dx - tex_dx.y * pos_dy) / (tex_dx.x * tex_dy.y - tex_dy.x * tex_dx.y);
        
        float3 ng(0);
        #if HAS_NORMALS
            ng = normalize(in.normal);
        #else
            ng = cross(pos_dx, pos_dy);
        #endif
        t = normalize(t - ng * dot(ng, t));
        float3 b = normalize(cross(ng, t));
        tbn = float3x3(t, b, ng);
    #else
        tbn = float3x3(in.tangent, in.bitangent, in.normal);
    #endif
    
    float3 n(0);
    #if HAS_NORMAL_MAP
        n = normalTexture.sample(normalSampler, in.normalTexCoord).rgb;
        n = normalize(tbn * ((2 * n - 1) * float3(uniforms.normalScale, uniforms.normalScale, 1)));
    #else
        n = tbn[2].xyz;
    #endif
    
    float perceptualRoughness = uniforms.metallicRoughnessValues.y;
    float metallic = uniforms.metallicRoughnessValues.x;
    
    #if HAS_METALLIC_ROUGHNESS_MAP
        float4 mrSample = metallicRoughnessTexture.sample(metallicRoughnessSampler, in.metallicRoughnessTexCoord);
        perceptualRoughness = mrSample.g * perceptualRoughness;
        metallic = mrSample.b * metallic;
    #endif
    
    #if HAS_VERTEX_ROUGHNESS
        perceptualRoughness = in.roughness;
    #endif
        
    #if HAS_VERTEX_METALLIC
        metallic = in.metalness;
    #endif

    perceptualRoughness = clamp(perceptualRoughness, minRoughness, 1.0);
    metallic = saturate(metallic);

    float4 baseColor;
    #if HAS_BASE_COLOR_MAP
        baseColor = baseColorTexture.sample(baseColorSampler, in.baseColorTexCoord) * uniforms.baseColorFactor;
    #else
        baseColor = uniforms.baseColorFactor;
    #endif
    
    #if HAS_VERTEX_COLOR
        baseColor *= in.color;
    #endif
    
    float3 f0 = float3(0.04);

    float3 diffuseColor = mix(baseColor.rgb * (1 - f0), float3(0), metallic);

    float3 specularColor = mix(f0, baseColor.rgb, metallic);
    
    float3 color(0);
    
    float3 v = normalize(uniforms.camera - in.worldPosition);
    float3 reflection = -normalize(reflect(v, n));
    float NdotV = clamp(dot(n, v), 0.001, 1.0);

    float3 specularEnvironmentR0 = specularColor.rgb;
    
    float alphaRoughness = perceptualRoughness * perceptualRoughness;

    #if USE_PBR
        for (int i = 0; i < MAX_LIGHTS; ++i) {
            Light light = uniforms.lights[i];
            
            float3 l = normalize(light.positionDirection.xyz);
            float3 h = normalize(l + v);

            float NdotL = clamp(dot(n, l), 0.001, 1.0);
            float NdotH = saturate(dot(n, h));
            float LdotH = saturate(dot(l, h));
            float VdotH = saturate(dot(v, h));

            LightingParameters pbrInputs = {
                .NdotL = NdotL,
                .NdotV = NdotV,
                .NdotH = NdotH,
                .LdotH = LdotH,
                .VdotH = VdotH,
                .perceptualRoughness = perceptualRoughness,
                .metalness = metallic,
                .baseColor = diffuseColor,
                .F0 = specularEnvironmentR0,
                .alphaRoughness = alphaRoughness
            };
            
            float3 F = FresnelReflectance(pbrInputs);
            float G = SmithAttenuation(pbrInputs);
            float D = TrowbridgeReitzNDF(pbrInputs);
            
            float3 diffuseContrib = NdotL * (1.0 - F) * LambertDiffuse(pbrInputs);

            float3 specContrib = F * G * D / (4.0 * NdotL * NdotV);
            
            color += light.color.rgb * light.intensity * (diffuseContrib + specContrib);
        }
    #endif
    
    #if USE_IBL
        constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    
        float envIntensity = 1.0;
    
        float mipCount = specularEnvTexture.get_num_mip_levels();
        float lod = perceptualRoughness * mipCount;
        float2 brdf = brdfLUT.sample(linearSampler, float2(NdotV, perceptualRoughness)).xy;
        float3 diffuseLight = diffuseEnvTexture.sample(linearSampler, n).rgb;
        diffuseLight *= envIntensity;
    
        float3 specularLight;
        if (mipCount > 1) {
            specularLight = specularEnvTexture.sample(linearSampler, reflection, level(lod)).rgb;
        } else {
            specularLight = specularEnvTexture.sample(linearSampler, reflection).rgb;
        }
        specularLight *= envIntensity;
    
        float3 iblDiffuse = diffuseLight * diffuseColor;
        float3 iblSpecular = specularLight * ((specularColor * brdf.x) + brdf.y);
    
        float3 iblColor = iblDiffuse + iblSpecular;
    
        color += iblColor;
    #endif
    
    #if HAS_OCCLUSION_MAP
        float ao = occlusionTexture.sample(occlusionSampler, in.occlusionTexCoord).r;
        color = mix(color, color * ao, uniforms.occlusionStrength);
    #endif
    
    #if HAS_EMISSIVE_MAP
        float3 emissive = emissiveTexture.sample(emissiveSampler, in.emissiveTexCoord).rgb * uniforms.emissiveFactor;
        color += emissive;
    #else
        color += uniforms.emissiveFactor;
    #endif
    
    #if USE_ALPHA_TEST
        if (baseColor.a < uniforms.alphaCutoff) {
            discard_fragment();
        }
    #endif
    
    return float4(color, baseColor.a);
}

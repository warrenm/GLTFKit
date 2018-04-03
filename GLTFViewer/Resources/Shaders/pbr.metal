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
#define USE_DOUBLE_SIDED_MATERIAL 1
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
#define SPECULAR_ENV_MIP_LEVELS 6
#define MAX_LIGHTS 3

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
    float4 position;
    float4 color;
    float intensity;
    float innerConeAngle;
    float outerConeAngle;
    float pad;
    float4 spotDirection;
};

struct FragmentUniforms {
    float normalScale;
    float3 emissiveFactor;
    float occlusionStrength;
    float2 metallicRoughnessValues;
    float4 baseColorFactor;
    float3 camera;
    float alphaCutoff;
    float envIntensity;
    Light ambientLight;
    Light lights[MAX_LIGHTS];
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
        #if VERTEX_COLOR_IS_RGB
            out.color = float4(in.color, 1);
        #else
            out.color = in.color;
        #endif
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

static float3 LambertDiffuse(float3 baseColor)
{
    return baseColor / M_PI_F;
}

static float3 SchlickFresnel(float3 F0, float LdotH)
{
    return F0 + (1 - F0) * pow(1.0 - LdotH, 5.0);
}

static float SmithGeometric(float NdotL, float NdotV, float roughness)
{
    float k = roughness * 0.5;
    float Gl = NdotL / ((NdotL * (1 - k)) + k);
    float Gv = NdotV / ((NdotV * (1 - k)) + k);
    return Gl * Gv;
}

static float TrowbridgeReitzNDF(float NdotH, float roughness)
{
    float roughnessSq = roughness * roughness;
    float f = NdotH * (NdotH * roughnessSq - NdotH) + 1;
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
                              constant FragmentUniforms &uniforms [[buffer(0)]],
                              bool frontFacing [[front_facing]])
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
    
    float3 N(0, 0, 1);
    #if HAS_NORMAL_MAP
        N = normalTexture.sample(normalSampler, in.normalTexCoord).rgb;
        N = normalize(tbn * ((2 * N - 1) * float3(uniforms.normalScale, uniforms.normalScale, 1)));
    #else
        N = tbn[2].xyz;
    #endif
    
    #if USE_DOUBLE_SIDED_MATERIAL
        N *= frontFacing ? 1 : -1;
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

    float3 F0 = specularColor.rgb;

    float alphaRoughness = perceptualRoughness * perceptualRoughness;

    float3 V = normalize(uniforms.camera - in.worldPosition);
    float NdotV = saturate(dot(N, V));
    
    float3 reflection = -normalize(reflect(V, N));

    float3 color(0);

    #if USE_PBR
        color += uniforms.ambientLight.color.rgb * uniforms.ambientLight.intensity * diffuseColor;

        for (int i = 0; i < MAX_LIGHTS; ++i) {
            Light light = uniforms.lights[i];
            
            float3 L = normalize((light.position.w == 0) ? -light.position.xyz : (light.position.xyz - in.worldPosition));
            float3 H = normalize(L + V);

            float NdotL = saturate(dot(N, L));
            float NdotH = saturate(dot(N, H));
            float VdotH = saturate(dot(V, H));
            
            float3 F = SchlickFresnel(F0, VdotH);
            float G = SmithGeometric(NdotL, NdotV, alphaRoughness);
            float D = TrowbridgeReitzNDF(NdotH, alphaRoughness);
            
            float3 diffuseContrib(0);
            float3 specContrib(0);
            if (NdotL > 0) {
                diffuseContrib = NdotL * LambertDiffuse(diffuseColor);
                specContrib = NdotL * D * F * G / (4.0 * NdotL * NdotV);
            }

            float atten = (light.position.w == 0) ? 1 : (1 / (1 + powr(length(light.position.xyz - in.worldPosition), 2)));

            float relativeSpotAngle = acos(dot(-L, normalize(light.spotDirection.xyz)));
            float spotAttenParam = 1 - clamp((relativeSpotAngle - light.innerConeAngle) / max(0.001, light.outerConeAngle - light.innerConeAngle), 0.0, 1.0);
            float spotAtten = spotAttenParam * spotAttenParam * (3 - 2 * spotAttenParam);
            atten *= spotAtten;

            color += light.color.rgb * light.intensity * atten * (diffuseContrib + specContrib);
        }
    #endif

    #if USE_IBL
        constexpr sampler cubeSampler(coord::normalized, filter::linear, mip_filter::linear);
    
        float mipCount = SPECULAR_ENV_MIP_LEVELS;
        float lod = perceptualRoughness * mipCount;
        float2 brdf = brdfLUT.sample(cubeSampler, float2(NdotV, perceptualRoughness)).xy;
        float3 diffuseLight = diffuseEnvTexture.sample(cubeSampler, N).rgb;
        diffuseLight *= uniforms.envIntensity;
    
        float3 specularLight(0);
        if (mipCount > 1) {
            specularLight = specularEnvTexture.sample(cubeSampler, reflection, level(lod)).rgb;
        } else {
            specularLight = specularEnvTexture.sample(cubeSampler, reflection).rgb;
        }
        specularLight *= uniforms.envIntensity;
    
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
        float3 emissive = emissiveTexture.sample(emissiveSampler, in.emissiveTexCoord).rgb;
        color += emissive * uniforms.emissiveFactor;
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

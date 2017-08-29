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

constant float pi = 3.141592653589793;
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
#define USE_VERTEX_SKINNING 1
#define HAS_TEXCOORDS 1
#define HAS_NORMALS 1
#define HAS_TANGENTS 1
#define HAS_BASE_COLOR_MAP 1
#define HAS_NORMAL_MAP 1
#define HAS_METALLIC_ROUGHNESS_MAP 1
#define HAS_OCCLUSION_MAP 1
#define HAS_EMISSIVE_MAP 1
#define SPECULAR_ENV_MAP_LOD_LEVELS 9

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float4 tangent   [[attribute(2)]];
    float2 texCoords [[attribute(3)]];
    float4 weights   [[attribute(4)]];
    ushort4 joints   [[attribute(5)]];
};
/*%end_replace_decls%*/

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float2 texCoords;
    float3 tangent;
    float3 bitangent;
    float3 normal;
};

struct VertexUniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
};

struct FragmentUniforms {
    float3 lightDirection;
    float3 lightColor;
    float normalScale;
    float3 emissiveFactor;
    float occlusionStrength;
    float2 metallicRoughnessValues;
    float4 baseColorFactor;
    float3 camera;
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
    float3 reflectance0;
    float3 reflectance90;
    float alphaRoughness;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant VertexUniforms &uniforms [[buffer(8)]]
#if USE_VERTEX_SKINNING
                           , constant float4x4 *jointMatrices  [[buffer(9)]]
#endif
)
{
    VertexOut out;
    
    #if USE_VERTEX_SKINNING
        ushort4 jointIndices = ushort4(in.joints);
        float4 jointWeights = float4(in.weights);
        
        float4x4 skinMatrix = jointWeights[0] * jointMatrices[jointIndices[0]] +
                              jointWeights[1] * jointMatrices[jointIndices[1]] +
                              jointWeights[2] * jointMatrices[jointIndices[2]] +
                              jointWeights[3] * jointMatrices[jointIndices[3]];
        
        float4 skinnedPosition = skinMatrix * float4(in.position.xyz, 1);
    #else
        float4 skinnedPosition = float4(in.position.xyz, 1);
    #endif

    float4 position = uniforms.modelMatrix * skinnedPosition;
    out.worldPosition = position.xyz / position.w;
    
    out.position = uniforms.modelViewProjectionMatrix * skinnedPosition;

    #if HAS_NORMALS
        #if HAS_TANGENTS
            float3 normalW = normalize(float3(uniforms.modelMatrix * float4(in.normal.xyz, 0.0)));
            float3 tangentW = normalize(float3(uniforms.modelMatrix * float4(in.tangent.xyz, 0.0)));
            float3 bitangentW = cross(normalW, tangentW) * in.tangent.w;
            out.tangent = tangentW;
            out.bitangent = bitangentW;
            out.normal = normalW;
        #else
            out.normal = normalize(float3(uniforms.modelMatrix * float4(in.normal.xyz, 0.0)));
        #endif
    #endif

    #if HAS_TEXCOORDS
        out.texCoords = in.texCoords;
    #else
        out.texCoords = float2(0);
    #endif
    
    return out;
}

static float3 lambertianDiffuse(LightingParameters pbrInputs)
{
    return pbrInputs.baseColor / pi;
}

static float3 fresnelSchlick2(LightingParameters pbrInputs)
{
    return pbrInputs.reflectance0 + (pbrInputs.reflectance90 - pbrInputs.reflectance0) * pow(clamp(1.0 - pbrInputs.VdotH, 0.0, 1.0), 5.0);
}

static float SmithG1_var2(float NdotV, float r)
{
    float tanSquared = (1.0 - NdotV * NdotV) / max((NdotV * NdotV), 0.00001);
    return 2.0 / (1.0 + sqrt(1.0 + r * r * tanSquared));
}

static float geometricOcclusionSmithGGX(LightingParameters pbrInputs)
{
    return SmithG1_var2(pbrInputs.NdotL, pbrInputs.alphaRoughness) * SmithG1_var2(pbrInputs.NdotV, pbrInputs.alphaRoughness);
}

static float GGX(LightingParameters pbrInputs)
{
    float roughnessSq = pbrInputs.alphaRoughness*pbrInputs.alphaRoughness;
    float f = (pbrInputs.NdotH * roughnessSq - pbrInputs.NdotH) * pbrInputs.NdotH + 1.0;
    return roughnessSq / (pi * f * f);
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
#if HAS_BASE_COLOR_MAP
                              texture2d<float, access::sample> baseColorTexture [[texture(textureIndexBaseColor)]],
#endif
#if HAS_NORMAL_MAP
                              texture2d<float, access::sample> normalTexture [[texture(textureIndexNormal)]],
#endif
#if HAS_EMISSIVE_MAP
                              texture2d<float, access::sample> emissiveTexture [[texture(textureIndexEmissive)]],
#endif
#if HAS_METALLIC_ROUGHNESS_MAP
                              texture2d<float, access::sample> metallicRoughnessTexture [[texture(textureIndexMetallicRoughness)]],
#endif
#if HAS_OCCLUSION_MAP
                              texture2d<float, access::sample> occlusionTexture [[texture(textureIndexOcclusion)]],
#endif
#if USE_IBL
                              texturecube<float, access::sample> diffuseEnvTexture [[texture(textureIndexDiffuseEnvironment)]],
                              texturecube<float, access::sample> specularEnvTexture [[texture(textureIndexSpecularEnvironment)]],
                              texture2d<float, access::sample> brdfLUT [[texture(textureIndexBRDFLookup)]],
#endif
                              constant FragmentUniforms &uniforms [[buffer(0)]])
{
    constexpr sampler linearSampler(coord::normalized, min_filter::linear, mag_filter::linear, mip_filter::linear, address::repeat);
    
    float3x3 tbn;
    #if !HAS_TANGENTS
        float3 pos_dx = dfdx(in.worldPosition);
        float3 pos_dy = dfdy(in.worldPosition);
        float3 tex_dx = dfdx(float3(in.texCoords, 0.0));
        float3 tex_dy = dfdy(float3(in.texCoords, 0.0));
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
        n = normalTexture.sample(linearSampler, in.texCoords).rgb;
        n = normalize(tbn * ((2.0 * n - 1.0) * float3(uniforms.normalScale, uniforms.normalScale, 1.0)));
    #else
        n = tbn[2].xyz;
    #endif
    
    float3 v = normalize(uniforms.camera - in.worldPosition);
    float3 l = normalize(uniforms.lightDirection);
    float3 h = normalize(l + v);
    float3 reflection = -normalize(reflect(v, n));
    
    float NdotL = clamp(dot(n, l), 0.001, 1.0);
    float NdotV = abs(dot(n, v)) + 0.001;
    float NdotH = clamp(dot(n, h), 0.0, 1.0);
    float LdotH = clamp(dot(l, h), 0.0, 1.0);
    float VdotH = clamp(dot(v, h), 0.0, 1.0);
    
    float perceptualRoughness = uniforms.metallicRoughnessValues.y;
    float metallic = uniforms.metallicRoughnessValues.x;
    
    #if HAS_METALLIC_ROUGHNESS_MAP
        float4 mrSample = metallicRoughnessTexture.sample(linearSampler, in.texCoords);
        perceptualRoughness = mrSample.g * perceptualRoughness;
        metallic = mrSample.b * metallic;
    #endif
    
    perceptualRoughness = clamp(perceptualRoughness, minRoughness, 1.0);
    metallic = clamp(metallic, 0.0, 1.0);
    
    float4 baseColor;
    #if HAS_BASE_COLOR_MAP
    baseColor = baseColorTexture.sample(linearSampler, in.texCoords) * uniforms.baseColorFactor;
    #else
        baseColor = uniforms.baseColorFactor;
    #endif
    
    float3 f0 = float3(0.04);

    float3 diffuseColor = mix(baseColor.rgb * (1.0 - f0), float3(0.0, 0.0, 0.0), metallic);

    float3 specularColor = mix(f0, baseColor.rgb, metallic);
    
    float3 color = diffuseColor + specularColor;
    
    #if USE_PBR
        float reflectance = max(max(specularColor.r, specularColor.g), specularColor.b);
        
        float reflectance90 = clamp(reflectance * 25.0, 0.0, 1.0);
        float3 specularEnvironmentR0 = specularColor.rgb;
        float3 specularEnvironmentR90 = float3(1.0, 1.0, 1.0) * reflectance90;
    
        float alphaRoughness = perceptualRoughness * perceptualRoughness;
        
        LightingParameters pbrInputs = {
            .NdotL = NdotL,
            .NdotV = NdotV,
            .NdotH = NdotH,
            .LdotH = LdotH,
            .VdotH = VdotH,
            .perceptualRoughness = perceptualRoughness,
            .metalness = metallic,
            .baseColor = diffuseColor,
            .reflectance0 = specularEnvironmentR0,
            .reflectance90 = specularEnvironmentR90,
            .alphaRoughness = alphaRoughness
        };
        
        float3 F = fresnelSchlick2(pbrInputs);
        float G = geometricOcclusionSmithGGX(pbrInputs);
        float D = GGX(pbrInputs);
        
        float3 diffuseContrib = (1.0 - F) * lambertianDiffuse(pbrInputs);

        float3 specContrib = F * G * D / (4.0 * NdotL * NdotV);
        
        color = NdotL * uniforms.lightColor * (diffuseContrib + specContrib);
    #endif
    
    #if USE_IBL
    float mipCount(SPECULAR_ENV_MAP_LOD_LEVELS);
        float lod = (perceptualRoughness * mipCount);
        float3 brdf = brdfLUT.sample(linearSampler, float2(NdotV, 1.0 - perceptualRoughness)).rgb;
        float3 diffuseLight = diffuseEnvTexture.sample(linearSampler, n).rgb;
        
        float3 specularLight;
        if (mipCount > 1) {
            specularLight = specularEnvTexture.sample(linearSampler, reflection, level(lod)).rgb;
        } else {
            specularLight = specularEnvTexture.sample(linearSampler, reflection).rgb;
        }
    
        float3 IBLcolor = (diffuseLight * diffuseColor) + (specularLight * (specularColor * brdf.x + brdf.y));
    
        color += IBLcolor;
    #endif
    
    #if HAS_OCCLUSION_MAP
        float ao = occlusionTexture.sample(linearSampler, in.texCoords).r;
        color = mix(color, color * ao, uniforms.occlusionStrength);
    #endif
    
    #if HAS_EMISSIVE_MAP
        float3 emissive = emissiveTexture.sample(linearSampler, in.texCoords).rgb * uniforms.emissiveFactor;
        color += emissive;
    #else
        color += uniforms.emissiveFactor;
    #endif
    
    return float4(color, baseColor.a);
}

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

#import <GLTF/GLTF.h>

#import "GLTFMTLShaderBuilder.h"
#import "GLTFMTLUtilities.h"

@implementation GLTFMTLShaderBuilder

- (id<MTLRenderPipelineState>)renderPipelineStateForSubmesh:(GLTFSubmesh *)submesh
                                           colorPixelFormat:(MTLPixelFormat)colorPixelFormat
                                    depthStencilPixelFormat:(MTLPixelFormat)depthStencilPixelFormat
                                                     device:(id<MTLDevice>)device
{
    NSParameterAssert(submesh);
    NSParameterAssert(submesh.material);
    NSParameterAssert(submesh.vertexDescriptor);
    
    NSError *error = nil;
    NSString *shaderSource = [self shaderSourceForMaterial:submesh.material];
    
    shaderSource = [self rewriteSource:shaderSource forSubmesh:submesh];
    
    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"Error occurred while creating library for material : %@", error);
        return nil;
    }
    
    id <MTLFunction> vertexFunction = nil;
    id <MTLFunction> fragmentFunction = nil;

    for (NSString *functionName in [library functionNames]) {
        id<MTLFunction> function = [library newFunctionWithName:functionName];
        if ([function functionType] == MTLFunctionTypeVertex) {
            vertexFunction = function;
        } else if ([function functionType] == MTLFunctionTypeFragment) {
            fragmentFunction = function;
        }
    }
    
    if (!vertexFunction || !fragmentFunction) {
        NSLog(@"Failed to find a vertex and fragment function in library source");
        return nil;
    }
    
    MTLVertexDescriptor *vertexDescriptor = [self vertexDescriptorForSubmesh: submesh];

    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat;
    pipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat;
    pipelineDescriptor.stencilAttachmentPixelFormat = depthStencilPixelFormat;
    
    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (!pipeline) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }
    
    return pipeline;
}

- (NSString *)shaderSourceForMaterial:(GLTFMaterial *)material {
    NSError *error = nil;
    NSURL *shaderURL = [[NSBundle mainBundle] URLForResource:@"Shaders" withExtension:@"metal"];
    return [NSString stringWithContentsOfURL:shaderURL encoding:NSUTF8StringEncoding error:&error];
}

- (NSString *)rewriteSource:(NSString *)source forSubmesh:(GLTFSubmesh *)submesh {
    
    BOOL usePBR = YES;
    BOOL useIBL = YES;
    BOOL hasTexCoord0 = submesh.accessorsForAttributes[GLTFAttributeSemanticTexCoord0] != nil;
    BOOL hasNormals = submesh.accessorsForAttributes[GLTFAttributeSemanticNormal] != nil;
    BOOL hasTangents = submesh.accessorsForAttributes[GLTFAttributeSemanticTangent] != nil;
    BOOL hasBaseColorMap = submesh.material.baseColorTexture != nil;
    BOOL hasOcclusionMap = submesh.material.occlusionTexture != nil;
    BOOL hasEmissiveMap = submesh.material.emissiveTexture != nil;
    BOOL hasNormalMap = submesh.material.normalTexture != nil;
    BOOL hasMetallicRoughnessMap = submesh.material.metallicRoughnessTexture != nil;
    BOOL hasSkinningData = submesh.accessorsForAttributes[GLTFAttributeSemanticJoints0] != nil &&
                           submesh.accessorsForAttributes[GLTFAttributeSemanticWeights0] != nil;

    NSMutableString *shaderFeatures = [NSMutableString string];
    [shaderFeatures appendFormat:@"#define USE_PBR %d\n", usePBR];
    [shaderFeatures appendFormat:@"#define USE_IBL %d\n", useIBL];
    [shaderFeatures appendFormat:@"#define USE_VERTEX_SKINNING %d\n", hasSkinningData];
    [shaderFeatures appendFormat:@"#define HAS_TEXCOORDS %d\n", hasTexCoord0];
    [shaderFeatures appendFormat:@"#define HAS_NORMALS %d\n", hasNormals];
    [shaderFeatures appendFormat:@"#define HAS_TANGENTS %d\n", hasTangents];
    [shaderFeatures appendFormat:@"#define HAS_BASE_COLOR_MAP %d\n", hasBaseColorMap];
    [shaderFeatures appendFormat:@"#define HAS_NORMAL_MAP %d\n", hasNormalMap];
    [shaderFeatures appendFormat:@"#define HAS_METALLIC_ROUGHNESS_MAP %d\n", hasMetallicRoughnessMap];
    [shaderFeatures appendFormat:@"#define HAS_OCCLUSION_MAP %d\n", hasOcclusionMap];
    [shaderFeatures appendFormat:@"#define HAS_EMISSIVE_MAP %d\n", hasEmissiveMap];
    [shaderFeatures appendFormat:@"#define SPECULAR_ENV_MAP_LOD_LEVELS %d\n\n", 8]; // log2(512)
    
    NSString *preamble = @"struct VertexIn {\n";
    NSString *epilogue = @"\n};";
    
    NSMutableArray *attribs = [NSMutableArray array];
    int i = 0;
    for (GLTFVertexAttribute *attribute in submesh.vertexDescriptor.attributes) {
        if (attribute.componentType == 0) { continue; }
        if ([attribute.semantic isEqualToString:GLTFAttributeSemanticPosition]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ position [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        } else if ([attribute.semantic isEqualToString:GLTFAttributeSemanticNormal]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ normal [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        } else if ([attribute.semantic isEqualToString:GLTFAttributeSemanticTangent]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ tangent [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        } else if ([attribute.semantic isEqualToString:GLTFAttributeSemanticTexCoord0]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ texCoords [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        } else if ([attribute.semantic isEqualToString:GLTFAttributeSemanticJoints0]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ joints [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        }else if ([attribute.semantic isEqualToString:GLTFAttributeSemanticWeights0]) {
            [attribs addObject:[NSString stringWithFormat:@"    %@ weights [[attribute(%d)]];", GLTFMTLTypeNameForType(attribute.componentType, attribute.dimension, false), i]];
        }
        
        ++i;
    }
    
    NSString *decls = [NSString stringWithFormat:@"%@%@%@%@",
                       shaderFeatures, preamble, [attribs componentsJoinedByString:@"\n"], epilogue];
    
    NSRange startSigilRange = [source rangeOfString:@"/*%begin_replace_decls%*/"];
    NSRange endSigilRange = [source rangeOfString:@"/*%end_replace_decls%*/"];
    
    NSRange declRange = NSUnionRange(startSigilRange, endSigilRange);
    
    source = [source stringByReplacingCharactersInRange:declRange withString:decls];

    return source;
}

- (MTLVertexDescriptor *)vertexDescriptorForSubmesh:(GLTFSubmesh *)submesh {
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
    
    GLTFVertexDescriptor *descriptor = submesh.vertexDescriptor;
    
    for (NSInteger attributeIndex = 0; attributeIndex < GLTFVertexDescriptorMaxAttributeCount; ++attributeIndex) {
        GLTFVertexAttribute *attribute = descriptor.attributes[attributeIndex];
        GLTFBufferLayout *layout = descriptor.bufferLayouts[attributeIndex];
        
        if (attribute.componentType == 0) {
            continue;
        }
        
        MTLVertexFormat vertexFormat = GLTFMTLVertexFormatForComponentTypeAndDimension(attribute.componentType, attribute.dimension);
        
        vertexDescriptor.attributes[attributeIndex].offset = 0;
        vertexDescriptor.attributes[attributeIndex].format = vertexFormat;
        vertexDescriptor.attributes[attributeIndex].bufferIndex = attributeIndex;
        
        vertexDescriptor.layouts[attributeIndex].stride = layout.stride;
        vertexDescriptor.layouts[attributeIndex].stepRate = 1;
        vertexDescriptor.layouts[attributeIndex].stepFunction = MTLStepFunctionPerVertex;
    }

    return vertexDescriptor;
}

@end

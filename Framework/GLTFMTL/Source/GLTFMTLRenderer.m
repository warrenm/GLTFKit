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

#import "GLTFMTLRenderer.h"
#import "GLTFMTLShaderBuilder.h"
#import "GLTFMTLUtilities.h"
#import "GLTFMTLBufferAllocator.h"
#import "GLTFMTLLightingEnvironment.h"
#import "GLTFMTLTextureLoader.h"

@import ImageIO;
@import MetalKit;

typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 normalMatrix;
} VertexUniforms;

typedef struct {
    simd_float4 position;
    simd_float4 color;
    float intensity;
    float innerConeAngle;
    float outerConeAngle;
    float range;
    simd_float4 spotDirection;
} Light;

typedef struct {
    float normalScale;
    simd_float3 emissiveFactor;
    float occlusionStrength;
    simd_float2 metallicRoughnessValues;
    simd_float4 baseColorFactor;
    simd_float3 camera;
    float alphaCutoff;
    float envIntensity;
    Light ambientLight;
    Light lights[GLTFMTLMaximumLightCount];
    simd_float3x3 textureMatrices[GLTFMTLMaximumTextureCount];
} FragmentUniforms;

@interface GLTFMTLRenderItem: NSObject
@property (nonatomic, strong) NSString *label;
@property (nonatomic, strong) GLTFNode *node;
@property (nonatomic, strong) GLTFSubmesh *submesh;
@property (nonatomic, assign) VertexUniforms vertexUniforms;
@property (nonatomic, assign) FragmentUniforms fragmentUniforms;
@end

@implementation GLTFMTLRenderItem
@end

@interface GLTFMTLRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, strong) GLTFMTLTextureLoader *textureLoader;

@property (nonatomic, strong) dispatch_semaphore_t frameBoundarySemaphore;

@property (nonatomic, strong) NSMutableDictionary<NSUUID *, id<MTLRenderPipelineState>> *pipelineStatesForSubmeshes;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<MTLDepthStencilState>> *depthStencilStateMap;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, id<MTLTexture>> *texturesForImageIdentifiers;
@property (nonatomic, strong) NSMutableDictionary<GLTFTextureSampler *, id<MTLSamplerState>> *samplerStatesForSamplers;

@property (nonatomic, strong) NSMutableArray<GLTFMTLRenderItem *> *opaqueRenderItems;
@property (nonatomic, strong) NSMutableArray<GLTFMTLRenderItem *> *transparentRenderItems;
@property (nonatomic, strong) NSMutableArray<GLTFNode *> *currentLightNodes;
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *deferredReusableBuffers;
@property (nonatomic, strong) NSMutableArray<id<MTLBuffer>> *bufferPool;

@property (nonatomic, weak) GLTFKHRLight *ambientLight;

@end

@implementation GLTFMTLRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        
        _commandQueue = [_device newCommandQueue];
        
        _viewMatrix = matrix_identity_float4x4;
        _projectionMatrix = matrix_identity_float4x4;

        _drawableSize = CGSizeMake(1, 1);
        _colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        _depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        _sampleCount = 1;

        _textureLoader = [[GLTFMTLTextureLoader alloc] initWithDevice:_device];

        _frameBoundarySemaphore = dispatch_semaphore_create(GLTFMTLRendererMaxInflightFrames);
        
        _depthStencilStateMap = [NSMutableDictionary dictionary];
        _texturesForImageIdentifiers = [NSMutableDictionary dictionary];
        _pipelineStatesForSubmeshes = [NSMutableDictionary dictionary];
        _samplerStatesForSamplers = [NSMutableDictionary dictionary];
        
        _opaqueRenderItems = [NSMutableArray array];
        _transparentRenderItems = [NSMutableArray array];
        _currentLightNodes = [NSMutableArray array];
        _deferredReusableBuffers = [NSMutableArray array];
        _bufferPool = [NSMutableArray array];
    }
    
    return self;
}

- (void)dealloc {
    // This is gross. It's necessary because we may have pending frame completions that
    // we don't actually care about, but which are waiting, and would thus cause a crash
    // if we don't artificially spin the semaphore down to zero before it's released.
    while (dispatch_semaphore_signal(_frameBoundarySemaphore) != 0) { }
}

- (void)enqueueReusableBuffer:(id<MTLBuffer>)buffer {
    [self.bufferPool addObject:buffer];
}

- (id<MTLBuffer>)dequeueReusableBufferOfLength:(size_t)length {
    int indexToReuse = -1;
    for (int i = 0; i < self.bufferPool.count; ++i) {
        if (self.bufferPool[i].length >= length) {
            indexToReuse = i;
        }
    }
    
    if (indexToReuse >= 0) {
        id <MTLBuffer> buffer = self.bufferPool[indexToReuse];
        [self.bufferPool removeObjectAtIndex:indexToReuse];
        return buffer;
    } else {
        return [self.device newBufferWithLength:length options:MTLResourceStorageModeShared];
    }
}

- (id<MTLTexture>)textureForImage:(GLTFImage *)image preferSRGB:(BOOL)sRGB {
    NSParameterAssert(image != nil);
    
    id<MTLTexture> texture = self.texturesForImageIdentifiers[image.identifier];
    
    if (texture) {
        return texture;
    }
    
    NSDictionary *options = @{ GLTFMTLTextureLoaderOptionGenerateMipmaps : @YES,
                               GLTFMTLTextureLoaderOptionSRGB : @(sRGB)
                             };
    
    NSError *error = nil;
    if (image.imageData != nil) {
        texture = [self.textureLoader newTextureWithData:image.imageData options:options error:&error];
        texture.label = image.name;
    } else if (image.url != nil) {
        texture = [self.textureLoader newTextureWithContentsOfURL:image.url options:options error:&error];
        texture.label = image.name ?: image.url.lastPathComponent;
    } else if (image.bufferView != nil) {
        GLTFBufferView *bufferView = image.bufferView;
        NSData *data = [NSData dataWithBytesNoCopy:bufferView.buffer.contents + bufferView.offset length:bufferView.length freeWhenDone:NO];
        texture = [self.textureLoader newTextureWithData:data options:options error:&error];
        texture.label = image.name;
    }
    
    if (!texture) {
        NSLog(@"Error occurred while loading texture: %@", error);
    } else {
        self.texturesForImageIdentifiers[image.identifier] = texture;
    }
    
    return texture;
}

- (id<MTLSamplerState>)samplerStateForSampler:(GLTFTextureSampler *)sampler {
    NSParameterAssert(sampler != nil);
    
    id<MTLSamplerState> samplerState = self.samplerStatesForSamplers[sampler];
    if (samplerState == nil) {
        MTLSamplerDescriptor *descriptor = [MTLSamplerDescriptor new];
        descriptor.magFilter = GLTFMTLSamplerMinMagFilterForSamplingFilter(sampler.magFilter);
        descriptor.minFilter = GLTFMTLSamplerMinMagFilterForSamplingFilter(sampler.minFilter);
        descriptor.mipFilter = GLTFMTLSamplerMipFilterForSamplingFilter(sampler.minFilter);
        descriptor.sAddressMode = GLTFMTLSamplerAddressModeForSamplerAddressMode(sampler.sAddressMode);
        descriptor.tAddressMode = GLTFMTLSamplerAddressModeForSamplerAddressMode(sampler.tAddressMode);
        descriptor.normalizedCoordinates = YES;
        samplerState = [self.device newSamplerStateWithDescriptor:descriptor];
        self.samplerStatesForSamplers[sampler] = samplerState;
    }
    return samplerState;
}

- (id<MTLRenderPipelineState>)renderPipelineStateForSubmesh:(GLTFSubmesh *)submesh {
    id<MTLRenderPipelineState> pipeline = self.pipelineStatesForSubmeshes[submesh.identifier];
    
    if (pipeline == nil) {
        GLTFMTLShaderBuilder *shaderBuilder = [[GLTFMTLShaderBuilder alloc] init];
        pipeline = [shaderBuilder renderPipelineStateForSubmesh: submesh
                                            lightingEnvironment:self.lightingEnvironment
                                               colorPixelFormat:self.colorPixelFormat
                                        depthStencilPixelFormat:self.depthStencilPixelFormat
                                                    sampleCount:self.sampleCount
                                                         device:self.device];
        self.pipelineStatesForSubmeshes[submesh.identifier] = pipeline;
    }

    return pipeline;
}

- (id<MTLDepthStencilState>)depthStencilStateForDepthWriteEnabled:(BOOL)depthWriteEnabled
                                                 depthTestEnabled:(BOOL)depthTestEnabled
                                                  compareFunction:(MTLCompareFunction)compareFunction
{
    NSInteger depthWriteBit = depthWriteEnabled ? 1 : 0;
    NSInteger depthTestBit = depthTestEnabled ? 1 : 0;
    
    NSInteger hash = (compareFunction << 2) | (depthWriteBit << 1) | depthTestBit;
    
    id <MTLDepthStencilState> depthStencilState = self.depthStencilStateMap[@(hash)];
    if (depthStencilState) {
        return depthStencilState;
    }
    
    MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
    depthDescriptor.depthCompareFunction = depthTestEnabled ? compareFunction : MTLCompareFunctionAlways;
    depthDescriptor.depthWriteEnabled = depthWriteEnabled;
    depthStencilState = [self.device newDepthStencilStateWithDescriptor:depthDescriptor];
    
    self.depthStencilStateMap[@(hash)] = depthStencilState;
    
    return depthStencilState;
}

- (void)renderScene:(GLTFScene *)scene
      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
     commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
{
    if (scene == nil) {
        return;
    }
    
    long timedOut = dispatch_semaphore_wait(self.frameBoundarySemaphore, dispatch_time(0, 1 * NSEC_PER_SEC));
    if (timedOut) {
        NSLog(@"Failed to receive frame boundary signal before timing out; calling signalFrameCompletion manually. "
              "Remember to call signalFrameCompletion on GLTFMTLRenderer from the completion handler of the command buffer "
              "into which you encode the work for drawing assets");
        [self signalFrameCompletion];
    }
    
    self.ambientLight = scene.ambientLight;

    for (GLTFNode *rootNode in scene.nodes) {
        [self buildLightListRecursive:rootNode];
    }
    
    for (GLTFNode *rootNode in scene.nodes) {
        [self buildRenderListRecursive:rootNode modelMatrix:matrix_identity_float4x4];
    }
    
    NSMutableArray *renderList = [NSMutableArray arrayWithArray:self.opaqueRenderItems];
    [renderList addObjectsFromArray:self.transparentRenderItems];
    
    [self drawRenderList:renderList commandEncoder:renderEncoder];
    
    NSArray *copiedDeferredReusableBuffers = [self.deferredReusableBuffers copy];
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (id<MTLBuffer> buffer in copiedDeferredReusableBuffers) {
                [self enqueueReusableBuffer:buffer];
            }
        });
    }];
    
    [self.opaqueRenderItems removeAllObjects];
    [self.transparentRenderItems removeAllObjects];
    [self.currentLightNodes removeAllObjects];
    [self.deferredReusableBuffers removeAllObjects];
}

- (void)bindTexturesForMaterial:(GLTFMaterial *)material commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    if (material.baseColorTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.baseColorTexture.texture.image preferSRGB:YES];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.baseColorTexture.texture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexBaseColor];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexBaseColor];
    }
    
    if (material.normalTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.normalTexture.texture.image preferSRGB:NO];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.normalTexture.texture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexNormal];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexNormal];
    }
    
    if (material.metallicRoughnessTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.metallicRoughnessTexture.texture.image preferSRGB:NO];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.metallicRoughnessTexture.texture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexMetallicRoughness];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexMetallicRoughness];
    }
    
    if (material.emissiveTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.emissiveTexture.texture.image preferSRGB:YES];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.emissiveTexture.texture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexEmissive];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexEmissive];
    }
    
    if (material.occlusionTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.occlusionTexture.texture.image preferSRGB:NO];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.occlusionTexture.texture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexOcclusion];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexOcclusion];
    }
    
    if (self.lightingEnvironment) {
        [renderEncoder setFragmentTexture:self.lightingEnvironment.specularCube atIndex:GLTFTextureBindIndexSpecularEnvironment];
        [renderEncoder setFragmentTexture:self.lightingEnvironment.diffuseCube atIndex:GLTFTextureBindIndexDiffuseEnvironment];
        [renderEncoder setFragmentTexture:self.lightingEnvironment.brdfLUT atIndex:GLTFTextureBindIndexBRDFLookup];
    }
}

- (void)computeJointsForSubmesh:(GLTFSubmesh *)submesh inNode:(GLTFNode *)node buffer:(id<MTLBuffer>)jointBuffer {
    GLTFAccessor *jointsAccessor = submesh.accessorsForAttributes[GLTFAttributeSemanticJoints0];
    GLTFSkin *skin = node.skin;
    GLTFAccessor *inverseBindingAccessor = node.skin.inverseBindMatricesAccessor;
    
    if (jointsAccessor != nil && inverseBindingAccessor != nil) {
        NSInteger jointCount = skin.jointNodes.count;
        simd_float4x4 *jointMatrices = (simd_float4x4 *)jointBuffer.contents;
        simd_float4x4 *inverseBindMatrices = inverseBindingAccessor.bufferView.buffer.contents + inverseBindingAccessor.bufferView.offset + inverseBindingAccessor.offset;
        for (NSInteger i = 0; i < jointCount; ++i) {
            GLTFNode *joint = skin.jointNodes[i];
            simd_float4x4 inverseBindMatrix = inverseBindMatrices[i];
            jointMatrices[i] = matrix_multiply(matrix_invert(node.globalTransform), matrix_multiply(joint.globalTransform, inverseBindMatrix));
        }
    }
}

- (void)buildLightListRecursive:(GLTFNode *)node {
    if (node.light != nil) {
        [self.currentLightNodes addObject:node];
    }

    for (GLTFNode *childNode in node.children) {
        [self buildLightListRecursive:childNode];
    }
}

- (void)buildRenderListRecursive:(GLTFNode *)node
                     modelMatrix:(simd_float4x4)modelMatrix
{
    modelMatrix = matrix_multiply(modelMatrix, node.localTransform);

    GLTFMesh *mesh = node.mesh;
    if (mesh) {
        for (GLTFSubmesh *submesh in mesh.submeshes) {
            GLTFMaterial *material = submesh.material;
            
            simd_float3x3 viewAffine = simd_inverse(GLTFMatrixUpperLeft3x3(self.viewMatrix));
            simd_float3 cameraPos = self.viewMatrix.columns[3].xyz;
            simd_float3 cameraWorldPos = matrix_multiply(viewAffine, -cameraPos);
            
            VertexUniforms vertexUniforms;
            vertexUniforms.modelMatrix = modelMatrix;
            vertexUniforms.modelViewProjectionMatrix = matrix_multiply(matrix_multiply(self.projectionMatrix, self.viewMatrix), modelMatrix);
            vertexUniforms.normalMatrix = GLTFNormalMatrixFromModelMatrix(modelMatrix);
            
            FragmentUniforms fragmentUniforms = { 0 };
            fragmentUniforms.normalScale = material.normalTextureScale;
            fragmentUniforms.emissiveFactor = material.emissiveFactor;
            fragmentUniforms.occlusionStrength = material.occlusionStrength;
            fragmentUniforms.metallicRoughnessValues = (simd_float2){ material.metalnessFactor, material.roughnessFactor };
            fragmentUniforms.baseColorFactor = material.baseColorFactor;
            fragmentUniforms.camera = cameraWorldPos;
            fragmentUniforms.alphaCutoff = material.alphaCutoff;
            fragmentUniforms.envIntensity = self.lightingEnvironment.intensity;
            
            if (material.baseColorTexture != nil) {
                fragmentUniforms.textureMatrices[GLTFTextureBindIndexBaseColor] = GLTFTextureMatrixFromTransform(material.baseColorTexture.transform);
            }
            if (material.normalTexture != nil) {
                fragmentUniforms.textureMatrices[GLTFTextureBindIndexNormal] = GLTFTextureMatrixFromTransform(material.normalTexture.transform);
            }
            if (material.metallicRoughnessTexture != nil) {
                fragmentUniforms.textureMatrices[GLTFTextureBindIndexMetallicRoughness] = GLTFTextureMatrixFromTransform(material.metallicRoughnessTexture.transform);
            }
            if (material.occlusionTexture != nil) {
                fragmentUniforms.textureMatrices[GLTFTextureBindIndexOcclusion] = GLTFTextureMatrixFromTransform(material.occlusionTexture.transform);
            }
            if (material.emissiveTexture != nil) {
                fragmentUniforms.textureMatrices[GLTFTextureBindIndexEmissive] = GLTFTextureMatrixFromTransform(material.emissiveTexture.transform);
            }

            if (self.ambientLight != nil) {
                fragmentUniforms.ambientLight.color = self.ambientLight.color;
                fragmentUniforms.ambientLight.intensity = self.ambientLight.intensity;
            }

            // TODO: Make this more efficient. Iterating the light list for every submesh is pretty silly.
            for (int lightIndex = 0; lightIndex < self.currentLightNodes.count; ++lightIndex) {
                GLTFNode *lightNode = self.currentLightNodes[lightIndex];
                GLTFKHRLight *light = lightNode.light;
                if (light.type == GLTFKHRLightTypeDirectional) {
                    fragmentUniforms.lights[lightIndex].position = lightNode.globalTransform.columns[2];
                } else {
                    fragmentUniforms.lights[lightIndex].position = lightNode.globalTransform.columns[3];
                }
                fragmentUniforms.lights[lightIndex].color = light.color;
                fragmentUniforms.lights[lightIndex].intensity = light.intensity;
                fragmentUniforms.lights[lightIndex].range = light.range;
                if (light.type == GLTFKHRLightTypeSpot) {
                    fragmentUniforms.lights[lightIndex].innerConeAngle = light.innerConeAngle;
                    fragmentUniforms.lights[lightIndex].outerConeAngle = light.outerConeAngle;
                } else {
                    fragmentUniforms.lights[lightIndex].innerConeAngle = 0;
                    fragmentUniforms.lights[lightIndex].outerConeAngle = M_PI;
                }
                fragmentUniforms.lights[lightIndex].spotDirection = lightNode.globalTransform.columns[2];
            }
            
            GLTFMTLRenderItem *item = [GLTFMTLRenderItem new];
            item.label = [NSString stringWithFormat:@"%@ - %@", node.name ?: @"Unnamed node", submesh.name ?: @"Unnamed primitive"];
            item.node = node;
            item.submesh = submesh;
            item.vertexUniforms = vertexUniforms;
            item.fragmentUniforms = fragmentUniforms;
            
            if (submesh.material.alphaMode == GLTFAlphaModeBlend) {
                [self.transparentRenderItems addObject:item];
            } else {
                [self.opaqueRenderItems addObject:item];
            }
        }
    }
    
    for (GLTFNode *childNode in node.children) {
        [self buildRenderListRecursive:childNode modelMatrix:modelMatrix];
    }
}

- (void)drawRenderList:(NSArray<GLTFMTLRenderItem *> *)renderList commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    for (GLTFMTLRenderItem *item in renderList) {
        GLTFNode *node = item.node;
        GLTFSubmesh *submesh = item.submesh;
        GLTFMaterial *material = submesh.material;
        
        [renderEncoder pushDebugGroup:[NSString stringWithFormat:@"%@", item.label]];
        
        id<MTLRenderPipelineState> renderPipelineState = [self renderPipelineStateForSubmesh:submesh];
                
        [renderEncoder setRenderPipelineState:renderPipelineState];
        
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];

        NSDictionary *accessorsForAttributes = submesh.accessorsForAttributes;
                
        GLTFAccessor *indexAccessor = submesh.indexAccessor;
        BOOL useIndexBuffer = (indexAccessor != nil);
                
        // TODO: Check primitive type for unsupported types (tri fan, line loop), and modify draw calls as appropriate
        MTLPrimitiveType primitiveType = GLTFMTLPrimitiveTypeForPrimitiveType(submesh.primitiveType);
        
        [self bindTexturesForMaterial:material commandEncoder:renderEncoder];
        
        VertexUniforms vertexUniforms = item.vertexUniforms;
        [renderEncoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms) atIndex:GLTFVertexDescriptorMaxAttributeCount + 0];
        
        if (node.skin != nil && node.skin.jointNodes != nil && node.skin.jointNodes.count > 0) {
            id<MTLBuffer> jointBuffer = [self dequeueReusableBufferOfLength: node.skin.jointNodes.count * sizeof(simd_float4x4)];
            [self computeJointsForSubmesh:submesh inNode:node buffer:jointBuffer];
            [renderEncoder setVertexBuffer:jointBuffer offset:0 atIndex:GLTFVertexDescriptorMaxAttributeCount + 1];
            [self.deferredReusableBuffers addObject:jointBuffer];
        }
        
        FragmentUniforms fragmentUniforms = item.fragmentUniforms;
        [renderEncoder setFragmentBytes:&fragmentUniforms length: sizeof(fragmentUniforms) atIndex: 0];
                
        GLTFVertexDescriptor *vertexDescriptor = submesh.vertexDescriptor;
        for (int i = 0; i < GLTFVertexDescriptorMaxAttributeCount; ++i) {
            NSString *semantic = vertexDescriptor.attributes[i].semantic;
            if (semantic == nil) { continue; }
            GLTFAccessor *accessor = submesh.accessorsForAttributes[semantic];
            
            [renderEncoder setVertexBuffer:((GLTFMTLBuffer *)accessor.bufferView.buffer).buffer
                                    offset:accessor.offset + accessor.bufferView.offset
                                   atIndex:i];
        }
        
        if (material.alphaMode == GLTFAlphaModeBlend){
            id<MTLDepthStencilState> depthStencilState = [self depthStencilStateForDepthWriteEnabled:YES
                                                                                    depthTestEnabled:YES
                                                                                     compareFunction:MTLCompareFunctionLess];
            [renderEncoder setDepthStencilState:depthStencilState];
        } else {
            id<MTLDepthStencilState> depthStencilState = [self depthStencilStateForDepthWriteEnabled:YES
                                                                                    depthTestEnabled:YES
                                                                                     compareFunction:MTLCompareFunctionLess];
            [renderEncoder setDepthStencilState:depthStencilState];
        }
        
        if (material.isDoubleSided) {
            [renderEncoder setCullMode:MTLCullModeNone];
        } else {
            [renderEncoder setCullMode:MTLCullModeBack];
        }
        
        if (useIndexBuffer) {
            GLTFMTLBuffer *indexBuffer = (GLTFMTLBuffer *)indexAccessor.bufferView.buffer;
            
            MTLIndexType indexType = (indexAccessor.componentType == GLTFDataTypeUShort) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
            
            [renderEncoder drawIndexedPrimitives:primitiveType
                                      indexCount:indexAccessor.count
                                       indexType:indexType
                                     indexBuffer:[indexBuffer buffer]
                               indexBufferOffset:indexAccessor.offset + indexAccessor.bufferView.offset];
        } else {
            GLTFAccessor *positionAccessor = accessorsForAttributes[GLTFAttributeSemanticPosition];
            [renderEncoder drawPrimitives:primitiveType vertexStart:0 vertexCount:positionAccessor.count];
        }
        
        [renderEncoder popDebugGroup];
    }
}

- (void)signalFrameCompletion {
    dispatch_semaphore_signal(self.frameBoundarySemaphore);
}

@end

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

#import "GLTFMTLRenderer.h"
#import "GLTFMTLShaderBuilder.h"
#import "GLTFMTLUtilities.h"
#import "GLTFMTLBufferAllocator.h"
#import "GLTFMTLLightingEnvironment.h"

@import ImageIO;
@import MetalKit;

struct VertexUniforms {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
};

struct FragmentUniforms {
    vector_float3 lightDirection;
    vector_float3 lightColor;
    float normalScale;
    vector_float3 emissiveFactor;
    float occlusionStrength;
    vector_float2 metallicRoughnessValues;
    vector_float4 baseColorFactor;
    vector_float3 camera;
};

@interface GLTFMTLRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (nonatomic, strong) MTKTextureLoader *textureLoader;

@property (nonatomic, strong) dispatch_semaphore_t frameBoundarySemaphore;

@property (nonatomic, copy) NSArray *dynamicConstantsBuffers;
@property (nonatomic, assign) NSInteger constantsBufferIndex;
@property (nonatomic, assign) NSInteger dynamicConstantsOffset;

@property (nonatomic, strong) NSMutableDictionary<NSUUID *, id<MTLRenderPipelineState>> *pipelineStatesForSubmeshes;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<MTLDepthStencilState>> *depthStencilStateMap;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, id<MTLTexture>> *texturesForImageIdentifiers;
@property (nonatomic, strong) NSMutableDictionary<GLTFTextureSampler *, id<MTLSamplerState>> *samplerStatesForSamplers;

@end

@implementation GLTFMTLRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        
        _commandQueue = [_device newCommandQueue];
        
        _viewMatrix = matrix_identity_float4x4;

        _drawableSize = CGSizeMake(1, 1);
        _colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        _depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

        _textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];
        
        NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:GLTFMTLRendererMaxInflightFrames];
        for (int i = 0; i < GLTFMTLRendererMaxInflightFrames; ++i) {
            id buffer = [_device newBufferWithLength:GLTFMTLRendererDynamicConstantsBufferSize
                                             options:MTLResourceStorageModeShared];
            [buffers addObject:buffer];
        }
        
        _dynamicConstantsBuffers = [buffers copy];
        _constantsBufferIndex = 0;
        _frameBoundarySemaphore = dispatch_semaphore_create(GLTFMTLRendererMaxInflightFrames);
        
        _depthStencilStateMap = [NSMutableDictionary dictionary];
        _texturesForImageIdentifiers = [NSMutableDictionary dictionary];
        _pipelineStatesForSubmeshes = [NSMutableDictionary dictionary];
        _samplerStatesForSamplers = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (id<MTLTexture>)textureForImage:(GLTFImage *)image {
    NSParameterAssert(image != nil);
    
    id<MTLTexture> texture = self.texturesForImageIdentifiers[image.identifier];
    
    if (texture) {
        return texture;
    }
    
    id options = @{ MTKTextureLoaderOptionOrigin : MTKTextureLoaderOriginTopLeft,
                    MTKTextureLoaderOptionSRGB : @(NO) };
    
    NSError *error = nil;
    if (image.cgImage) {
        texture = [self.textureLoader newTextureWithCGImage:image.cgImage options:options error:&error];
    } else if (image.url) {
        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)image.url, nil);
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);
        
        CGColorSpaceRef sourceColorSpace = CGImageGetColorSpace(cgImage);
        
        CGColorSpaceModel sourceColorModel = CGColorSpaceGetModel(sourceColorSpace);
        
        if (sourceColorModel != kCGColorSpaceModelRGB) {
            // TODO: Remove this once the indexed image decode bug in MetalKit is fixed.
            size_t width = CGImageGetWidth(cgImage);
            size_t height = CGImageGetHeight(cgImage);
            size_t bpc = 8;
            size_t Bpr = width * 4;
            CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(nil, width, height, bpc, Bpr, colorSpace, kCGImageAlphaPremultipliedLast);
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
            CGImageRelease(cgImage);
            cgImage = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
        }
        
        texture = [self.textureLoader newTextureWithCGImage:cgImage options:options error:&error];
        
        CGImageRelease(cgImage);
        if (imageSource != NULL) {
            CFRelease(imageSource);
        }
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
        modelMatrix:(matrix_float4x4)modelMatrix
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
    
    for (GLTFNode *rootNode in scene.nodes) {
        [self renderNodeRecursive:rootNode
                      modelMatrix:modelMatrix
             renderCommandEncoder:renderEncoder];
    }
}

- (void)bindTexturesForMaterial:(GLTFMaterial *)material commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    if (material.baseColorTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.baseColorTexture.image];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.baseColorTexture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexBaseColor];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexBaseColor];
    }
    
    if (material.normalTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.normalTexture.image];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.normalTexture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexNormal];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexNormal];
    }
    
    if (material.metallicRoughnessTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.metallicRoughnessTexture.image];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.metallicRoughnessTexture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexMetallicRoughness];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexMetallicRoughness];
    }
    
    if (material.emissiveTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.emissiveTexture.image];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.emissiveTexture.sampler];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexEmissive];
        [renderEncoder setFragmentSamplerState:sampler atIndex:GLTFTextureBindIndexEmissive];
    }
    
    if (material.occlusionTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.occlusionTexture.image];
        id<MTLSamplerState> sampler = [self samplerStateForSampler:material.occlusionTexture.sampler];
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
        matrix_float4x4 *jointMatrices = (matrix_float4x4 *)jointBuffer.contents;
        for (NSInteger i = 0; i < jointCount; ++i) {
            GLTFNode *joint = skin.jointNodes[i];
            matrix_float4x4 *inverseBindMatrices = (matrix_float4x4 *)(inverseBindingAccessor.bufferView.buffer.contents + inverseBindingAccessor.bufferView.offset + inverseBindingAccessor.offset);
            matrix_float4x4 inverseBindMatrix = inverseBindMatrices[i];
            jointMatrices[i] = matrix_multiply(matrix_invert(node.globalTransform), matrix_multiply(joint.globalTransform, inverseBindMatrix));
        }
    }
}

- (void)renderNodeRecursive:(GLTFNode *)node
                modelMatrix:(matrix_float4x4)modelMatrix
       renderCommandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
{
    modelMatrix = matrix_multiply(modelMatrix, node.localTransform);
    
    GLTFMesh *mesh = node.mesh;
    if (mesh)
    {
        [renderEncoder pushDebugGroup:mesh.name ?: @"(unnamed mesh)"];
        
        for (GLTFSubmesh *submesh in mesh.submeshes) {
            GLTFMaterial *material = submesh.material;
            
            id<MTLRenderPipelineState> renderPipelineState = [self renderPipelineStateForSubmesh: submesh];
            
            [renderEncoder setRenderPipelineState:renderPipelineState];

            NSDictionary *accessorsForAttributes = submesh.accessorsForAttributes;

            GLTFAccessor *indexAccessor = submesh.indexAccessor;
            BOOL useIndexBuffer = (indexAccessor != nil);
            
            // TODO: Check primitive type for unsupported types (tri fan, line loop), and modify draw calls as appropriate
            MTLPrimitiveType primitiveType = GLTFMTLPrimitiveTypeForPrimitiveType(submesh.primitiveType);
            
            [self bindTexturesForMaterial:material commandEncoder: renderEncoder];
            
            matrix_float4x4 projectionMatrix =  GLTFPerspectiveProjectionMatrixAspectFovRH(M_PI / 4, self.drawableSize.width / self.drawableSize.height, 0.1, 1000);
            
            struct VertexUniforms vertexUniforms;
            
            matrix_float3x3 viewAffine = matrix_invert(GLTFMatrixUpperLeft3x3(self.viewMatrix));
            vector_float3 cameraPos = (vector_float3){ self.viewMatrix.columns[3].x, self.viewMatrix.columns[3].y, self.viewMatrix.columns[3].z };
            vector_float3 cameraWorldPos = matrix_multiply(viewAffine, -cameraPos);
            
            vertexUniforms.modelMatrix = modelMatrix;
            vertexUniforms.modelViewProjectionMatrix = matrix_multiply(matrix_multiply(projectionMatrix, self.viewMatrix), modelMatrix);
            
            struct FragmentUniforms fragmentUniforms;
            fragmentUniforms.lightDirection = (vector_float3){ 0, 1, 0 };
            fragmentUniforms.lightColor = (vector_float3) { 1, 1, 1 };
            fragmentUniforms.normalScale = material.normalTextureScale;
            fragmentUniforms.emissiveFactor = material.emissiveFactor;
            fragmentUniforms.occlusionStrength = 1;
            fragmentUniforms.metallicRoughnessValues = (vector_float2){ material.metalnessFactor, material.roughnessFactor };
            fragmentUniforms.baseColorFactor = material.baseColorFactor;
            fragmentUniforms.camera = cameraWorldPos;
            
            [renderEncoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms) atIndex:GLTFVertexDescriptorMaxAttributeCount + 0];
            
            id<MTLBuffer> jointBuffer = self.dynamicConstantsBuffers[self.constantsBufferIndex];
            [self computeJointsForSubmesh:submesh inNode:node buffer:jointBuffer];
            [renderEncoder setVertexBuffer:jointBuffer offset:0 atIndex:GLTFVertexDescriptorMaxAttributeCount + 1];
            
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
            
            [renderEncoder setDepthStencilState:[self depthStencilStateForDepthWriteEnabled:YES depthTestEnabled:YES compareFunction:MTLCompareFunctionLess]];
            
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
        }
        
        [renderEncoder popDebugGroup];
    }
    
    for (GLTFNode *childNode in node.children) {
        [self renderNodeRecursive:childNode
                      modelMatrix:modelMatrix
             renderCommandEncoder:renderEncoder];
    }
}

- (void)signalFrameCompletion {
    self.constantsBufferIndex = (self.constantsBufferIndex + 1) % GLTFMTLRendererMaxInflightFrames;
    self.dynamicConstantsOffset = 0;
    dispatch_semaphore_signal(self.frameBoundarySemaphore);
}

@end

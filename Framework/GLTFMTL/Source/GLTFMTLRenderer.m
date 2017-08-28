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

@import ImageIO;
@import MetalKit;

struct VertexUniforms {
    matrix_float4x4 modelViewProjectionMatrix;
    matrix_float4x4 modelMatrix;
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

@property (nonatomic, retain) id<MTLTexture> diffuseCube;
@property (nonatomic, retain) id<MTLTexture> specularCube;
@property (nonatomic, retain) id<MTLTexture> brdfLUT;

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
        
        [self loadIBLTextures];
    }
    
    return self;
}

- (void)loadIBLTextures {
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    
    NSURL *brdfLUTURL = [[NSBundle mainBundle] URLForResource:@"brdfLUT" withExtension:@"png"];
    id options = @{ MTKTextureLoaderOptionOrigin : MTKTextureLoaderOriginTopLeft,
                    MTKTextureLoaderOptionSRGB : @(NO)
                  };
    NSError *error = nil;
    _brdfLUT = [_textureLoader newTextureWithContentsOfURL:brdfLUTURL options:options error:&error];
    
    NSURL *diffuseURL = [[NSBundle mainBundle] URLForResource:@"output_iem" withExtension:@"png"];
    id<MTLTexture> diffuseStrip = [_textureLoader newTextureWithContentsOfURL:diffuseURL options:options error:&error];
    
    int diffuseCubeSize = (int)[diffuseStrip width];
    
    MTLTextureDescriptor *cubeDescriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm size:diffuseCubeSize mipmapped:NO];
    
    _diffuseCube = [_device newTextureWithDescriptor:cubeDescriptor];
    
    for (int i = 0; i < 6; ++i) {
        [blitEncoder copyFromTexture:diffuseStrip
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, i * diffuseCubeSize, 0)
                          sourceSize:MTLSizeMake(diffuseCubeSize, diffuseCubeSize, 1)
                           toTexture:_diffuseCube
                    destinationSlice:i
                    destinationLevel:0
                   destinationOrigin:MTLOriginMake(0, 0, 0)];
    }
    
    int specularMipLevel = 0;
    int specularCubeSize = 0;
    do {
        NSString *specularCubeName = [NSString stringWithFormat:@"output_pmrem_%d", specularMipLevel];
        
        NSURL *specularURL = [[NSBundle mainBundle] URLForResource:specularCubeName withExtension:@"png"];
        id<MTLTexture> specularStrip = [_textureLoader newTextureWithContentsOfURL:specularURL options:options error:&error];
        
        if (specularStrip == nil) {
            break;
        }
        
        if (specularCubeSize == 0) {
            specularCubeSize = (int)[specularStrip width];
            MTLTextureDescriptor *cubeDescriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm size:specularCubeSize mipmapped:YES];
            _specularCube = [_device newTextureWithDescriptor:cubeDescriptor];
        }
        
        for (int i = 0; i < 6; ++i) {
            [blitEncoder copyFromTexture:specularStrip
                             sourceSlice:0
                             sourceLevel:0
                            sourceOrigin:MTLOriginMake(0, i * specularCubeSize, 0)
                              sourceSize:MTLSizeMake(specularCubeSize, specularCubeSize, 1)
                               toTexture:_specularCube
                        destinationSlice:i
                        destinationLevel:specularMipLevel
                       destinationOrigin:MTLOriginMake(0, 0, 0)];
        }
        
        specularCubeSize = specularCubeSize / 2;
        ++specularMipLevel;
    } while (specularCubeSize >= 1);
    
    [blitEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
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
        
        // TODO: Remove this once the image decode bugs in MetalKit are fixed.
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        size_t bpc = 8;
        size_t Bpr = width * 4;
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(nil, width, height, bpc, Bpr, colorSpace, kCGImageAlphaPremultipliedLast);
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGImageRef redrawnImage = CGBitmapContextCreateImage(context);
        
        texture = [self.textureLoader newTextureWithCGImage:redrawnImage options:options error:&error];
        
        CGImageRelease(redrawnImage);
        CGContextRelease(context);
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

- (id<MTLRenderPipelineState>)renderPipelineStateForSubmesh:(GLTFSubmesh *)submesh {
    id<MTLRenderPipelineState> pipeline = self.pipelineStatesForSubmeshes[submesh.identifier];
    
    if (pipeline == nil) {
        GLTFMTLShaderBuilder *shaderBuilder = [[GLTFMTLShaderBuilder alloc] init];
        pipeline = [shaderBuilder renderPipelineStateForSubmesh: submesh
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

- (void)renderAsset:(GLTFAsset *)asset
        modelMatrix:(matrix_float4x4)modelMatrix
      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
     commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
{
    long timedOut = dispatch_semaphore_wait(self.frameBoundarySemaphore, dispatch_time(0, 1 * NSEC_PER_SEC));
    if (timedOut) {
        NSLog(@"Failed to receive frame boundary signal before timing out; calling signalFrameCompletion manually. "
              "Remember to call signalFrameCompletion on GLTFMTLRenderer from the completion handler of the command buffer "
              "into which you encode the work for drawing assets");
        [self signalFrameCompletion];
    }
    
    GLTFScene *defaultScene = asset.defaultScene;
    
    for (GLTFNode *rootNode in defaultScene.nodes) {
        [self renderNodeRecursive:rootNode
                      modelMatrix:modelMatrix
             renderCommandEncoder:renderEncoder];
    }
}

- (void)bindTexturesForMaterial:(GLTFMaterial *)material commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    if (material.baseColorTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.baseColorTexture.image];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexBaseColor];
    }
    
    if (material.normalTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.normalTexture.image];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexNormal];
    }
    
    if (material.metallicRoughnessTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.metallicRoughnessTexture.image];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexMetallicRoughness];
    }
    
    if (material.emissiveTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.emissiveTexture.image];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexEmissive];
    }
    
    if (material.occlusionTexture != nil) {
        id<MTLTexture> texture = [self textureForImage:material.occlusionTexture.image];
        [renderEncoder setFragmentTexture:texture atIndex:GLTFTextureBindIndexOcclusion];
    }
    
    if (self.specularCube) {
        [renderEncoder setFragmentTexture:self.specularCube atIndex:GLTFTextureBindIndexSpecularEnvironment];
    }
    
    if (self.diffuseCube) {
        [renderEncoder setFragmentTexture:self.diffuseCube atIndex:GLTFTextureBindIndexDiffuseEnvironment];
    }
    
    if (self.brdfLUT) {
        [renderEncoder setFragmentTexture:self.brdfLUT atIndex:GLTFTextureBindIndexBRDFLookup];
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
            fragmentUniforms.lightDirection = (vector_float3){ 0, 0, -1 };
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

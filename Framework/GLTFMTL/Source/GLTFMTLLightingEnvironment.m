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

#import "GLTFMTLLightingEnvironment.h"
#import "GLTFMTLTextureLoader.h"

@import MetalKit;

@interface GLTFMTLLightingEnvironment ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLLibrary> library;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLComputePipelineState> brdfComputePipeline;
@property (nonatomic, strong) id<MTLComputePipelineState> equirectToCubePipeline;
@property (nonatomic, strong) id<MTLComputePipelineState> irradiancePipeline;
@property (nonatomic, strong) id<MTLComputePipelineState> specularPipeline;
@property (nonatomic, strong) GLTFMTLTextureLoader *textureLoader;
@end

@implementation GLTFMTLLightingEnvironment

@synthesize specularMipLevelCount=_specularMipLevelCount;

- (instancetype)initWithContentsOfURL:(NSURL *)environmentURL device:(id<MTLDevice>)device error:(NSError **)error
{
    NSParameterAssert(device != nil);
    
    if ((self = [super init])) {
        _intensity = 1;
        _device = device;
        _commandQueue = [device newCommandQueue];
        _library = [device newDefaultLibrary];
        _textureLoader = [[GLTFMTLTextureLoader alloc] initWithDevice:device];
        
        NSDictionary *options = @{ };
        id<MTLTexture> equirectTexture = [_textureLoader newTextureWithContentsOfURL:environmentURL options:options error:error];
        
        if (![self _buildPipelineStatesWithError:error]) {
            return nil;
        }

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        [self _generateEnvironmentCubeMapWithSize:512 fromEquirectTexture:equirectTexture commandBuffer:commandBuffer];
        [commandBuffer commit];

        commandBuffer = [_commandQueue commandBuffer];
        [self _generateIrradianceCubeMapWithSize:64 fromRadianceCubeMap:_environmentCube commandBuffer:commandBuffer];
        [commandBuffer commit];

        commandBuffer = [_commandQueue commandBuffer];
        [self _generateSpecularCubeMapWithSize:256 roughnessLevels:9 fromRadianceCubeMap:_environmentCube commandBuffer:commandBuffer];
        [commandBuffer commit];

        commandBuffer = [_commandQueue commandBuffer];
        [self _generateBRDFLookupWithSize:128 commandBuffer:commandBuffer];
        [commandBuffer commit];
    }
    
    return self;
}

- (BOOL)_buildPipelineStatesWithError:(NSError **)error {
    id<MTLFunction> brdfFunction = [_library newFunctionWithName:@"integrate_brdf"];
    _brdfComputePipeline = [_device newComputePipelineStateWithFunction:brdfFunction error:error];
    if (_brdfComputePipeline == nil) {
        return NO;
    }
    
    id<MTLFunction> equirectFunction = [_library newFunctionWithName:@"equirect_to_cube"];
    _equirectToCubePipeline = [_device newComputePipelineStateWithFunction:equirectFunction error:error];
    if (_equirectToCubePipeline == nil) {
        return NO;
    }

    id<MTLFunction> irradianceFunction = [_library newFunctionWithName:@"compute_irradiance"];
    _irradiancePipeline = [_device newComputePipelineStateWithFunction:irradianceFunction error:error];
    if (_irradiancePipeline == nil) {
        return NO;
    }
    
    id<MTLFunction> specularFunction = [_library newFunctionWithName:@"compute_prefiltered_specular"];
    _specularPipeline = [_device newComputePipelineStateWithFunction:specularFunction error:error];
    if (_specularPipeline == nil) {
        return NO;
    }

    return YES;
}

- (void)_generateEnvironmentCubeMapWithSize:(int)size
                        fromEquirectTexture:(id<MTLTexture>)equirectTexture
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                              size:size
                                                                                         mipmapped:YES];
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id <MTLTexture> cubeTexture = [_device newTextureWithDescriptor:textureDesc];
    
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    [commandEncoder setComputePipelineState:_equirectToCubePipeline];
    [commandEncoder setTexture:equirectTexture atIndex:0];
    [commandEncoder setTexture:cubeTexture atIndex:1];
    MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(size / threadsPerThreadgroup.width, size / threadsPerThreadgroup.height, 6);
    [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
    [commandEncoder endEncoding];
    
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder generateMipmapsForTexture:cubeTexture];
    [blitEncoder endEncoding];

    _environmentCube = cubeTexture;
}

- (void)_generateIrradianceCubeMapWithSize:(int)size
                       fromRadianceCubeMap:(id<MTLTexture>)environmentCube
                             commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                              size:size
                                                                                         mipmapped:NO];
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id <MTLTexture> diffuseCube = [_device newTextureWithDescriptor:textureDesc];
    
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    [commandEncoder setComputePipelineState:_irradiancePipeline];
    [commandEncoder setTexture:environmentCube atIndex:0];
    [commandEncoder setTexture:diffuseCube atIndex:1];
    MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(size / threadsPerThreadgroup.width, size / threadsPerThreadgroup.height, 6);
    [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
    [commandEncoder endEncoding];
    
    _diffuseCube = diffuseCube;
}

- (void)_generateSpecularCubeMapWithSize:(int)size
                         roughnessLevels:(int)roughnessLevels
                     fromRadianceCubeMap:(id<MTLTexture>)environmentCube
                           commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                              size:size
                                                                                         mipmapped:YES];
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id <MTLTexture> specularCube = [_device newTextureWithDescriptor:textureDesc];

    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    [commandEncoder setComputePipelineState:_specularPipeline];
    [commandEncoder setTexture:environmentCube atIndex:0];
    
    int mipSize = size;
    for (int lod = 0; lod < roughnessLevels; ++lod) {
        float roughness = lod / (float)(roughnessLevels - 1);
        [commandEncoder setBytes:&roughness length:sizeof(float) atIndex:0];
        id<MTLTexture> specularCubeView = [specularCube newTextureViewWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                          textureType:MTLTextureTypeCube
                                                                               levels:NSMakeRange(lod, 1)
                                                                               slices:NSMakeRange(0, 6)];
        [commandEncoder setTexture:specularCubeView atIndex:1];
        MTLSize threadsPerThreadgroup = MTLSizeMake(MIN(mipSize, 16), MIN(mipSize, 16), 1);
        MTLSize threadgroups = MTLSizeMake(size / threadsPerThreadgroup.width, size / threadsPerThreadgroup.height, 6);
        [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        mipSize = mipSize / 2;
    }
    
    [commandEncoder endEncoding];

    _specularCube = specularCube;
    _specularMipLevelCount = roughnessLevels;
}

- (void)_generateBRDFLookupWithSize:(int)size commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRG16Float
                                                                                           width:size
                                                                                          height:size
                                                                                       mipmapped:NO];
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id <MTLTexture> lookupTexture = [_device newTextureWithDescriptor:textureDesc];
    
    id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
    [commandEncoder setComputePipelineState:_brdfComputePipeline];
    [commandEncoder setTexture:lookupTexture atIndex:0];
    MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
    MTLSize threadgroups = MTLSizeMake(size / threadsPerThreadgroup.width, size / threadsPerThreadgroup.height, 1);
    [commandEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
    [commandEncoder endEncoding];
    
    _brdfLUT = lookupTexture;
}

- (int)specularMipLevelCount {
    return _specularMipLevelCount;
}

@end

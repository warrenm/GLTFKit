#import "GLTFMTLLightingEnvironment.h"
#import <MetalKit/MetalKit.h>

@implementation GLTFMTLLightingEnvironment

- (instancetype)initWithDiffuseCubeURL:(NSURL *)diffuseCubeURL
                      specularCubeURLs:(NSArray<NSURL *> *)specularCubeURLs
                            brdfLUTURL:(NSURL *)brdfLUTURL
                                device:(id<MTLDevice>)device
                                 error:(NSError **)error
{
    if ((self = [super init])) {
        NSError *internalError = nil;
        
        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        
        MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:device];
        
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        
        id options = @{ MTKTextureLoaderOptionOrigin : MTKTextureLoaderOriginTopLeft,
                        MTKTextureLoaderOptionSRGB : @(NO)
                      };
        _brdfLUT = [textureLoader newTextureWithContentsOfURL:brdfLUTURL options:options error:&internalError];
        if (_brdfLUT == nil) {
            if (error != nil) {
                *error = internalError;
            }
            return nil;
        }
        
        id<MTLTexture> diffuseStrip = [textureLoader newTextureWithContentsOfURL:diffuseCubeURL options:options error:&internalError];
        if (diffuseStrip == nil) {
            if (error != nil) {
                *error = internalError;
            }
            return nil;
        }
        
        int diffuseCubeSize = (int)[diffuseStrip width];
        
        MTLTextureDescriptor *cubeDescriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                     size:diffuseCubeSize
                                                                                                mipmapped:NO];
        
        _diffuseCube = [device newTextureWithDescriptor:cubeDescriptor];
        
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
        for (int i = 0; i < specularCubeURLs.count; ++i) {
            id<MTLTexture> specularStrip = [textureLoader newTextureWithContentsOfURL:specularCubeURLs[i]
                                                                              options:options
                                                                                error:&internalError];
            
            if (specularStrip == nil) {
                if (error != nil) {
                    *error = internalError;
                }
                return nil;
            }
            
            if (specularCubeSize == 0) {
                specularCubeSize = (int)[specularStrip width];
                MTLTextureDescriptor *cubeDescriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                             size:specularCubeSize
                                                                                                        mipmapped:YES];
                cubeDescriptor.mipmapLevelCount = [specularCubeURLs count];
                _specularCube = [device newTextureWithDescriptor:cubeDescriptor];
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
        }
        
        [blitEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }
    
    return self;
}

- (NSUInteger)specularLODLevelCount {
    return self.specularCube.mipmapLevelCount;
}

@end

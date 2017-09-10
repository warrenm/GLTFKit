#import <Foundation/Foundation.h>
#import <GLTF/GLTF.h>
#import <Metal/Metal.h>

@interface GLTFMTLLightingEnvironment : NSObject

@property (nonatomic, retain) id<MTLTexture> diffuseCube;
@property (nonatomic, retain) id<MTLTexture> specularCube;
@property (nonatomic, retain) id<MTLTexture> brdfLUT;
@property (nonatomic, readonly, assign) NSUInteger specularLODLevelCount;

- (instancetype)initWithDiffuseCubeURL:(NSURL *)diffuseCubeURL
                      specularCubeURLs:(NSArray<NSURL *> *)specularCubeURLs
                            brdfLUTURL:(NSURL *)brdfLUTURL
                                device:(id<MTLDevice>)device
                                 error:(NSError **)error;

@end

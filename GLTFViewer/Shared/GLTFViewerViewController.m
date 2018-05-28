
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

#import "GLTFViewerViewController.h"
#import "GLTFViewerOrbitCamera.h"
#import "GLTFViewerFirstPersonCamera.h"
#import "GLTFViewerNodeCamera.h"
#import "HIToolboxEvents.h"

@interface GLTFViewerViewController ()
@property (nonatomic, weak) MTKView *metalView;

#if TARGET_OS_OSX
@property (nonatomic, strong) NSTrackingArea *trackingArea;
#endif

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> library;

@property (nonatomic, strong) id<MTLRenderPipelineState> skyboxPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> tonemapPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> bloomThresholdPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> blurHorizontalPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> blurVerticalPipelineState;
@property (nonatomic, strong) id<MTLRenderPipelineState> additiveBlendPipelineState;

@property (nonatomic, assign) int sampleCount;
@property (nonatomic, assign) MTLPixelFormat colorPixelFormat;
@property (nonatomic, assign) MTLPixelFormat depthStencilPixelFormat;
@property (nonatomic, strong) id<MTLTexture> multisampleColorTexture;
@property (nonatomic, strong) id<MTLTexture> colorTexture;
@property (nonatomic, strong) id<MTLTexture> depthStencilTexture;

@property (nonatomic, strong) id<MTLTexture> bloomTextureA;
@property (nonatomic, strong) id<MTLTexture> bloomTextureB;

@property (nonatomic, strong) GLTFMTLRenderer *renderer;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;

@property (nonatomic, strong) GLTFNode *_Nullable pointOfView;
@property (nonatomic, strong) GLTFViewerCamera *camera;
@property (nonatomic, assign) simd_float4x4 regularizationMatrix;

@property (nonatomic, assign) NSTimeInterval globalTime;

@end

@implementation GLTFViewerViewController

- (BOOL)acceptsFirstResponder {
    return YES;
}

#if TARGET_OS_OSX
- (void)setView:(NSView *)view {
    [super setView:view];
    
    self.sampleCount = 4;
    self.colorPixelFormat = MTLPixelFormatRGBA16Float;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    
    [self setupMetal];
    [self setupView];
    [self setupRenderer];
    [self loadSkyboxPipeline];
    [self loadBloomPipelines];
    [self loadTonemapPipeline];
    
    NSTrackingAreaOptions trackingOptions = NSTrackingMouseMoved | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect;
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                     options:trackingOptions
                                                       owner:self
                                                    userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}
#endif

- (void)setupMetal {
    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
    self.library = [self.device newDefaultLibrary];
}

- (void)setupView {
    self.metalView = (MTKView *)self.view;
    self.metalView.delegate = self;
    self.metalView.device = self.device;
    
    self.metalView.sampleCount = 4;
    self.metalView.clearColor = MTLClearColorMake(0.25, 0.25, 0.25, 1.0);
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    
    self.camera = [GLTFViewerOrbitCamera new];
}

- (void)setupRenderer {
    self.renderer = [[GLTFMTLRenderer alloc] initWithDevice:self.device];
    self.renderer.drawableSize = self.metalView.drawableSize;
    self.renderer.colorPixelFormat = self.colorPixelFormat;
    self.renderer.depthStencilPixelFormat = self.depthStencilPixelFormat;
}

- (void)setLightingEnvironment:(GLTFMTLLightingEnvironment *)lightingEnvironment {
    self.renderer.lightingEnvironment = lightingEnvironment;
}

- (GLTFMTLLightingEnvironment *)lightingEnvironment {
    return self.renderer.lightingEnvironment;
}

- (void)loadSkyboxPipeline {
    NSError *error = nil;
    
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [self.library newFunctionWithName:@"skybox_vertex_main"];
    descriptor.fragmentFunction = [self.library newFunctionWithName:@"skybox_fragment_main"];
    descriptor.sampleCount = self.metalView.sampleCount;
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    descriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
    
    self.skyboxPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.skyboxPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }
}

- (void)loadTonemapPipeline {
    NSError *error = nil;
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [self.library newFunctionWithName:@"quad_vertex_main"];
    descriptor.fragmentFunction = [self.library newFunctionWithName:@"tonemap_fragment_main"];
    descriptor.sampleCount = self.metalView.sampleCount;
    descriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    self.tonemapPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.tonemapPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }
}

- (void)loadBloomPipelines {
    NSError *error = nil;
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [self.library newFunctionWithName:@"quad_vertex_main"];
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    
    descriptor.fragmentFunction = [self.library newFunctionWithName:@"bloom_threshold_fragment_main"];
    self.bloomThresholdPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.bloomThresholdPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }

    descriptor.fragmentFunction = [self.library newFunctionWithName:@"blur_horizontal7_fragment_main"];
    self.blurHorizontalPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.blurHorizontalPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }

    descriptor.fragmentFunction = [self.library newFunctionWithName:@"blur_vertical7_fragment_main"];
    self.blurVerticalPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.blurVerticalPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }

    descriptor.fragmentFunction = [self.library newFunctionWithName:@"additive_blend_fragment_main"];
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorZero;
    self.additiveBlendPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.additiveBlendPipelineState == nil) {
        NSLog(@"Error occurred when creating render pipeline state: %@", error);
    }
}

- (simd_float4x4)viewMatrix {
    return self.renderer.viewMatrix;
}

- (void)setViewMatrix:(simd_float4x4)viewMatrix {
    self.renderer.viewMatrix = viewMatrix;
}

- (simd_float4x4)projectionMatrix {
    return self.renderer.projectionMatrix;
}

- (void)setProjectionMatrix:(simd_float4x4)projectionMatrix {
    self.renderer.projectionMatrix = projectionMatrix;
}

- (void)setAsset:(GLTFAsset *)asset {
    _asset = asset;
    [self computeRegularizationMatrix];
    [self computeTransforms];
    [self addDefaultLights];
}

- (void)addDefaultLights {
//    GLTFNode *lightNode = [[GLTFNode alloc] init];
//    lightNode.translation = (simd_float3){ 0, 0, 1 };
//    lightNode.rotationQuaternion = simd_quaternion(1.0f, 0, 0, 0);
//    GLTFKHRLight *light = [[GLTFKHRLight alloc] init];
//    lightNode.light = light;
//    [self.asset.defaultScene addNode:lightNode];
//    [self.asset addLight:light];
//    
//    GLTFKHRLight *ambientLight = [[GLTFKHRLight alloc] init];
//    ambientLight.type = GLTFKHRLightTypeAmbient;
//    ambientLight.intensity = 0.1;
//    [self.asset addLight:ambientLight];
//    self.asset.defaultScene.ambientLight = ambientLight;
}

- (void)computeRegularizationMatrix {
    GLTFBoundingSphere bounds = GLTFBoundingSphereFromBox(self.asset.defaultScene.approximateBounds);
    float scale = (bounds.radius > 0) ? (1 / (bounds.radius)) : 1;
    simd_float4x4 centerScale = GLTFMatrixFromUniformScale(scale);
    simd_float4x4 centerTranslation = GLTFMatrixFromTranslation(-bounds.center);
    self.regularizationMatrix = matrix_multiply(centerScale, centerTranslation);
}

- (void)computeTransforms {
    if (self.pointOfView == nil) {
        self.viewMatrix = matrix_multiply(self.camera.viewMatrix, self.regularizationMatrix);
    } else {
        self.viewMatrix = self.camera.viewMatrix;
    }

    float aspectRatio = self.renderer.drawableSize.width / self.renderer.drawableSize.height;
    simd_float4x4 aspectCorrection = GLTFMatrixFromScale((simd_float3){ 1 / aspectRatio, 1, 1 });
    self.projectionMatrix = simd_mul(aspectCorrection, self.camera.projectionMatrix);
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.globalTime += timestep;
    
    NSTimeInterval maxAnimDuration = 0;
    for (GLTFAnimation *animation in self.asset.animations) {
        for (GLTFAnimationChannel *channel in animation.channels) {
            if (channel.duration > maxAnimDuration) {
                maxAnimDuration = channel.duration;
            }
        }
    }
    
    NSTimeInterval animTime = fmod(self.globalTime, maxAnimDuration);

    for (GLTFAnimation *animation in self.asset.animations) {
        [animation runAtTime:animTime];
    }

    [self.camera updateWithTimestep:timestep];
    [self computeTransforms];
}

- (void)makeFramebuffer:(CGSize)drawableSize {
    MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor new];

    textureDescriptor.width = drawableSize.width;
    textureDescriptor.height = drawableSize.height;
    textureDescriptor.depth = 1;

    textureDescriptor.textureType = self.sampleCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;
    textureDescriptor.pixelFormat = self.colorPixelFormat;
    textureDescriptor.sampleCount = self.sampleCount;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget;
    self.multisampleColorTexture = [self.device newTextureWithDescriptor:textureDescriptor];
    
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.pixelFormat = self.colorPixelFormat;
    textureDescriptor.sampleCount = 1;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    self.colorTexture = [self.device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.textureType = self.sampleCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;
    textureDescriptor.pixelFormat = self.depthStencilPixelFormat;
    textureDescriptor.sampleCount = self.sampleCount;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget;
    self.depthStencilTexture = [self.device newTextureWithDescriptor:textureDescriptor];
    
    textureDescriptor.width = drawableSize.width / 2;
    textureDescriptor.height = drawableSize.height / 2;
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.pixelFormat = self.colorPixelFormat;
    textureDescriptor.sampleCount = 1;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    self.bloomTextureA = [self.device newTextureWithDescriptor:textureDescriptor];

    textureDescriptor.width = drawableSize.width / 2;
    textureDescriptor.height = drawableSize.height / 2;
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.pixelFormat = self.colorPixelFormat;
    textureDescriptor.sampleCount = 1;
    textureDescriptor.storageMode = MTLStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    self.bloomTextureB = [self.device newTextureWithDescriptor:textureDescriptor];
    
    self.renderer.sampleCount = self.sampleCount;
}

- (MTLRenderPassDescriptor *)currentRenderPassDescriptor {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    if (self.sampleCount > 1) {
        pass.colorAttachments[0].texture = self.multisampleColorTexture;
        pass.colorAttachments[0].resolveTexture = self.colorTexture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
    } else {
        pass.colorAttachments[0].texture = self.colorTexture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    }
    pass.depthAttachment.texture = self.depthStencilTexture;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.storeAction = MTLStoreActionDontCare;
    
    return pass;
}

- (void)drawSkyboxWithCommandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    float vertexData[] = {
        // +Z
        -1,  1,  1,
         1, -1,  1,
        -1, -1,  1,
         1, -1,  1,
        -1,  1,  1,
         1,  1,  1,
        // +X
         1,  1,  1,
         1, -1, -1,
         1, -1,  1,
         1, -1, -1,
         1,  1,  1,
         1,  1, -1,
        // -Z
         1,  1, -1,
        -1, -1, -1,
         1, -1, -1,
        -1, -1, -1,
         1,  1, -1,
        -1,  1, -1,
        // -X
        -1,  1, -1,
        -1, -1,  1,
        -1, -1, -1,
        -1, -1,  1,
        -1,  1, -1,
        -1,  1,  1,
        // +Y
        -1,  1, -1,
         1,  1,  1,
        -1,  1,  1,
         1,  1,  1,
        -1,  1, -1,
         1,  1, -1,
        // -Y
        -1, -1,  1,
         1, -1, -1,
        -1, -1, -1,
         1, -1, -1,
        -1, -1,  1,
         1, -1,  1,
    };

    simd_float4x4 viewProjectionMatrix = matrix_multiply(self.projectionMatrix, self.camera.viewMatrix);

    struct VertexUniforms {
        simd_float4x4 modelMatrix;
        simd_float4x4 modelViewProjectionMatrix;
    } vertexUniforms;
    
    vertexUniforms.modelMatrix = GLTFMatrixFromUniformScale(100);
    vertexUniforms.modelViewProjectionMatrix = matrix_multiply(viewProjectionMatrix, vertexUniforms.modelMatrix);
    
    float environmentIntensity = self.lightingEnvironment.intensity;
    
    [renderEncoder setRenderPipelineState:self.skyboxPipelineState];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeBack];
    [renderEncoder setVertexBytes:vertexData length:sizeof(float) * 36 * 3 atIndex:0];
    [renderEncoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms) atIndex:1];
    [renderEncoder setFragmentBytes:&environmentIntensity length:sizeof(environmentIntensity) atIndex:0];
    [renderEncoder setFragmentTexture:self.lightingEnvironment.diffuseCube atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
    [renderEncoder setCullMode:MTLCullModeNone];
}

- (void)drawFullscreenPassWithPipeline:(id<MTLRenderPipelineState>)renderPipelineState
                        commandEncoder:(id<MTLRenderCommandEncoder>)renderCommandEncoder
                         sourceTexture:(id<MTLTexture>)sourceTexture
{
    float triangleData[] = {
        -1,  3, 0, -1,
        -1, -1, 0,  1,
         3, -1, 2,  1
    };
    [renderCommandEncoder setRenderPipelineState:renderPipelineState];
    [renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderCommandEncoder setCullMode:MTLCullModeNone];
    [renderCommandEncoder setVertexBytes:triangleData length:sizeof(float) * 12 atIndex:0];
    [renderCommandEncoder setFragmentTexture:sourceTexture atIndex:0];
    [renderCommandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}

- (void)_selectCameraAtIndex:(int)cameraIndex {
    if (cameraIndex >= 0 && cameraIndex < self.asset.cameras.count) {
        GLTFCamera *camera = self.asset.cameras[cameraIndex];
        if (camera.referencingNodes.count > 0) {
            GLTFNode *cameraNode = camera.referencingNodes.firstObject;
            self.pointOfView = cameraNode;
            self.camera = [[GLTFViewerNodeCamera alloc] initWithNode:cameraNode];
        }
    }
}

// MARK: - NSResponder

#if TARGET_OS_OSX

- (void)mouseDown:(NSEvent *)event {
    [self.camera mouseDown:event];
}

- (void)mouseMoved:(NSEvent *)event {
    [self.camera mouseMoved:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self.camera mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self.camera mouseUp:event];
}

- (void)scrollWheel:(NSEvent *)event {
    [self.camera scrollWheel:event];
}

- (void)keyDown:(NSEvent *)event {
    [self.camera keyDown:event];
    
    switch (event.keyCode) {
        case kVK_ANSI_1:
            [self _selectCameraAtIndex:0];
            break;
        case kVK_ANSI_2:
            [self _selectCameraAtIndex:1];
            break;
        case kVK_ANSI_3:
            [self _selectCameraAtIndex:2];
            break;
        case kVK_ANSI_4:
            [self _selectCameraAtIndex:3];
            break;
        case kVK_ANSI_5:
            [self _selectCameraAtIndex:4];
            break;
        case kVK_ANSI_6:
            [self _selectCameraAtIndex:5];
            break;
        case kVK_ANSI_7:
            [self _selectCameraAtIndex:6];
            break;
        case kVK_ANSI_8:
            [self _selectCameraAtIndex:7];
            break;
        case kVK_ANSI_9:
            self.camera = [GLTFViewerOrbitCamera new];
            break;
        case kVK_ANSI_0:
            self.camera = [GLTFViewerFirstPersonCamera new];
            break;
            
        default:
            break;
    }
}

- (void)keyUp:(NSEvent *)event {
    [self.camera keyUp:event];
}

#endif

- (void)encodeMainPass:(id<MTLCommandBuffer>)commandBuffer {
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:self.currentRenderPassDescriptor];
    
    if (self.lightingEnvironment != nil) {
        [renderEncoder pushDebugGroup:@"Draw Backdrop"];
        [self drawSkyboxWithCommandEncoder:renderEncoder];
        [renderEncoder popDebugGroup];
    }
    
    [renderEncoder pushDebugGroup:@"Draw glTF Scene"];
    [self.renderer renderScene:self.asset.defaultScene
                 commandBuffer:commandBuffer
                commandEncoder:renderEncoder];
    [renderEncoder popDebugGroup];
    
    [renderEncoder endEncoding];
}

- (void)encodeBloomPasses:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = self.bloomTextureA;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [renderEncoder pushDebugGroup:@"Post-process (Bloom threshold)"];
    [self drawFullscreenPassWithPipeline:self.bloomThresholdPipelineState commandEncoder:renderEncoder sourceTexture:self.colorTexture];
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

    pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = self.bloomTextureB;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [renderEncoder pushDebugGroup:@"Post-process (Bloom blur - horizontal)"];
    [self drawFullscreenPassWithPipeline:self.blurHorizontalPipelineState commandEncoder:renderEncoder sourceTexture:self.bloomTextureA];
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

    pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = self.bloomTextureA;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [renderEncoder pushDebugGroup:@"Post-process (Bloom blur - vertical)"];
    [self drawFullscreenPassWithPipeline:self.blurVerticalPipelineState commandEncoder:renderEncoder sourceTexture:self.bloomTextureB];
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

    pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = self.colorTexture;
    pass.colorAttachments[0].loadAction = MTLLoadActionLoad;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    [renderEncoder pushDebugGroup:@"Post-process (Bloom combine)"];
    [self drawFullscreenPassWithPipeline:self.additiveBlendPipelineState commandEncoder:renderEncoder sourceTexture:self.bloomTextureA];
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];
}

- (void)encodeTonemappingPass:(id<MTLCommandBuffer>)commandBuffer {
    if (self.metalView.currentRenderPassDescriptor != nil) {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:self.metalView.currentRenderPassDescriptor];
        [renderEncoder pushDebugGroup:@"Post-process (Tonemapping)"];
        [self drawFullscreenPassWithPipeline:self.tonemapPipelineState commandEncoder:renderEncoder sourceTexture:self.colorTexture];
        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:self.metalView.currentDrawable];
    }
}

// MARK: - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.renderer.drawableSize = size;
    [self makeFramebuffer:size];
}

- (void)drawInMTKView:(MTKView *)view {
    float timestep = (1 / 60.0f);
    
    [self updateWithTimestep:timestep];
    
    if (self.colorTexture == nil) {
        [self makeFramebuffer:self.metalView.drawableSize];
    }

    id <MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    [self encodeMainPass:commandBuffer];
    [self encodeBloomPasses:commandBuffer];
    [self encodeTonemappingPass:commandBuffer];

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.renderer signalFrameCompletion];
        });
    }];
    
    [commandBuffer commit];
}

@end

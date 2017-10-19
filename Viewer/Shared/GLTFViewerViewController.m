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

#import "GLTFViewerViewController.h"
#import "GLTFViewerOrbitCamera.h"
#import "GLTFViewerFirstPersonCamera.h"

@import simd;

@interface GLTFViewerViewController ()
@property (nonatomic, weak) MTKView *metalView;

@property (nonatomic, strong) NSTrackingArea *trackingArea;

@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;

@property (nonatomic, strong) id<MTLRenderPipelineState> skyboxPipelineState;

@property (nonatomic, strong) GLTFMTLRenderer *renderer;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;

@property (nonatomic, strong) GLTFViewerCamera *camera;
@property (nonatomic, assign) simd_float4x4 regularizationMatrix;

@property (nonatomic, assign) NSTimeInterval globalTime;

@end

@implementation GLTFViewerViewController

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)setView:(NSView *)view {
    [super setView:view];
    
    [self setupMetal];
    [self setupView];
    [self setupRenderer];
    [self loadLightingEnvironment];
    [self loadSkyboxPipeline];
    
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.view.bounds
                                                     options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow )
                                                       owner:self
                                                    userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}

- (void)setupMetal {
    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
}

- (void)setupView {
    self.metalView = (MTKView *)self.view;
    self.metalView.delegate = self;
    self.metalView.device = self.device;
    
    self.metalView.sampleCount = 1;
    self.metalView.clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0);
    self.metalView.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    self.camera = [GLTFViewerOrbitCamera new];
}

- (void)setupRenderer {
    self.renderer = [[GLTFMTLRenderer alloc] initWithDevice:self.device];
    self.renderer.drawableSize = self.metalView.drawableSize;
    self.renderer.colorPixelFormat = self.metalView.colorPixelFormat;
    self.renderer.depthStencilPixelFormat = self.metalView.depthStencilPixelFormat;
}

- (void)loadLightingEnvironment {
    NSError *error = nil;
    NSURL *diffuseURL = [[NSBundle mainBundle] URLForResource:@"output_iem" withExtension:@"png"];
    NSMutableArray *specularURLs = [NSMutableArray array];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_0" withExtension:@"png"]];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_1" withExtension:@"png"]];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_2" withExtension:@"png"]];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_3" withExtension:@"png"]];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_4" withExtension:@"png"]];
    [specularURLs addObject:[[NSBundle mainBundle] URLForResource:@"output_pmrem_5" withExtension:@"png"]];
    NSURL *brdfURL = [[NSBundle mainBundle] URLForResource:@"brdfLUT" withExtension:@"png"];
    self.lightingEnvironment = [[GLTFMTLLightingEnvironment alloc] initWithDiffuseCubeURL:diffuseURL
                                                                         specularCubeURLs:specularURLs
                                                                               brdfLUTURL:brdfURL
                                                                                   device:self.device
                                                                                    error:&error];
    self.renderer.lightingEnvironment = self.lightingEnvironment;
}

- (void)loadSkyboxPipeline {
    NSError *error = nil;
    id <MTLLibrary> library = [self.device newDefaultLibrary];
    
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"skybox_vertex_main"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"skybox_fragment_main"];
    descriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    descriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    descriptor.stencilAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    self.skyboxPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (self.skyboxPipelineState == nil) {
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
}

- (void)computeRegularizationMatrix {
    GLTFBoundingSphere bounds = GLTFBoundingSphereFromBox(self.asset.defaultScene.approximateBounds);
    float scale = (bounds.radius > 0) ? (1 / (bounds.radius)) : 1;
    simd_float4x4 centerScale = GLTFMatrixFromUniformScale(scale);
    simd_float4x4 centerTranslation = GLTFMatrixFromTranslation(-bounds.center.x, -bounds.center.y, -bounds.center.z);
    self.regularizationMatrix = matrix_multiply(centerScale, centerTranslation);
}

- (void)computeTransforms {
    self.viewMatrix = matrix_multiply(self.camera.viewMatrix, self.regularizationMatrix);

//    if (_lastCameraIndex >= 0 && _lastCameraIndex < self.asset.cameras.count) {
//        GLTFCamera *camera = self.asset.cameras[_lastCameraIndex];
//        if (camera.referencingNodes.count > 0) {
//            GLTFNode *cameraNode = camera.referencingNodes.firstObject;
//            self.viewMatrix = matrix_invert(cameraNode.globalTransform);
//        }
//    }
    
    float aspectRatio = self.renderer.drawableSize.width / self.renderer.drawableSize.height;
    self.projectionMatrix = GLTFPerspectiveProjectionMatrixAspectFovRH(M_PI / 3, aspectRatio, 0.01, 150);
}

//- (void)keyDown:(NSEvent *)event {
//    switch (event.keyCode) {
//        case 29: _lastCameraIndex = 0; break;
//        case 18: _lastCameraIndex = 1; break;
//        case 19: _lastCameraIndex = 2; break;
//        case 20: _lastCameraIndex = 3; break;
//        case 21: _lastCameraIndex = 4; break;
//        case 23: _lastCameraIndex = 5; break;
//        case 22: _lastCameraIndex = 6; break;
//        case 26: _lastCameraIndex = 7; break;
//        case 28: _lastCameraIndex = 8; break;
//        case 25: _lastCameraIndex = 9; break;
//        default: _lastCameraIndex = -1; break;
//    }
//}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.globalTime += timestep;

    [self.asset runAnimationsAtTime:self.globalTime];

    [self.camera updateWithTimestep:timestep];
    [self computeTransforms];
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
    
    struct VertexUniforms {
        simd_float4x4 modelMatrix;
        simd_float4x4 modelViewProjectionMatrix;
    } vertexUniforms;
    
    vertexUniforms.modelMatrix = GLTFMatrixFromUniformScale(100);
    vertexUniforms.modelViewProjectionMatrix = matrix_multiply(matrix_multiply(self.projectionMatrix, self.viewMatrix), vertexUniforms.modelMatrix);
    
    [renderEncoder setRenderPipelineState:self.skyboxPipelineState];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeBack];
    [renderEncoder setVertexBytes:vertexData length:sizeof(float) * 36 * 3 atIndex:0];
    [renderEncoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms) atIndex:1];
    [renderEncoder setFragmentTexture:self.lightingEnvironment.specularCube atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
    [renderEncoder setCullMode:MTLCullModeNone];
}

// MARK: - NSResponder

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
}

- (void)keyUp:(NSEvent *)event {
    [self.camera keyUp:event];
}

// MARK: - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.renderer.drawableSize = size;
}

- (void)drawInMTKView:(MTKView *)view {
    float timestep = (1 / 60.0f);
    
    [self updateWithTimestep:timestep];
    
    id <MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    MTLRenderPassDescriptor *renderPassDescriptor = self.metalView.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderEncoder pushDebugGroup:@"Draw Backdrop"];
        [self drawSkyboxWithCommandEncoder:renderEncoder];
        [renderEncoder popDebugGroup];
        
        [renderEncoder pushDebugGroup:@"Draw glTF Scene"];
        [self.renderer renderScene:self.asset.defaultScene
                     commandBuffer:commandBuffer
                    commandEncoder:renderEncoder];
        [renderEncoder popDebugGroup];
        
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:self.metalView.currentDrawable];
    }
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        [self.renderer signalFrameCompletion];
    }];
    
    [commandBuffer commit];
}

@end

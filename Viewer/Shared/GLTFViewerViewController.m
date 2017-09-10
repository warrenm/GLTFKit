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

@import simd;

const CGFloat GLTFViewerDefaultCameraDistance = 2;
const CGFloat GLTFViewerZoomDrag = 0.95;

const CGFloat GLTFViewerRotationDrag = 0.95;
const CGFloat GLTFViewerRotationScaleFactor = 0.0033;
const CGFloat GLTFViewerRotationMomentumScaleFactor = 0.2;

@interface GLTFViewerViewController ()
@property (nonatomic, weak) MTKView *metalView;

@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;

@property (nonatomic, strong) id<MTLRenderPipelineState> skyboxPipelineState;

@property (nonatomic, strong) GLTFMTLRenderer *renderer;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;

@property (nonatomic, assign) matrix_float4x4 regularizationMatrix;

@property (nonatomic, assign) CGPoint cursorPosition;
@property (nonatomic, assign) CGVector cursorVelocity;
@property (nonatomic, assign) CGFloat azimuthalAngle;
@property (nonatomic, assign) CGFloat azimuthalVelocity;

@property (nonatomic, assign) CGFloat cameraDistance;
@property (nonatomic, assign) CGFloat cameraVelocity;
@property (nonatomic, assign) CGFloat zoomVelocity;

@property (nonatomic, assign) NSTimeInterval globalTime;

@end

@implementation GLTFViewerViewController

- (void)setView:(NSView *)view {
    [super setView:view];
    
    [self setupMetal];
    [self setupView];
    [self setupRenderer];
    [self loadLightingEnvironment];
    [self loadSkyboxPipeline];
}

- (void)setupMetal {
    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
}

- (void)setupView
{
    self.metalView = (MTKView *)self.view;
    self.metalView.delegate = self;
    self.metalView.device = self.device;
    
    self.metalView.sampleCount = 1;
    self.metalView.clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0);
    self.metalView.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    self.cameraDistance = GLTFViewerDefaultCameraDistance;
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

- (matrix_float4x4)viewMatrix {
    return self.renderer.viewMatrix;
}

- (void)setViewMatrix:(matrix_float4x4)viewMatrix {
    self.renderer.viewMatrix = viewMatrix;
}

- (void)setAsset:(GLTFAsset *)asset {
    _asset = asset;
    [self computeRegularizationMatrix];
    [self computeViewMatrix];
}

- (void)computeRegularizationMatrix {
    GLTFBoundingSphere bounds = GLTFBoundingSphereFromBox(self.asset.defaultScene.approximateBounds);
    float scale = (bounds.radius > 0) ? (1 / (bounds.radius)) : 1;
    matrix_float4x4 centerScale = GLTFMatrixFromUniformScale(scale);
    matrix_float4x4 centerTranslation = GLTFMatrixFromTranslation(-bounds.center.x, -bounds.center.y, -bounds.center.z);
    self.regularizationMatrix = matrix_multiply(centerScale, centerTranslation);
}

- (void)computeViewMatrix {
    self.viewMatrix = matrix_multiply(GLTFMatrixFromTranslation(0, 0, -self.cameraDistance), GLTFMatrixFromRotationAxisAngle(self.azimuthalAngle, 0, 1, 0));
}

- (void)mouseDown:(NSEvent *)event {
    self.cursorPosition = [event locationInWindow];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint currentCursorPosition = [event locationInWindow];
    self.cursorVelocity = CGVectorMake(self.cursorPosition.x - currentCursorPosition.x, self.cursorPosition.y - currentCursorPosition.y);
    
    self.azimuthalAngle += GLTFViewerRotationScaleFactor * -self.cursorVelocity.dx;
    self.cursorPosition = currentCursorPosition;
}

- (void)mouseUp:(NSEvent *)event {
    self.azimuthalVelocity = GLTFViewerRotationMomentumScaleFactor * -self.cursorVelocity.dx;
}

- (void)scrollWheel:(NSEvent *)event {
    self.cameraVelocity = 2 * event.deltaY;
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.globalTime += timestep;
    
    self.azimuthalAngle += self.azimuthalVelocity * timestep;
    self.azimuthalVelocity = self.azimuthalVelocity * GLTFViewerRotationDrag;
    
    self.cameraDistance += self.cameraVelocity * timestep;
    self.cameraVelocity = self.cameraVelocity * GLTFViewerZoomDrag;
    
    [self computeViewMatrix];
    [self.asset runAnimationsAtTime:self.globalTime];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.renderer.drawableSize = size;
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
    
    // TODO: Pass the projection matrix to the renderer so we're sure they match up
    CGSize drawableSize = self.metalView.drawableSize;
    matrix_float4x4 projectionMatrix = GLTFPerspectiveProjectionMatrixAspectFovRH(M_PI / 4, drawableSize.width / drawableSize.height, 0.1, 1000);
    
    struct VertexUniforms {
        simd_float4x4 modelMatrix;
        simd_float4x4 modelViewProjectionMatrix;
    } vertexUniforms;
    
    vertexUniforms.modelMatrix = matrix_multiply(GLTFMatrixFromUniformScale(100), self.regularizationMatrix);
    vertexUniforms.modelViewProjectionMatrix = matrix_multiply(matrix_multiply(projectionMatrix, self.viewMatrix), vertexUniforms.modelMatrix);
    
    [renderEncoder setRenderPipelineState:self.skyboxPipelineState];
    [renderEncoder setVertexBytes:vertexData length:sizeof(float) * 36 * 3 atIndex:0];
    [renderEncoder setVertexBytes:&vertexUniforms length:sizeof(vertexUniforms) atIndex:1];
    [renderEncoder setFragmentTexture:self.lightingEnvironment.specularCube atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
}

- (void)drawInMTKView:(MTKView *)view {
    float timestep = (1 / 60.0f);
    
    [self updateWithTimestep:timestep];
    
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    MTLRenderPassDescriptor *renderPassDescriptor = self.metalView.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderEncoder pushDebugGroup:@"Draw Backdrop"];
        [self drawSkyboxWithCommandEncoder:renderEncoder];
        [renderEncoder popDebugGroup];
        
        [renderEncoder pushDebugGroup:@"Draw glTF Scene"];
        [self.renderer renderScene:self.asset.defaultScene
                       modelMatrix:self.regularizationMatrix
                     commandBuffer:commandBuffer
                    commandEncoder:renderEncoder];
        [renderEncoder popDebugGroup];
        
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:_metalView.currentDrawable];
    }
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        [self.renderer signalFrameCompletion];
    }];
    
    [commandBuffer commit];
}

@end

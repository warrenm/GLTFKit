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
const CGFloat GLTFViewerLinearDrag = 0.95;

const CGFloat GLTFViewerRotationDrag = 0.95;
const CGFloat GLTFViewerRotationScaleFactor = 0.0033;
const CGFloat GLTFViewerRotationMomentumScaleFactor = 0.2;

@interface GLTFViewerViewController ()
@property (nonatomic, weak) MTKView *metalView;

@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;

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
    self.cameraVelocity = self.cameraVelocity * GLTFViewerLinearDrag;
    
    [self computeViewMatrix];
    [self.asset runAnimationsAtTime:self.globalTime];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.renderer.drawableSize = size;
}

- (void)drawInMTKView:(MTKView *)view {
    float timestep = (1 / 60.0f);
    
    [self updateWithTimestep:timestep];
    
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    MTLRenderPassDescriptor *renderPassDescriptor = self.metalView.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        [renderEncoder pushDebugGroup:@"DrawGLTFScene"];
        [self.renderer renderAsset:self.asset
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

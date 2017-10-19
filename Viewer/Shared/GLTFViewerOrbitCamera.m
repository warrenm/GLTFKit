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

#import "GLTFViewerOrbitCamera.h"
#import "HIToolboxEvents.h"
#import <GLTF/GLTF.h>

const CGFloat GLTFViewerOrbitCameraDefaultDistance = 2;
const CGFloat GLTFViewerOrbitCameraZoomDrag = 0.95;
const CGFloat GLTFViewerOrbitCameraRotationDrag = 0.6667;
const CGFloat GLTFViewerOrbitCameraRotationScaleFactor = 0.0033;
const CGFloat GLTFViewerOrbitCameraRotationMomentumScaleFactor = 0.2;

@interface GLTFViewerOrbitCamera ()
@property (nonatomic, assign) simd_float3 rotationAngles;
@property (nonatomic, assign) CGVector cursorVelocity;
@property (nonatomic, assign) CGFloat cameraDistance;
@property (nonatomic, assign) CGFloat cameraVelocity;
@property (nonatomic, assign) CGFloat zoomVelocity;

@end

@implementation GLTFViewerOrbitCamera

@synthesize viewMatrix=_viewMatrix;

- (instancetype)init {
    if ((self = [super init])) {
        _cameraDistance = GLTFViewerOrbitCameraDefaultDistance;
    }
    return self;
}

- (void)mouseDragged:(NSEvent *)event {
    [super mouseMoved:event];
    
    self.cursorVelocity = CGVectorMake(event.deltaX, event.deltaY);
}

- (void)scrollWheel:(NSEvent *)event {
    self.cameraVelocity = 2 * event.deltaY;
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.rotationAngles += (simd_float3){ self.cursorVelocity.dx * timestep, self.cursorVelocity.dy * timestep, 0 };

    // Clamp pitch
    self.rotationAngles = (simd_float3){ self.rotationAngles.x, MAX(-M_PI * 0.5, MIN(self.rotationAngles.y, M_PI * 0.5)), 0 };

    self.cursorVelocity = CGVectorMake(self.cursorVelocity.dx * GLTFViewerOrbitCameraRotationDrag,
                                       self.cursorVelocity.dy * GLTFViewerOrbitCameraRotationDrag);

    self.cameraDistance += self.cameraVelocity * timestep;
    self.cameraVelocity = self.cameraVelocity * GLTFViewerOrbitCameraZoomDrag;
    
    simd_float4x4 yawRotation = GLTFRotationMatrixFromAxisAngle(GLTFAxisY, -self.rotationAngles.x);
    simd_float4x4 pitchRotation = GLTFRotationMatrixFromAxisAngle(GLTFAxisX, -self.rotationAngles.y);
    simd_float4x4 cameraTranslation = GLTFMatrixFromTranslation(0, 0, self.cameraDistance);
    _viewMatrix = matrix_invert(matrix_multiply(matrix_multiply(yawRotation, pitchRotation), cameraTranslation));

}

@end


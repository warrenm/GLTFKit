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

#import "GLTFViewerOrbitCamera.h"
#import "HIToolboxEvents.h"
#import <GLTF/GLTF.h>

const float GLTFViewerOrbitCameraDefaultDistance = 2;
const float GLTFViewerOrbitCameraZoomDrag = 0.95;
const float GLTFViewerOrbitCameraRotationDrag = 0.6667;
const float GLTFViewerOrbitCameraZoomSensitivity = 2;

@interface GLTFViewerOrbitCamera ()
@property (nonatomic, assign) simd_float3 rotationAngles;
@property (nonatomic, assign) simd_float3 rotationVelocity;
@property (nonatomic, assign) float distance;
@property (nonatomic, assign) float velocity;
@end

@implementation GLTFViewerOrbitCamera

@synthesize viewMatrix=_viewMatrix;

- (instancetype)init {
    if ((self = [super init])) {
        _distance = GLTFViewerOrbitCameraDefaultDistance;
    }
    return self;
}

- (void)mouseDragged:(NSEvent *)event {
    [super mouseMoved:event];
    
    self.rotationVelocity = (simd_float3){ event.deltaX, event.deltaY, 0 };
}

- (void)scrollWheel:(NSEvent *)event {
    [super scrollWheel:event];
    
    self.velocity = event.deltaY * GLTFViewerOrbitCameraZoomSensitivity;
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.rotationAngles += self.rotationVelocity * timestep;

    // Clamp pitch
    self.rotationAngles = (simd_float3){ self.rotationAngles.x, fmax(-M_PI_2, fmin(self.rotationAngles.y, M_PI_2)), 0 };

    self.rotationVelocity *= GLTFViewerOrbitCameraRotationDrag;

    self.distance += self.velocity * timestep;
    self.velocity *= GLTFViewerOrbitCameraZoomDrag;
    
    simd_float4x4 pitchRotation = GLTFRotationMatrixFromAxisAngle(GLTFAxisX, -self.rotationAngles.y);
    simd_float4x4 yawRotation = GLTFRotationMatrixFromAxisAngle(GLTFAxisY, -self.rotationAngles.x);
    simd_float4x4 translation = GLTFMatrixFromTranslation((simd_float3){ 0, 0, self.distance });
    _viewMatrix = matrix_invert(matrix_multiply(matrix_multiply(yawRotation, pitchRotation), translation));
}

@end

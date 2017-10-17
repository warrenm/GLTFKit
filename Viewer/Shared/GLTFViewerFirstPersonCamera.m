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

#import "GLTFViewerFirstPersonCamera.h"
#import "HIToolboxEvents.h"
#import <GLTF/GLTF.h>

const CGFloat GLTFViewerFirstPersonCameraDefaultDistance = 2;
const CGFloat GLTFViewerFirstPersonCameraDefaultSpeed = 0.015;
const CGFloat GLTFViewerFirstPersonCameraMotionDecayFactor = 0.6667;
const CGFloat GLTFViewerFirstPersonCameraRotationDecayFactor = 0.8333;
const CGFloat GLTFViewerFirstPersonCameraRotationScaleFactor = 0.0033;

@interface GLTFViewerFirstPersonCamera ()

@property (nonatomic, assign) CGPoint cursorPosition;
@property (nonatomic, assign) CGVector cursorVelocity;
@property (nonatomic, assign) simd_float4 motionDirection;
@property (nonatomic, assign) simd_float4 position;
@property (nonatomic, assign) float pitch, yaw;
@end

@implementation GLTFViewerFirstPersonCamera

@synthesize viewMatrix=_viewMatrix;

- (instancetype)init {
    if ((self = [super init])) {
        _position = (simd_float4){ 0, 0, GLTFViewerFirstPersonCameraDefaultDistance, 1 };
        _pitch = 0;
        _yaw = 0;
    }
    return self;
}

- (void)mouseDown:(NSEvent *)event {
    self.cursorPosition = [event locationInWindow];
    self.cursorVelocity = CGVectorMake(0, 0);
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint currentCursorPosition = [event locationInWindow];
    self.cursorVelocity = CGVectorMake(self.cursorPosition.x - currentCursorPosition.x, self.cursorPosition.y - currentCursorPosition.y);
    
    self.cursorPosition = currentCursorPosition;
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    simd_float4 motionDirection = self.motionDirection;
    
    motionDirection = motionDirection * GLTFViewerFirstPersonCameraMotionDecayFactor;
    
    if (self.keysDown[kVK_UpArrow] || self.keysDown[kVK_ANSI_W]) {
        motionDirection.z -= 1;
    }
    if (self.keysDown[kVK_DownArrow] || self.keysDown[kVK_ANSI_S]) {
        motionDirection.z += 1;
    }
    if (self.keysDown[kVK_LeftArrow] || self.keysDown[kVK_ANSI_A]) {
        motionDirection.x -= 1;
    }
    if (self.keysDown[kVK_RightArrow] || self.keysDown[kVK_ANSI_D]) {
        motionDirection.x += 1;
    }

    self.motionDirection = motionDirection;
    
    self.yaw += GLTFViewerFirstPersonCameraRotationScaleFactor * -self.cursorVelocity.dx;
    self.pitch += GLTFViewerFirstPersonCameraRotationScaleFactor * self.cursorVelocity.dy;
    
    self.cursorVelocity = CGVectorMake(self.cursorVelocity.dx * GLTFViewerFirstPersonCameraRotationDecayFactor,
                                       self.cursorVelocity.dy * GLTFViewerFirstPersonCameraRotationDecayFactor);

    vector_float4 yawQuat = GLTFQuaternionFromEulerAngles(0, self.yaw, 0);
    vector_float4 pitchQuat = GLTFQuaternionFromEulerAngles(self.pitch, 0, 0);
    vector_float4 rotationQuat = GLTFQuaternionMultiply(pitchQuat, yawQuat);
    simd_float4x4 rotation = GLTFRotationMatrixFromQuaternion(rotationQuat);

    simd_float4 forward = rotation.columns[2];
    simd_float4 right = rotation.columns[0];
    
    self.position = self.position + (motionDirection.x * right + motionDirection.z * forward) * GLTFViewerFirstPersonCameraDefaultSpeed;

    simd_float4x4 translation = GLTFMatrixFromTranslation(self.position.x, self.position.y, self.position.z);
    _viewMatrix = matrix_invert(matrix_multiply(translation, rotation));
}

@end

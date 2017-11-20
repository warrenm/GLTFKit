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

const float GLTFViewerFirstPersonCameraDefaultDistance = 2;
const float GLTFViewerFirstPersonCameraDefaultSpeed = 0.015;
const float GLTFViewerFirstPersonCameraVelocityDecay = 0.6667;
const float GLTFViewerFirstPersonCameraRotationDecay = 0.8333;
const float GLTFViewerFirstPersonCameraRotationScale = 0.0033;

@interface GLTFViewerFirstPersonCamera ()

@property (nonatomic, assign) simd_float3 rotationVelocity;
@property (nonatomic, assign) simd_float3 rotationAngles;
@property (nonatomic, assign) simd_float3 velocity;
@property (nonatomic, assign) simd_float3 position;
@property (nonatomic, assign) BOOL capturedCursor;
@end

@implementation GLTFViewerFirstPersonCamera

@synthesize viewMatrix=_viewMatrix;

- (instancetype)init {
    if ((self = [super init])) {
        _position = (simd_float3){ 0, 0, GLTFViewerFirstPersonCameraDefaultDistance };
    }
    return self;
}

- (void)dealloc {
    [self releaseCursor];
}

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];

    [self captureCursor];
}

- (void)mouseMoved:(NSEvent *)event {
    [super mouseMoved:event];

    self.rotationVelocity = (simd_float3){ -event.deltaX, -event.deltaY, 0 };
}

- (void)keyUp:(NSEvent *)event {
    [super keyUp:event];
    
    if (event.keyCode == kVK_Escape) {
        [self releaseCursor];
    }
}

- (void)captureCursor {
    if (!self.capturedCursor) {
        CGAssociateMouseAndMouseCursorPosition(false);
        [NSCursor hide];
        self.capturedCursor = YES;
    }
}

- (void)releaseCursor {
    if (self.capturedCursor) {
        CGAssociateMouseAndMouseCursorPosition(true);
        [NSCursor unhide];
        self.capturedCursor = NO;
    }
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    simd_float3 velocity = self.velocity;
    
    velocity *= GLTFViewerFirstPersonCameraVelocityDecay;
    
    if (self.keysDown[kVK_UpArrow] || self.keysDown[kVK_ANSI_W]) {
        velocity.z -= 1;
    }
    if (self.keysDown[kVK_DownArrow] || self.keysDown[kVK_ANSI_S]) {
        velocity.z += 1;
    }
    if (self.keysDown[kVK_LeftArrow] || self.keysDown[kVK_ANSI_A]) {
        velocity.x -= 1;
    }
    if (self.keysDown[kVK_RightArrow] || self.keysDown[kVK_ANSI_D]) {
        velocity.x += 1;
    }

    self.velocity = velocity;
    
    self.rotationAngles += (simd_float3){ self.rotationVelocity.y, self.rotationVelocity.x, 0 } * GLTFViewerFirstPersonCameraRotationScale;

    self.rotationVelocity *= GLTFViewerFirstPersonCameraRotationDecay;

    GLTFQuaternion pitchQuat = GLTFQuaternionFromEulerAngles(self.rotationAngles.x, 0, 0);
    GLTFQuaternion yawQuat = GLTFQuaternionFromEulerAngles(0, self.rotationAngles.y, 0);
    GLTFQuaternion rotationQuat = GLTFQuaternionMultiply(yawQuat, pitchQuat);
    simd_float4x4 rotation = GLTFRotationMatrixFromQuaternion(rotationQuat);

    simd_float3 forward = rotation.columns[2].xyz;
    simd_float3 right = rotation.columns[0].xyz;
    
    self.position = self.position + (velocity.x * right + velocity.z * forward) * GLTFViewerFirstPersonCameraDefaultSpeed;

    simd_float4x4 translation = GLTFMatrixFromTranslation(self.position.x, self.position.y, self.position.z);
    _viewMatrix = matrix_invert(matrix_multiply(translation, rotation));
}

@end

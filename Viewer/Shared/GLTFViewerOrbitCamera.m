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
const CGFloat GLTFViewerOrbitCameraRotationDrag = 0.95;
const CGFloat GLTFViewerOrbitCameraRotationScaleFactor = 0.0033;
const CGFloat GLTFViewerOrbitCameraRotationMomentumScaleFactor = 0.2;

@interface GLTFViewerOrbitCamera ()
@property (nonatomic, assign) CGPoint cursorPosition;
@property (nonatomic, assign) CGVector cursorVelocity;
@property (nonatomic, assign) CGFloat azimuthalAngle;
@property (nonatomic, assign) CGFloat azimuthalVelocity;

@property (nonatomic, assign) CGFloat cameraDistance;
@property (nonatomic, assign) CGFloat cameraVelocity;
@property (nonatomic, assign) CGFloat zoomVelocity;

@end

@implementation GLTFViewerOrbitCamera

- (instancetype)init {
    if ((self = [super init])) {
        _cameraDistance = GLTFViewerOrbitCameraDefaultDistance;
    }
    return self;
}

- (simd_float4x4)viewMatrix {
    return matrix_multiply(GLTFMatrixFromTranslation(0, 0, -self.cameraDistance), GLTFRotationMatrixFromAxisAngle((simd_float3){ 0, 1, 0 }, self.azimuthalAngle));
}

- (void)mouseDown:(NSEvent *)event {
    self.cursorPosition = [event locationInWindow];
    self.cursorVelocity = CGVectorMake(0, 0);
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint currentCursorPosition = [event locationInWindow];
    self.cursorVelocity = CGVectorMake(self.cursorPosition.x - currentCursorPosition.x, self.cursorPosition.y - currentCursorPosition.y);
    
    self.azimuthalAngle += GLTFViewerOrbitCameraRotationScaleFactor * -self.cursorVelocity.dx;
    self.cursorPosition = currentCursorPosition;
}

- (void)mouseUp:(NSEvent *)event {
    self.azimuthalVelocity = GLTFViewerOrbitCameraRotationMomentumScaleFactor * -self.cursorVelocity.dx;
}

- (void)scrollWheel:(NSEvent *)event {
    self.cameraVelocity = 2 * event.deltaY;
}

- (void)keyDown:(NSEvent *)event {
}

- (void)keyUp:(NSEvent *)event {
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
    self.azimuthalAngle += self.azimuthalVelocity * timestep;
    self.azimuthalVelocity = self.azimuthalVelocity * GLTFViewerOrbitCameraRotationDrag;
    
    self.cameraDistance += self.cameraVelocity * timestep;
    self.cameraVelocity = self.cameraVelocity * GLTFViewerOrbitCameraZoomDrag;
}

@end


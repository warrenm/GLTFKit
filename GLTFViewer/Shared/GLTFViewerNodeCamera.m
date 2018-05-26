
#import "GLTFViewerNodeCamera.h"
#import <GLTF/GLTF.h>

@implementation GLTFViewerNodeCamera

- (instancetype)initWithNode:(GLTFNode *)node {
    if ((self = [super init])) {
        _node = node;
    }
    return self;
}

- (simd_float4x4)viewMatrix {
    return matrix_invert(self.node.globalTransform);
}

- (simd_float4x4)projectionMatrix {
    NSAssert(self.node.camera != nil, @"Point-of-view node has no associated camera");
    return self.node.camera.projectionMatrix;
}

- (void)updateWithTimestep:(NSTimeInterval)timestep {
}

@end

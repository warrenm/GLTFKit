
#import "GLTFViewerCamera.h"

@class GLTFNode;

@interface GLTFViewerNodeCamera : GLTFViewerCamera

@property (nonatomic, strong) GLTFNode *node;

- (instancetype)initWithNode:(GLTFNode *)node;

@end

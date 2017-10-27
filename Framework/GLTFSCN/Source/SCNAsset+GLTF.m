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

#import <Foundation/Foundation.h>

#import "SCNAsset+GLTF.h"

static SCNGeometryPrimitiveType GLTFSCNGeometryPrimitiveTypeForPrimitiveType(GLTFPrimitiveType primitiveType) {
    switch (primitiveType) {
        case GLTFPrimitiveTypePoints:
            return SCNGeometryPrimitiveTypePoint;
        case GLTFPrimitiveTypeLines:
            return SCNGeometryPrimitiveTypeLine;
        case GLTFPrimitiveTypeTriangles:
            return SCNGeometryPrimitiveTypeTriangles;
        case GLTFPrimitiveTypeTriangleStrip:
            return SCNGeometryPrimitiveTypeTriangleStrip;
        default:
            // Unsupported: line loop, line strip, triangle fan, polygon
            return -1;
    }
}

@interface GLTFSCNSceneBuilder : NSObject

@property (nonatomic, strong) GLTFScene *scene;
@property (nonatomic, copy) NSDictionary<id<NSCopying>, id> *options;

- (instancetype)initWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options;

- (SCNScene *)buildScene;

@end

@implementation GLTFSCNSceneBuilder

- (instancetype)initWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options {
    if ((self = [super init])) {
        _scene = scene;
        _options = options;
    }
    return self;
}

- (SCNScene *)buildScene {
    SCNScene *scnScene = [SCNScene scene];
    
    for (GLTFNode *node in self.scene.nodes) {
        [self recursiveAddNode:node toSCNNode:scnScene.rootNode];
    }
    
    return scnScene;
}

- (void)recursiveAddNode:(GLTFNode *)node toSCNNode:(SCNNode *)scnNode {
    SCNNode *childRoot = [SCNNode node];
    
    if (node.camera != nil) {
        // generate camera and add to node
    }
    
    // TODO: How to handle skins and joints?
    //    @property (nonatomic, weak) GLTFSkin *skin;
    //    @property (nonatomic, copy) NSString *jointName;
    
    scnNode.simdTransform = node.localTransform;
    
    [scnNode addChildNode:childRoot];
    
    NSArray<SCNNode *> *meshNodes = [self nodesForGLTFMesh:node.mesh];
    for (SCNNode *meshNode in meshNodes) {
        [childRoot addChildNode:meshNode];
    }
    
    for (GLTFNode *child in node.children) {
        [self recursiveAddNode:child toSCNNode:childRoot];
    }
}

- (NSArray<SCNNode *> *)nodesForGLTFMesh:(GLTFMesh *)mesh {
    if (mesh == nil) {
        return nil;
    }
    
    NSMutableArray *nodes = [NSMutableArray array];

    for (GLTFSubmesh *submesh in mesh.submeshes) {
        NSMutableArray *sources = [NSMutableArray array];
        NSMutableArray *elements = [NSMutableArray array];

        SCNGeometrySource *positionSource = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticVertex
                                                                    accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticPosition]];
        if (positionSource != nil) {
            [sources addObject:positionSource];
        }
        
        SCNGeometrySource *normalSource = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticNormal
                                                                  accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticNormal]];
        if (normalSource != nil) {
            [sources addObject:normalSource];
        }
        
        SCNGeometrySource *texCoord0Source = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticTexcoord
                                                                     accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticTexCoord0]];
        if (texCoord0Source != nil) {
            [sources addObject:texCoord0Source];
        }
        
        // TODO:
        //   SCNGeometrySourceSemanticColor;
        //   SCNGeometrySourceSemanticTangent
        //   SCNGeometrySourceSemanticBoneWeights
        //   SCNGeometrySourceSemanticBoneIndices
        
        GLTFAccessor *indexAccessor = submesh.indexAccessor;
        GLTFBufferView *indexBufferView = indexAccessor.bufferView;
        id<GLTFBuffer> indexBuffer = indexBufferView.buffer;
        SCNGeometryPrimitiveType primitiveType = GLTFSCNGeometryPrimitiveTypeForPrimitiveType(submesh.primitiveType);
        NSInteger bytesPerIndex = (indexAccessor.componentType == GLTFDataTypeUShort) ? sizeof(uint16_t) : sizeof(uint32_t);
        NSData *indexData = [NSData dataWithBytesNoCopy:indexBuffer.contents + indexBufferView.offset + indexAccessor.offset
                                                 length:indexAccessor.count * bytesPerIndex
                                           freeWhenDone:NO];
        NSInteger indexCount = indexAccessor.count / bytesPerIndex;
        NSInteger primitiveCount = indexCount / 3; // TODO: Wrong for anything other than indexed triangles
        SCNGeometryElement *geometryElement = [SCNGeometryElement geometryElementWithData:indexData
                                                                            primitiveType:primitiveType
                                                                           primitiveCount:primitiveCount
                                                                            bytesPerIndex:bytesPerIndex];
        [elements addObject:geometryElement];
        
        SCNGeometry *geometry = [SCNGeometry geometryWithSources:sources elements:elements];
        
        SCNNode *node = [SCNNode node];
        node.geometry = geometry;
        
        [nodes addObject:node];
    }
    
    // TODO: Materials!

    return nodes;
}

- (SCNGeometrySource *)geometrySourceWithSemantic:(SCNGeometrySourceSemantic)semantic accessor:(GLTFAccessor *)accessor {
    if (accessor == nil) {
        return nil;
    }
    
    GLTFBufferView *bufferView = accessor.bufferView;
    id<GLTFBuffer> buffer = bufferView.buffer;

    NSInteger bytesPerElement = GLTFSizeOfComponentTypeWithDimension(accessor.componentType, accessor.dimension);
    BOOL componentsAreFloat = GLTFDataTypeComponentsAreFloats(accessor.componentType);
    NSInteger componentsPerElement = GLTFComponentCountForDimension(accessor.dimension);
    NSInteger bytesPerComponent = bytesPerElement / componentsPerElement;
    NSInteger dataOffset = 0;
    NSInteger dataStride = accessor.bufferView.stride;
    if (dataStride == 0) {
        dataStride = GLTFSizeOfComponentTypeWithDimension(accessor.componentType, accessor.dimension);
    }
    
    NSData *data = [NSData dataWithBytesNoCopy:buffer.contents + bufferView.offset + accessor.offset
                                        length:accessor.count * bytesPerElement
                                  freeWhenDone:NO];

    SCNGeometrySource *source = [SCNGeometrySource geometrySourceWithData:data
                                                                 semantic:semantic
                                                              vectorCount:accessor.count
                                                          floatComponents:componentsAreFloat
                                                      componentsPerVector:componentsPerElement
                                                        bytesPerComponent:bytesPerComponent
                                                               dataOffset:dataOffset
                                                               dataStride:dataStride];
    return source;
}

@end

@implementation SCNScene (GLTF)

+ (instancetype)sceneWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options {
    GLTFSCNSceneBuilder *builder = [[GLTFSCNSceneBuilder alloc] initWithGLTFScene:scene options:options];
    return [builder buildScene];
}

@end

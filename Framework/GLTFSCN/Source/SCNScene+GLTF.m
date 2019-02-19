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
#import <sys/kdebug_signpost.h>

#import <Foundation/Foundation.h>

#import "SCNScene+GLTF.h"


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

static SCNWrapMode GLTFSCNWrapModeForAddressMode(GLTFAddressMode mode) {
    switch (mode) {
        case GLTFAddressModeClampToEdge:
            return SCNWrapModeClamp;
        case GLTFAddressModeMirroredRepeat:
            return SCNWrapModeMirror;
        case GLTFAddressModeRepeat:
        default:
            return SCNWrapModeRepeat;
    }
}

static NSInteger GLTFPrimitiveCountForIndexCount(NSInteger indexCount, SCNGeometryPrimitiveType primitiveType) {
    switch (primitiveType) {
        case SCNGeometryPrimitiveTypePoint:
            return indexCount;
        case SCNGeometryPrimitiveTypeLine:
            return indexCount / 2;
        case SCNGeometryPrimitiveTypeTriangles:
            return indexCount / 3;
        case SCNGeometryPrimitiveTypeTriangleStrip:
            return indexCount - 2;
        case SCNGeometryPrimitiveTypePolygon:
            return 1;
        default:
            return 0;
    }
}

static SCNMatrix4 GLTFSCNMatrix4FromFloat4x4(GLTFMatrix4 m) {
    SCNMatrix4 mOut = (SCNMatrix4) {
        m.columns[0].x, m.columns[0].y, m.columns[0].z, m.columns[0].w,
        m.columns[1].x, m.columns[1].y, m.columns[1].z, m.columns[1].w,
        m.columns[2].x, m.columns[2].y, m.columns[2].z, m.columns[2].w,
        m.columns[3].x, m.columns[3].y, m.columns[3].z, m.columns[3].w
    };
    return mOut;
}

static SCNMatrix4 GLTFSCNContentsTransformFromTextureTransform(GLTFTextureTransform transform) {
    simd_float3x3 m = GLTFTextureMatrixFromTransform(transform);
    SCNMatrix4 mOut = (SCNMatrix4) {
        m.columns[0].x, m.columns[0].y, 0, 0,
        m.columns[1].x, m.columns[1].y, 0, 0,
                     0,              0, 1, 0,
        m.columns[2].x, m.columns[2].y, 0, 1
    };
    return mOut;

}

@implementation GLTFSCNAnimationTargetPair
@end

@implementation GLTFSCNAsset
@end

@interface GLTFSCNSceneBuilder : NSObject

@property (nonatomic, strong) GLTFAsset *asset;
@property (nonatomic, copy) NSDictionary<id<NSCopying>, id> *options;
@property (nonatomic, weak) id<GLTFSCNAssetLoadingDelegate> loadingDelegate;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, SCNNode *> *scnNodesForGLTFNodes;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSArray<NSValue *> *> *inverseBindMatricesForSkins;
@property (nonatomic, assign) NSInteger anonymousAnimationIndex;

- (instancetype)initWithGLTFAsset:(GLTFAsset *)asset delegate:(id<GLTFSCNAssetLoadingDelegate>)delegate options:(NSDictionary<id<NSCopying>, id> *)options;

- (GLTFSCNAsset *)buildSceneContainer;

@end

@implementation GLTFSCNSceneBuilder

- (instancetype)initWithGLTFAsset:(GLTFAsset *)asset delegate:(id<GLTFSCNAssetLoadingDelegate>)delegate options:(NSDictionary<id<NSCopying>, id> *)options {
    if ((self = [super init])) {
        _asset = asset;
        _options = options;
        _scnNodesForGLTFNodes = [NSMutableDictionary dictionary];
        _inverseBindMatricesForSkins = [NSMutableDictionary dictionary];
        _loadingDelegate = delegate;
    }
    return self;
}

- (NSString *)_nextAnonymousAnimationName {
    NSString *name = [NSString stringWithFormat:@"animation_%d", (int)self.anonymousAnimationIndex];
    self.anonymousAnimationIndex = self.anonymousAnimationIndex + 1;
    return name;
}

- (GLTFSCNAsset *)buildSceneContainer {
    GLTFSCNAsset *scnAsset = [GLTFSCNAsset new];

    NSMutableArray *scenes = [NSMutableArray array];

    for (GLTFScene *scene in self.asset.scenes) {
        SCNScene *scnScene = [SCNScene scene];

        for (GLTFNode *node in scene.nodes) {
            [self recursiveAddNode:node toSCNNode:scnScene.rootNode];
        }

        [scenes addObject:scnScene];
    }

    NSMutableDictionary *animations = [NSMutableDictionary dictionary];
    for (GLTFAnimation *animation in self.asset.animations) {
        NSString *name = animation.name ?: [self _nextAnonymousAnimationName];
        NSMutableArray *pairs = [NSMutableArray array];
        for (GLTFAnimationChannel *channel in animation.channels) {
            CAKeyframeAnimation *keyframeAnimation = nil;
            if ([channel.targetPath isEqualToString:@"rotation"]) {
                keyframeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"orientation"];
                keyframeAnimation.values = [self arrayFromQuaternionAccessor:channel.sampler.outputAccessor];
            } else if ([channel.targetPath isEqualToString:@"translation"]) {
                keyframeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"translation"];
                keyframeAnimation.values = [self vectorArrayFromAccessor:channel.sampler.outputAccessor];
            } else if ([channel.targetPath isEqualToString:@"scale"]) {
                keyframeAnimation = [CAKeyframeAnimation animationWithKeyPath:@"scale"];
                keyframeAnimation.values = [self vectorArrayFromAccessor:channel.sampler.outputAccessor];
            } else {
                continue;
            }
            keyframeAnimation.keyTimes = [self normalizedArrayFromFloatAccessor:channel.sampler.inputAccessor
                                                                   minimumValue:channel.startTime
                                                                   maximumValue:channel.endTime];
            keyframeAnimation.beginTime = channel.startTime;
            keyframeAnimation.duration = channel.duration;
            keyframeAnimation.repeatDuration = FLT_MAX;

            SCNNode *scnNode = self.scnNodesForGLTFNodes[channel.targetNode.identifier];
            if (scnNode != nil) {
                GLTFSCNAnimationTargetPair *pair = [GLTFSCNAnimationTargetPair new];
                pair.animation = keyframeAnimation;
                pair.target = scnNode;
                [pairs addObject:pair];
            } else {
                NSLog(@"WARNING: Could not find node for channel target node identifier %@", channel.targetNode.identifier);
            }
        }
        animations[name] = [pairs copy];
    }

    scnAsset.scenes = [scenes copy];
    scnAsset.animations = [animations copy];

    if (self.asset.defaultScene != nil) {
        NSUInteger defaultSceneIndex = [self.asset.scenes indexOfObject:self.asset.defaultScene];
        if (defaultSceneIndex < scenes.count) {
            scnAsset.defaultScene = scenes[defaultSceneIndex];
        }
    }

    return scnAsset;
}

- (void)recursiveAddNode:(GLTFNode *)node toSCNNode:(SCNNode *)parentNode {
    SCNNode *scnNode = [self makeSCNNodeForGLTFNode:node];

    if (node.camera != nil) {
        // generate camera and add to node
    }

    if (@available(iOS 11.0, *)) {
        scnNode.simdTransform = node.localTransform;
    } else {
        scnNode.transform = SCNMatrix4FromMat4(node.localTransform);
    }
    scnNode.name = node.name;

    [parentNode addChildNode:scnNode];

    NSArray<SCNNode *> *meshNodes = [self nodesForGLTFMesh:node.mesh skin:node.skin];
    for (SCNNode *meshNode in meshNodes) {
        [scnNode addChildNode:meshNode];
    }

    for (GLTFNode *child in node.children) {
        [self recursiveAddNode:child toSCNNode:scnNode];
    }
}

- (NSArray<SCNNode *> *)nodesForGLTFMesh:(GLTFMesh *)mesh skin:(GLTFSkin *)skin {
    if (mesh == nil) {
        return nil;
    }

    NSMutableArray *nodes = [NSMutableArray array];

    NSArray<SCNNode *> *bones = [self bonesForGLTFSkin:skin];
    NSArray<NSValue *> *inverseBindMatrices = [self inverseBindMatricesForGLTFSkin:skin];

    NSInteger submeshIndex = 0;
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

        SCNGeometrySource *tangentSource = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticTangent
                                                                   accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticTangent]];
        if (tangentSource != nil) {
            [sources addObject:tangentSource];
        }

        SCNGeometrySource *texCoord0Source = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticTexcoord
                                                                     accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticTexCoord0]];
        if (texCoord0Source != nil) {
            [sources addObject:texCoord0Source];
        }

        SCNGeometrySource *color0Source = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticColor
                                                                  accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticColor0]];
        if (color0Source != nil) {
            [sources addObject:color0Source];
        }

        GLTFAccessor *indexAccessor = submesh.indexAccessor;
        GLTFBufferView *indexBufferView = indexAccessor.bufferView;
        id<GLTFBuffer> indexBuffer = indexBufferView.buffer;
        SCNGeometryPrimitiveType primitiveType = GLTFSCNGeometryPrimitiveTypeForPrimitiveType(submesh.primitiveType);
        NSInteger bytesPerIndex = (indexAccessor.componentType == GLTFDataTypeUShort) ? sizeof(uint16_t) : sizeof(uint32_t);
        NSData *indexData = [NSData dataWithBytes:indexBuffer.contents + indexBufferView.offset + indexAccessor.offset
                                           length:indexAccessor.count * bytesPerIndex];
        NSInteger indexCount = indexAccessor.count;
        NSInteger primitiveCount = GLTFPrimitiveCountForIndexCount(indexCount, primitiveType);
        SCNGeometryElement *geometryElement = [SCNGeometryElement geometryElementWithData:indexData
                                                                            primitiveType:primitiveType
                                                                           primitiveCount:primitiveCount
                                                                            bytesPerIndex:bytesPerIndex];
        [elements addObject:geometryElement];

        SCNGeometry *geometry = [SCNGeometry geometryWithSources:sources elements:elements];

        SCNMaterial *material = [self materialForGLTFMaterial:submesh.material];
        geometry.materials = @[material];

        SCNNode *node = [SCNNode node];
        node.geometry = geometry;

        SCNGeometrySource *boneWeights = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticBoneWeights
                                                                 accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticWeights0]];
        SCNGeometrySource *boneIndices = [self geometrySourceWithSemantic:SCNGeometrySourceSemanticBoneIndices
                                                                 accessor:submesh.accessorsForAttributes[GLTFAttributeSemanticJoints0]];
        if (boneWeights != nil && boneIndices != nil) {
            SCNSkinner *skinner = [SCNSkinner skinnerWithBaseGeometry:geometry
                                                                bones:bones
                                            boneInverseBindTransforms:inverseBindMatrices
                                                          boneWeights:boneWeights
                                                          boneIndices:boneIndices];
            node.skinner = skinner;
        }

        [nodes addObject:node];
        ++submeshIndex;
    }

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
        dataStride = bytesPerElement;
    }

    void *dataBase = buffer.contents + bufferView.offset + accessor.offset;

    // Ensure linear sum of weights is equal to 1; this is required by the spec, and SceneKit
    // relies on this invariant as of iOS 12 and macOS Mojave. This fix is due to Alexander Petrovichev;
    // refer to https://github.com/warrenm/GLTFKit/issues/5
    if ([semantic isEqualToString:SCNGeometrySourceSemanticBoneWeights])
    {
        NSAssert(accessor.componentType == GLTFDataTypeFloat && accessor.dimension == GLTFDataDimensionVector4,
                 @"Accessor for joint weights must be of float4 type; other data types are not currently supported");
        for (int i = 0; i < accessor.count; ++i) {
            float *weights = (float *)(dataBase + i * dataStride);
            float sum = weights[0] + weights[1] + weights[2] + weights[3];
            if (sum != 1.0f) {
                weights[0] /= sum;
                weights[1] /= sum;
                weights[2] /= sum;
                weights[3] /= sum;
            }
        }
    }

    NSData *data = [NSData dataWithBytes:dataBase length:accessor.count * dataStride];

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

- (SCNNode *)makeSCNNodeForGLTFNode:(GLTFNode *)node {
    SCNNode *scnNode = self.scnNodesForGLTFNodes[node.identifier];
    if (scnNode == nil) {
        scnNode = [SCNNode node];
        self.scnNodesForGLTFNodes[node.identifier] = scnNode;
    }
    return scnNode;
}

- (NSArray<SCNNode *> *)bonesForGLTFSkin:(GLTFSkin *)skin {
    if (skin == nil) {
        return @[];
    }

    NSMutableArray<SCNNode *> *bones = [NSMutableArray array];
    for (GLTFNode *jointNode in skin.jointNodes) {
        SCNNode *boneNode = [self makeSCNNodeForGLTFNode:jointNode];
        if (boneNode != nil) {
            [bones addObject:boneNode];
        } else {
            NSLog(@"WARNING: Did not find node for joint with identifier %@", jointNode.identifier);
        }
    }

    if (bones.count == skin.jointNodes.count) {
        return [bones copy];
    } else {
        NSLog(@"WARNING: Bone count for skinner does not match joint node count for skin with identifier %@", skin.identifier);
    }

    return @[];
}

- (NSArray<NSValue *> *)inverseBindMatricesForGLTFSkin:(GLTFSkin *)skin {
    if (skin == nil) {
        return @[];
    }

    NSArray<NSValue *> *inverseBindMatrices = self.inverseBindMatricesForSkins[skin.identifier];
    if (inverseBindMatrices != nil) {
        return inverseBindMatrices;
    }

    NSMutableArray *matrices = [NSMutableArray array];
    GLTFAccessor *ibmAccessor = skin.inverseBindMatricesAccessor;
    GLTFMatrix4 *ibms = ibmAccessor.bufferView.buffer.contents + ibmAccessor.bufferView.offset + ibmAccessor.offset;
    for (int i = 0; i < ibmAccessor.count; ++i) {
        SCNMatrix4 ibm = GLTFSCNMatrix4FromFloat4x4(ibms[i]);
        NSValue *ibmValue = [NSValue valueWithSCNMatrix4:ibm];
        [matrices addObject:ibmValue];
    }
    matrices = [matrices copy];
    self.inverseBindMatricesForSkins[skin.identifier] = matrices;

    return matrices;
}

- (SCNMaterial *)materialForGLTFMaterial:(GLTFMaterial *)material {
    if (material == nil) {
        return nil;
    }

    kdebug_signpost_start(60, 0, 0, 0, 0);

    SCNMaterial *scnMaterial = [SCNMaterial material];

    scnMaterial.name = material.name;

    scnMaterial.lightingModelName = SCNLightingModelPhysicallyBased;

    scnMaterial.diffuse.contents = [self.loadingDelegate uiImageForGLTFImage:material.baseColorTexture.texture.image
                                                              channelMask:GLTFImageChannelAll];
    if (scnMaterial.diffuse.contents == nil) {
        scnMaterial.diffuse.contents = (__bridge_transfer id)[self newCGColorForFloat4:material.baseColorFactor];
    }
    scnMaterial.diffuse.wrapS = GLTFSCNWrapModeForAddressMode(material.baseColorTexture.texture.sampler.sAddressMode);
    scnMaterial.diffuse.wrapT = GLTFSCNWrapModeForAddressMode(material.baseColorTexture.texture.sampler.tAddressMode);
    scnMaterial.diffuse.mappingChannel = material.baseColorTexture.texCoord;
    scnMaterial.diffuse.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.baseColorTexture.transform);

    scnMaterial.metalness.contents = [self.loadingDelegate uiImageForGLTFImage:material.metallicRoughnessTexture.texture.image
                                                                channelMask:GLTFImageChannelBlue];
    if (scnMaterial.metalness.contents == nil) {
        scnMaterial.metalness.contents = @(material.metalnessFactor);
    }
    scnMaterial.metalness.wrapS = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.texture.sampler.sAddressMode);
    scnMaterial.metalness.wrapT = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.texture.sampler.tAddressMode);
    scnMaterial.metalness.mappingChannel = material.metallicRoughnessTexture.texCoord;
    scnMaterial.metalness.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.metallicRoughnessTexture.transform);

    scnMaterial.roughness.contents = [self.loadingDelegate uiImageForGLTFImage:material.metallicRoughnessTexture.texture.image
                                                                channelMask:GLTFImageChannelGreen];
    if (scnMaterial.roughness.contents == nil) {
        scnMaterial.roughness.contents = @(material.roughnessFactor);
    }
    scnMaterial.roughness.wrapS = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.texture.sampler.sAddressMode);
    scnMaterial.roughness.wrapT = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.texture.sampler.tAddressMode);
    scnMaterial.roughness.mappingChannel = material.metallicRoughnessTexture.texCoord;
    scnMaterial.roughness.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.metallicRoughnessTexture.transform);

    scnMaterial.normal.contents = [self.loadingDelegate uiImageForGLTFImage:material.normalTexture.texture.image
                                                             channelMask:GLTFImageChannelAll];
    scnMaterial.normal.wrapS = GLTFSCNWrapModeForAddressMode(material.normalTexture.texture.sampler.sAddressMode);
    scnMaterial.normal.wrapT = GLTFSCNWrapModeForAddressMode(material.normalTexture.texture.sampler.tAddressMode);
    scnMaterial.normal.mappingChannel = material.normalTexture.texCoord;
    scnMaterial.normal.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.normalTexture.transform);

    scnMaterial.ambientOcclusion.contents = [self.loadingDelegate uiImageForGLTFImage:material.occlusionTexture.texture.image
                                                                       channelMask:GLTFImageChannelRed];
    scnMaterial.ambientOcclusion.wrapS = GLTFSCNWrapModeForAddressMode(material.occlusionTexture.texture.sampler.sAddressMode);
    scnMaterial.ambientOcclusion.wrapT = GLTFSCNWrapModeForAddressMode(material.occlusionTexture.texture.sampler.tAddressMode);
    scnMaterial.ambientOcclusion.mappingChannel = material.occlusionTexture.texCoord;
    scnMaterial.ambientOcclusion.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.occlusionTexture.transform);

    scnMaterial.emission.contents = [self.loadingDelegate uiImageForGLTFImage:material.emissiveTexture.texture.image
                                                               channelMask:GLTFImageChannelAll];
    if (scnMaterial.emission.contents == nil) {
        scnMaterial.emission.contents = (__bridge_transfer id)[self newCGColorForFloat3:material.emissiveFactor];
    }
    scnMaterial.emission.wrapS = GLTFSCNWrapModeForAddressMode(material.emissiveTexture.texture.sampler.sAddressMode);
    scnMaterial.emission.wrapT = GLTFSCNWrapModeForAddressMode(material.emissiveTexture.texture.sampler.tAddressMode);
    scnMaterial.emission.mappingChannel = material.emissiveTexture.texCoord;
    scnMaterial.emission.contentsTransform = GLTFSCNContentsTransformFromTextureTransform(material.emissiveTexture.transform);

    kdebug_signpost_end(60, 0, 0, 0, 0);
    return scnMaterial;
}


- (CGColorRef)newCGColorForFloat4:(simd_float4)v {
    CGFloat components[] = { v.x, v.y, v.z, v.w };
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef color = CGColorCreate(colorSpace, &components[0]);
    CGColorSpaceRelease(colorSpace);
    return color;
}

- (CGColorRef)newCGColorForFloat3:(simd_float3)v {
    CGFloat components[] = { v.x, v.y, v.z, 1 };
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef color = CGColorCreate(colorSpace, &components[0]);
    CGColorSpaceRelease(colorSpace);
    return color;
}

- (NSArray<NSValue *> *)arrayFromQuaternionAccessor:(GLTFAccessor *)accessor {
    NSMutableArray *values = [NSMutableArray array];
    const GLTFQuaternion *quaternions = accessor.bufferView.buffer.contents + accessor.bufferView.offset + accessor.offset;
    NSInteger count = accessor.count;
    for (NSInteger i = 0; i < count; ++i) {
        SCNVector4 quat = (SCNVector4){ quaternions[i].vector[0], quaternions[i].vector[1], quaternions[i].vector[2], quaternions[i].vector[3] };
        NSValue *value = [NSValue valueWithSCNVector4:quat];
        [values addObject:value];
    }
    return [values copy];
}

- (NSArray<NSValue *> *)vectorArrayFromAccessor:(GLTFAccessor *)accessor {
    NSMutableArray *values = [NSMutableArray array];
    const GLTFVector3 *vectors = accessor.bufferView.buffer.contents + accessor.bufferView.offset + accessor.offset;
    NSInteger count = accessor.count;
    for (NSInteger i = 0; i < count; ++i) {
        GLTFVector3 vec = vectors[i];
        SCNVector3 scnVec = (SCNVector3){ vec.x, vec.y, vec.z };
        NSValue *value = [NSValue valueWithSCNVector3:scnVec];
        [values addObject:value];
    }
    return [values copy];
}

- (NSArray<NSValue *> *)vectorArrayFromScalarAccessor:(GLTFAccessor *)accessor {
    NSMutableArray *values = [NSMutableArray array];
    const float *floats = accessor.bufferView.buffer.contents + accessor.bufferView.offset + accessor.offset;
    NSInteger count = accessor.count;
    for (NSInteger i = 0; i < count; ++i) {
        SCNVector3 scnVec = (SCNVector3){ floats[i], floats[i], floats[i] };
        NSValue *value = [NSValue valueWithSCNVector3:scnVec];
        [values addObject:value];
    }
    return [values copy];
}

- (NSArray<NSNumber *> *)normalizedArrayFromFloatAccessor:(GLTFAccessor *)accessor minimumValue:(float)minimumValue maximumValue:(float)maximumValue {
    NSMutableArray *values = [NSMutableArray array];
    const float *floats = accessor.bufferView.buffer.contents + accessor.bufferView.offset + accessor.offset;
    NSInteger count = accessor.count;
    for (NSInteger i = 0; i < count; ++i) {
        float f = floats[i];
        f = fmin(fmax(0, (f - minimumValue) / (maximumValue - minimumValue)), 1);
        NSValue *value = [NSNumber numberWithFloat:f];
        [values addObject:value];
    }
    return [values copy];
}

@end

@implementation SCNScene (GLTF)

// can be blocking! default implementation of image loading delegate is.
+ (GLTFSCNAsset *)assetFromGLTFAsset:(GLTFAsset *)asset options:(NSDictionary<id<NSCopying>, id> *)options {
  return [self assetFromGLTFAsset:asset delegate:[DefaultGLTFSCNAssetLoadingDelegate new] options:options];
}


+ (GLTFSCNAsset *)assetFromGLTFAsset:(GLTFAsset *)asset delegate:(id<GLTFSCNAssetLoadingDelegate>)delegate options:(NSDictionary<id<NSCopying>, id> *)options {
  GLTFSCNSceneBuilder *builder = [[GLTFSCNSceneBuilder alloc] initWithGLTFAsset:asset delegate:(id<GLTFSCNAssetLoadingDelegate>)delegate options:options];

  return [builder buildSceneContainer];
}

@end




@implementation DefaultGLTFSCNAssetLoadingDelegate

- init {
  if ((self = [super init])) {
    _cgImagesForImagesAndChannels = [NSMutableDictionary dictionary];
  }
  return self;

}

- (CGImageRef)cgImageForGLTFImage:(GLTFImage *)image channelMask:(GLTFImageChannel)channelMask {
  if (image == nil) {
    return nil;
  }

  NSString *maskedIdentifier = [NSString stringWithFormat:@"%@/%d", image.identifier.UUIDString, (int)channelMask];

  // Check the cache to see if we already have an exact match for the requested image and channel subset
  CGImageRef exactCachedImage = (__bridge CGImageRef)self.cgImagesForImagesAndChannels[maskedIdentifier];
  if (exactCachedImage != nil) {
    return exactCachedImage;
  }

  // If we don't have an exact match for the image+channel pair, we may still have the original image cached
  NSString *unmaskedIdentifier = [NSString stringWithFormat:@"%@/%d", image.identifier.UUIDString, (int)GLTFImageChannelAll];
  CGImageRef originalImage = (__bridge CGImageRef)self.cgImagesForImagesAndChannels[unmaskedIdentifier];

  if (originalImage == NULL) {
    // We got unlucky, so we need to load and cache the original
    if (image.imageData != nil) {
      CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)image.imageData, nil);
      originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);
      if (imageSource) {
        CFRelease(imageSource);
      }
    } else if (image.url != nil) {
      NSLog(@"CACHE MISS id: %@ for url: %@ ", unmaskedIdentifier, image.url);
      CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)image.url, nil);
      originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);
      if (imageSource) {
        CFRelease(imageSource);
      }
    } else if (image.bufferView != nil) {
      GLTFBufferView *bufferView = image.bufferView;
      NSData *imageData = [NSData dataWithBytes:bufferView.buffer.contents + bufferView.offset length:bufferView.length];
      CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, nil);
      originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);
      if (imageSource) {
        CFRelease(imageSource);
      }
    }

    NSLog(@"CACHE STORE id: %@", unmaskedIdentifier);
    self.cgImagesForImagesAndChannels[unmaskedIdentifier] = (__bridge id)originalImage;
    CGImageRelease(originalImage);
  }

  // Now that we have the original, we may need to extract the requisite channel and cache the result
  if (channelMask != GLTFImageChannelAll) {
    CGImageRef extractedImage = [self newCGImageByExtractingChannel:(int)channelMask fromCGImage:originalImage];
    NSLog(@"CACHE STORE MASKED id: %@", maskedIdentifier);
    self.cgImagesForImagesAndChannels[maskedIdentifier] = (__bridge id)extractedImage;
    CGImageRelease(extractedImage);
    return extractedImage;
  }

  return originalImage;
}

- (CGImageRef)newCGImageByExtractingChannel:(NSInteger)channelIndex fromCGImage:(CGImageRef)sourceImage {
  if (sourceImage == NULL) {
    return NULL;
  }

  size_t width = CGImageGetWidth(sourceImage);
  size_t height = CGImageGetHeight(sourceImage);
  size_t bpc = 8;
  size_t Bpr = width * 4;

  uint8_t *pixels = malloc(Bpr * height);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(pixels, width, height, bpc, Bpr, colorSpace, kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), sourceImage);

  for (int i = 0; i < width * height; ++i) {
    uint8_t components[4] = { pixels[i * 4 + 0], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] }; // RGBA
    pixels[i] = components[channelIndex];
  }

  CGColorSpaceRef monoColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
  CGContextRef monoContext = CGBitmapContextCreate(pixels, width, height, bpc, width, monoColorSpace, kCGImageAlphaNone);

  CGImageRef channelImage = CGBitmapContextCreateImage(monoContext);

  CGColorSpaceRelease(monoColorSpace);
  CGContextRelease(monoContext);
  CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  free(pixels);

  return channelImage;
}



@end

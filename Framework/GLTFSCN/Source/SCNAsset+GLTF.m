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


typedef NS_ENUM(NSInteger, GLTFImageChannel) {
    GLTFImageChannelRed,
    GLTFImageChannelGreen,
    GLTFImageChannelBlue,
    GLTFImageChannelAlpha,
    GLTFImageChannelAll = 255
};

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

@interface GLTFSCNSceneBuilder : NSObject

@property (nonatomic, strong) GLTFScene *scene;
@property (nonatomic, copy) NSDictionary<id<NSCopying>, id> *options;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *cgImagesForImagesAndChannels;

- (instancetype)initWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options;

- (SCNScene *)buildScene;

@end

@implementation GLTFSCNSceneBuilder

- (instancetype)initWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options {
    if ((self = [super init])) {
        _scene = scene;
        _options = options;
        _cgImagesForImagesAndChannels = [NSMutableDictionary dictionary];
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

- (void)recursiveAddNode:(GLTFNode *)node toSCNNode:(SCNNode *)parentNode {
    SCNNode *scnNode = [SCNNode node];
    
    if (node.camera != nil) {
        // generate camera and add to node
    }
    
    // TODO: How to handle skins and joints?
    //    @property (nonatomic, weak) GLTFSkin *skin;
    //    @property (nonatomic, copy) NSString *jointName;
    
    scnNode.simdTransform = node.localTransform;
    scnNode.name = node.name;

    [parentNode addChildNode:scnNode];
    
    NSArray<SCNNode *> *meshNodes = [self nodesForGLTFMesh:node.mesh];
    for (SCNNode *meshNode in meshNodes) {
        [scnNode addChildNode:meshNode];
    }

    for (GLTFNode *child in node.children) {
        [self recursiveAddNode:child toSCNNode:scnNode];
    }
}

- (NSArray<SCNNode *> *)nodesForGLTFMesh:(GLTFMesh *)mesh {
    if (mesh == nil) {
        return nil;
    }
    
    NSMutableArray *nodes = [NSMutableArray array];

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
        
        // TODO:
        //   SCNGeometrySourceSemanticColor;
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
        NSInteger indexCount = indexAccessor.count;
        NSInteger primitiveCount = indexCount / 3; // TODO: Wrong for anything other than indexed triangles
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
    
    NSData *data = [NSData dataWithBytesNoCopy:buffer.contents + bufferView.offset + accessor.offset
                                        length:accessor.count * dataStride
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

- (SCNMaterial *)materialForGLTFMaterial:(GLTFMaterial *)material {
    if (material == nil) {
        return nil;
    }
    
    SCNMaterial *scnMaterial = [SCNMaterial material];
    
    scnMaterial.name = material.name;
    
    scnMaterial.lightingModelName = SCNLightingModelPhysicallyBased;

    scnMaterial.diffuse.contents = (__bridge id)[self cgImageForGLTFImage:material.baseColorTexture.image
                                                              channelMask:GLTFImageChannelAll];
    if (scnMaterial.diffuse.contents == nil) {
        scnMaterial.diffuse.contents = (__bridge id)[self createCGColorForFloat4:material.baseColorFactor];
    }
    scnMaterial.diffuse.wrapS = GLTFSCNWrapModeForAddressMode(material.baseColorTexture.sampler.sAddressMode);
    scnMaterial.diffuse.wrapT = GLTFSCNWrapModeForAddressMode(material.baseColorTexture.sampler.tAddressMode);
    scnMaterial.diffuse.mappingChannel = material.baseColorTexCoord;
    
    scnMaterial.metalness.contents = (__bridge id)[self cgImageForGLTFImage:material.metallicRoughnessTexture.image
                                                                channelMask:GLTFImageChannelBlue];
    if (scnMaterial.metalness.contents == nil) {
        scnMaterial.metalness.contents = @(material.metalnessFactor);
    }
    scnMaterial.metalness.wrapS = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.sampler.sAddressMode);
    scnMaterial.metalness.wrapT = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.sampler.tAddressMode);
    scnMaterial.metalness.mappingChannel = material.metallicRoughnessTexCoord;
    
    scnMaterial.roughness.contents = (__bridge id)[self cgImageForGLTFImage:material.metallicRoughnessTexture.image
                                                                channelMask:GLTFImageChannelGreen];
    if (scnMaterial.roughness.contents == nil) {
        scnMaterial.roughness.contents = @(material.roughnessFactor);
    }
    scnMaterial.roughness.wrapS = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.sampler.sAddressMode);
    scnMaterial.roughness.wrapT = GLTFSCNWrapModeForAddressMode(material.metallicRoughnessTexture.sampler.tAddressMode);
    scnMaterial.roughness.mappingChannel = material.metallicRoughnessTexCoord;
    
    scnMaterial.normal.contents = (__bridge id)[self cgImageForGLTFImage:material.normalTexture.image
                                                             channelMask:GLTFImageChannelAll];
    scnMaterial.normal.wrapS = GLTFSCNWrapModeForAddressMode(material.normalTexture.sampler.sAddressMode);
    scnMaterial.normal.wrapT = GLTFSCNWrapModeForAddressMode(material.normalTexture.sampler.tAddressMode);
    scnMaterial.normal.mappingChannel = material.normalTexCoord;
    
    scnMaterial.ambientOcclusion.contents = (__bridge id)[self cgImageForGLTFImage:material.occlusionTexture.image
                                                                       channelMask:GLTFImageChannelRed];
    scnMaterial.ambientOcclusion.wrapS = GLTFSCNWrapModeForAddressMode(material.occlusionTexture.sampler.sAddressMode);
    scnMaterial.ambientOcclusion.wrapT = GLTFSCNWrapModeForAddressMode(material.occlusionTexture.sampler.tAddressMode);
    scnMaterial.ambientOcclusion.mappingChannel = material.occlusionTexCoord;
    
    scnMaterial.emission.contents = (__bridge id)[self cgImageForGLTFImage:material.emissiveTexture.image
                                                               channelMask:GLTFImageChannelAll];
    if (scnMaterial.emission.contents == nil) {
        scnMaterial.emission.contents = (__bridge id)[self createCGColorForFloat3:material.emissiveFactor];
    }
    scnMaterial.emission.wrapS = GLTFSCNWrapModeForAddressMode(material.emissiveTexture.sampler.sAddressMode);
    scnMaterial.emission.wrapT = GLTFSCNWrapModeForAddressMode(material.emissiveTexture.sampler.tAddressMode);
    scnMaterial.emission.mappingChannel = material.emissiveTexCoord;

    return scnMaterial;
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
        if (image.cgImage != nil) {
            originalImage = image.cgImage;
            CGImageRetain(originalImage);
        } else if (image.url != nil) {
            CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)image.url, nil);
            originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);
            if (imageSource) {
                CFRelease(imageSource);
            }
        }
        
        self.cgImagesForImagesAndChannels[unmaskedIdentifier] = (__bridge id)originalImage;
        CGImageRelease(originalImage);
    }
    
    // Now that we have the original, we may need to extract the requisite channel and cache the result
    if (channelMask != GLTFImageChannelAll) {
        CGImageRef extractedImage = [self createCGImageByExtractingChannel:(int)channelMask fromCGImage:originalImage];
        self.cgImagesForImagesAndChannels[maskedIdentifier] = (__bridge id)extractedImage;
        CGImageRelease(extractedImage);
        return extractedImage;
    }
    
    return originalImage;
}

- (CGImageRef)createCGImageByExtractingChannel:(NSInteger)channelIndex fromCGImage:(CGImageRef)sourceImage {
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

    CGContextRelease(monoContext);
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    free(pixels);
    
    return channelImage;
}

- (CGColorRef)createCGColorForFloat4:(simd_float4)v {
    CGFloat components[] = { v.x, v.y, v.z, v.w };
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef color = CGColorCreate(colorSpace, &components[0]);
    CGColorSpaceRelease(colorSpace);
    return color;
}

- (CGColorRef)createCGColorForFloat3:(simd_float3)v {
    CGFloat components[] = { v.x, v.y, v.z, 1 };
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef color = CGColorCreate(colorSpace, &components[0]);
    CGColorSpaceRelease(colorSpace);
    return color;
}

@end

@implementation SCNScene (GLTF)

+ (instancetype)sceneWithGLTFScene:(GLTFScene *)scene options:(NSDictionary<id<NSCopying>, id> *)options {
    GLTFSCNSceneBuilder *builder = [[GLTFSCNSceneBuilder alloc] initWithGLTFScene:scene options:options];
    return [builder buildScene];
}

@end

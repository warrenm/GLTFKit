
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

#import "GLTFAsset.h"
#import "GLTFAnimation.h"
#import "GLTFAccessor.h"
#import "GLTFBuffer.h"
#import "GLTFBufferAllocator.h"
#import "GLTFBufferView.h"
#import "GLTFCamera.h"
#import "GLTFMaterial.h"
#import "GLTFMesh.h"
#import "GLTFNode.h"
#import "GLTFImage.h"
#import "GLTFTexture.h"
#import "GLTFTextureSampler.h"
#import "GLTFScene.h"
#import "GLTFSkin.h"
#import "GLTFUtilities.h"

@import simd;

#define USE_AGGRESSIVE_ALIGNMENT 0

static NSString *const GLTFExtensionKHRMaterialsPBRSpecularGlossiness = @"KHR_materials_pbrSpecularGlossiness";

@interface GLTFAsset ()
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;
@property (nonatomic, copy) NSArray *accessors;
@property (nonatomic, copy) NSArray *buffers;
@property (nonatomic, copy) NSArray *bufferViews;
@property (nonatomic, copy) NSArray *images;
@property (nonatomic, copy) NSArray *samplers;
@property (nonatomic, copy) NSArray *textures;
@property (nonatomic, copy) NSArray *meshes;
@property (nonatomic, copy) NSArray *materials;
@property (nonatomic, copy) NSArray *lights;
@property (nonatomic, copy) NSArray *nodes;
@property (nonatomic, copy) NSArray *animations;
@property (nonatomic, copy) NSArray<GLTFSkin *> *skins;
@property (nonatomic, strong) GLTFMaterial *defaultMaterial;
@property (nonatomic, strong) GLTFTextureSampler *defaultSampler;
@property (nonatomic, assign) BOOL usesPBRSpecularGlossiness;
@end

@implementation GLTFAsset

- (instancetype)initWithURL:(NSURL *)url bufferAllocator:(id<GLTFBufferAllocator>)bufferAllocator {
    if (url == nil) {
        return nil;
    }
    
    if ((self = [super init])) {
        _url = url;
        _bufferAllocator = bufferAllocator;
        NSError *error = nil;
        if (![self loadWithError:&error]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)loadWithError:(NSError **)errorOrNil {
    NSData *assetData = [NSData dataWithContentsOfURL:_url];
    NSError *error = nil;
    NSDictionary *rootObject = [NSJSONSerialization JSONObjectWithData:assetData options:0 error:&error];
    
    if (!rootObject) {
        if (errorOrNil) { *errorOrNil = error; }
        return NO;
    }
    
    _extensionsUsed = [rootObject[@"extensionsUsed"] ?: @[] copy];
    
    [self toggleExtensionFeatureFlags];

    _defaultSampler =  [GLTFTextureSampler new];
    
    _defaultMaterial = [GLTFMaterial new];
    
    // Since we aren't streaming, we have the properties for all objects in memory
    // and we can load in the order that makes the least work for us, i.e. by
    // reducing the number of name resolutions we have to do after we deserialize
    // everything into glTF objects. The only object subgraph that can't be
    // resolved by careful ordering of loading is the subgraph of nodes itself,
    // which is stored unordered and may contain arbitrary node-node relationships.
    // Therefore, we run a post-load fix-up pass to resolve all node graph edges
    // into real object references. Refer to `fixNodeRelationships` below.
    
    [self loadAssetProperties:rootObject[@"asset"]];
    [self loadBuffers:rootObject[@"buffers"]];
    [self loadBufferViews:rootObject[@"bufferViews"]];
    [self loadAccessors:rootObject[@"accessors"]];
    [self loadSamplers:rootObject[@"samplers"]];
    [self loadImages:rootObject[@"images"]];
    [self loadTextures:rootObject[@"textures"]];
    [self loadMaterials:rootObject[@"materials"]];
    [self loadCameras:rootObject[@"cameras"]];
    [self loadSkins:rootObject[@"skins"]];
    [self loadMeshes:rootObject[@"meshes"]];
    [self loadNodes:rootObject[@"nodes"]];
    [self loadAnimations:rootObject[@"animations"]];
    [self loadScenes:rootObject[@"scenes"]];
    [self loadDefaultScene:rootObject[@"scene"]];

    return YES;
}

- (void)toggleExtensionFeatureFlags {
    for (NSString *extension in _extensionsUsed) {
        if ([extension isEqualToString:GLTFExtensionKHRMaterialsPBRSpecularGlossiness]) {
            _usesPBRSpecularGlossiness = YES;
        } else {
            NSLog(@"WARNING: Unsupported extension \"%@\" used", extension);
        }
    }
}

- (BOOL)loadAssetProperties:(NSDictionary *)propertiesMap {
    _generator = [propertiesMap[@"generator"] copy];
    _copyright = [propertiesMap[@"copyright"] copy];
    _formatVersion = propertiesMap[@"version"] ?: @"2.0";
    return YES;
}

- (BOOL)loadAccessors:(NSArray *)accessorsMap {
    if (accessorsMap.count == 0) {
        _accessors = @[];
        return YES;
    }
    
    NSMutableArray *accessors = [NSMutableArray arrayWithCapacity:accessorsMap.count];
    for (NSDictionary *properties in accessorsMap) {
        GLTFAccessor *accessor = [[GLTFAccessor alloc] init];
        accessor.componentType = [properties[@"componentType"] integerValue];
        accessor.dimension = GLTFDataDimensionForName(properties[@"type"]);
        accessor.offset = [properties[@"byteOffset"] integerValue];
        accessor.count = [properties[@"count"] integerValue];
        NSUInteger bufferViewIndex = [properties[@"bufferView"] intValue];
        if (bufferViewIndex < _bufferViews.count) {
            accessor.bufferView = _bufferViews[bufferViewIndex];
#if USE_AGGRESSIVE_ALIGNMENT
            size_t alignment = GLTFSizeOfComponentTypeWithDimension(accessor.componentType, accessor.dimension);
#else
            size_t alignment = GLTFSizeOfDataType(accessor.componentType);
#endif
            NSInteger dataOffset = accessor.offset + accessor.bufferView.offset;
            if (dataOffset % alignment != 0) {
                size_t elementSize = GLTFSizeOfComponentTypeWithDimension(accessor.componentType, accessor.dimension);
                size_t length = accessor.count * elementSize;
                NSLog(@"WARNING: Accessor had misaligned offset %d, which is not a multiple of %d. Building auxiliary buffer of length %d and continuing...",
                      (int)dataOffset, (int)alignment, (int)length);
                id<GLTFBuffer> buffer = [_bufferAllocator newBufferWithLength:length];
                memcpy(buffer.contents, accessor.bufferView.buffer.contents + accessor.bufferView.offset + accessor.offset, buffer.length);
                _buffers = [_buffers arrayByAddingObject:buffer];

                GLTFBufferView *bufferView = [GLTFBufferView new];
                bufferView.buffer = buffer;
                bufferView.offset = 0;
                bufferView.stride = 0;
                _bufferViews = [_bufferViews arrayByAddingObject:bufferView];

                accessor.bufferView = bufferView;
                accessor.offset = 0;
            }
        }

        __block GLTFValueRange valueRange = { 0 };
        NSArray *minValues = properties[@"min"];
        [minValues enumerateObjectsUsingBlock:^(NSNumber *num, NSUInteger index, BOOL *stop) {
            valueRange.minValue[index] = num.floatValue;
        }];
        NSArray *maxValues = properties[@"max"];
        [maxValues enumerateObjectsUsingBlock:^(NSNumber *num, NSUInteger index, BOOL *stop) {
            valueRange.maxValue[index] = num.floatValue;
        }];
        accessor.valueRange = valueRange;
        
        [accessors addObject:accessor];
    }
    
    _accessors = [accessors copy];
    
    return YES;
}

- (BOOL)loadBuffers:(NSArray *)buffersMap {
    if (buffersMap.count == 0) {
        _buffers = @[];
    }
    
    NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:buffersMap.count];
    for (NSDictionary *properties in buffersMap) {
        NSUInteger byteLength = [properties[@"byteLength"] integerValue];

        NSString *uri = properties[@"uri"];
        NSData *data = nil;
        
        if ([uri hasPrefix:@"data:"]) {
            if ([uri hasPrefix:@"data:application/octet-stream;base64,"]) {
                NSString *dataSubstring = [uri substringFromIndex:[@"data:application/octet-stream;base64," length]];
                data = [[NSData alloc] initWithBase64EncodedString:dataSubstring options:0];
            }
        } else if (uri.length > 0) {
            NSURL *fileURL = [[_url URLByDeletingLastPathComponent] URLByAppendingPathComponent:uri];
            NSError *error = nil;
            data = [NSData dataWithContentsOfURL:fileURL options:0 error:&error];
            NSAssert(data != nil, @"Unable to load data at URL %@; error %@", fileURL, error);
        }
        
        id<GLTFBuffer> buffer = [_bufferAllocator newBufferWithData:data];
        
        NSParameterAssert(byteLength == [buffer length]);
        [buffers addObject: buffer];
    }
    
    _buffers = [buffers copy];
    return YES;
}

- (BOOL)loadBufferViews:(NSArray *)bufferViewsMap {
    if (bufferViewsMap.count == 0) {
        _bufferViews = @[];
    }
    
    NSMutableArray *bufferViews = [NSMutableArray arrayWithCapacity:bufferViewsMap.count];
    [bufferViewsMap enumerateObjectsUsingBlock:^(NSDictionary *properties, NSUInteger index, BOOL *stop) {
        
        GLTFBufferView *bufferView = [[GLTFBufferView alloc] init];
        NSUInteger bufferIndex = [properties[@"buffer"] intValue];
        if (bufferIndex < _buffers.count) {
            bufferView.buffer = _buffers[bufferIndex];
        }
        bufferView.length = [properties[@"byteLength"] integerValue];
        bufferView.stride = [properties[@"byteStride"] integerValue];
        bufferView.offset = [properties[@"byteOffset"] integerValue];
        bufferView.target = [properties[@"target"] integerValue];

//        if ((bufferView.buffer != nil) && (bufferView.offset % 16 != 0)) {
//            NSLog(@"WARNING: Buffer view %d had misaligned offset of %d. Creating auxilliary buffer of length %d and continuing...",
//                  (int)index, (int)bufferView.offset, (int)bufferView.length);
//            id<GLTFBuffer> alignedBuffer = [_bufferAllocator newBufferWithLength:bufferView.length];
//            _buffers = [_buffers arrayByAddingObject:alignedBuffer];
//            memcpy([alignedBuffer contents], bufferView.buffer.contents + bufferView.offset, bufferView.length);
//            bufferView.buffer = alignedBuffer;
//            bufferView.offset = 0;
//        }
        
        [bufferViews addObject: bufferView];
    }];
    
    _bufferViews = [bufferViews copy];
    return YES;
}

- (BOOL)loadSamplers:(NSArray *)samplersMap {
    if (samplersMap.count == 0) {
        _samplers = @[];
    }

    NSMutableArray *samplers = [NSMutableArray arrayWithCapacity:samplersMap.count];
    for (NSDictionary *properties in samplersMap) {
        GLTFTextureSampler *sampler = [[GLTFTextureSampler alloc] init];
        sampler.minFilter = [properties[@"minFilter"] integerValue] ?: sampler.minFilter;
        sampler.magFilter = [properties[@"magFilter"] integerValue] ?: sampler.magFilter;
        sampler.sAddressMode = [properties[@"wrapS"] integerValue] ?: sampler.sAddressMode;
        sampler.tAddressMode = [properties[@"wrapT"] integerValue] ?: sampler.tAddressMode;
        sampler.name = properties[@"name"];
        sampler.extensions = properties[@"extensions"];
        sampler.extras = properties[@"extras"];

        [samplers addObject:sampler];
    }

    _samplers = [samplers copy];
    return YES;
}

- (BOOL)loadImages:(NSArray *)imagesMap {
    if (imagesMap.count == 0) {
        _images = @[];
    }
    
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:imagesMap.count];
    for (NSDictionary *properties in imagesMap) {
        GLTFImage *image = [[GLTFImage alloc] init];
        
        NSString *uri = properties[@"uri"];
        
        if ([uri hasPrefix:@"data:image/"]) {
            image.cgImage = [GLTFImage newImageForDataURI:uri];
        } else if (uri.length > 0) {
            NSURL *resourceURL = [self.url URLByDeletingLastPathComponent];
            image.url = [resourceURL URLByAppendingPathComponent:uri];
        }
        
        image.mimeType = properties[@"mimeType"];
        
        NSString *bufferViewIndexString = properties[@"bufferView"];
        if (bufferViewIndexString) {
            NSUInteger bufferViewIndex = bufferViewIndexString.integerValue;
            if (bufferViewIndex < _bufferViews.count) {
                image.bufferView = _bufferViews[bufferViewIndex];
            }
        }
        
        image.name = properties[@"name"];
        image.extensions = properties[@"extensions"];
        image.extras = properties[@"extras"];

        [images addObject:image];
    }
    
    _images = [images copy];
    return YES;
}

- (BOOL)loadTextures:(NSArray *)texturesMap {
    if (texturesMap.count == 0) {
        _textures = @[];
    }

    NSMutableArray *textures = [NSMutableArray arrayWithCapacity:texturesMap.count];
    for (NSDictionary *properties in texturesMap) {
        GLTFTexture *texture = [[GLTFTexture alloc] init];

        NSUInteger samplerIndex = [properties[@"sampler"] intValue];
        if (samplerIndex < _samplers.count) {
            texture.sampler = _samplers[samplerIndex];
        } else {
            texture.sampler = _defaultSampler;
        }

        NSUInteger imageIndex = [properties[@"source"] intValue];
        if (imageIndex < _images.count) {
            texture.image = _images[imageIndex];
        }

        texture.format = [properties[@"format"] integerValue] ?: texture.format;
        texture.internalFormat = [properties[@"internalFormat"] integerValue] ?: texture.internalFormat;
        texture.target = [properties[@"target"] integerValue] ?: texture.target;
        texture.type = [properties[@"type"] integerValue] ?: texture.type;
        texture.name = properties[@"name"];
        texture.extensions = properties[@"extensions"];
        texture.extras = properties[@"extras"];

        [textures addObject: texture];
    }

    _textures = [textures copy];
    return YES;
}


- (BOOL)loadCameras:(NSArray *)camerasMap {
    if (camerasMap.count == 0) {
        _cameras = @[];
        return YES;
    }
    
    NSMutableArray *cameras = [NSMutableArray arrayWithCapacity:camerasMap.count];
    for (NSDictionary *properties in camerasMap) {
        GLTFCamera *camera = [[GLTFCamera alloc] init];
        
        camera.cameraType = [properties[@"type"] isEqualToString:@"orthographic"] ? GLTFCameraTypeOrthographic : GLTFCameraTypePerspective;
        
        NSDictionary *params = properties[properties[@"type"]];
        
        switch (camera.cameraType) {
            case GLTFCameraTypeOrthographic:
                camera.xmag = [params[@"xmag"] floatValue];
                camera.ymag = [params[@"ymag"] floatValue];
                break;
            case GLTFCameraTypePerspective:
            default:
                camera.aspectRatio = [params[@"aspectRatio"] floatValue];
                camera.yfov = [params[@"yfov"] floatValue];
                break;
        }
        
        camera.znear = [params[@"znear"] floatValue];
        
        if (camera.cameraType == GLTFCameraTypePerspective && (params[@"zfar"] == nil)) {
            camera.zfar = FLT_MAX;
        } else {
            camera.zfar = [params[@"zfar"] floatValue];
        }

        camera.extensions = properties[@"extensions"];
        camera.extras = properties[@"extras"];
        
        [camera buildProjectionMatrix];
        
        [cameras addObject: camera];
    }
    
    _cameras = [cameras copy];
    return YES;
}

- (BOOL)loadLights:(NSArray *)lightsMap {
    if (lightsMap.count == 0) {
        _lights = @[];
    }
    
    NSMutableArray *lights = [NSMutableArray arrayWithCapacity:lightsMap.count];
    [lightsMap enumerateObjectsUsingBlock:^(NSDictionary *properties, NSUInteger index, BOOL *stop) {
//        GLTFKHRLight *light = [[GLTFKHRLight alloc] initWithIdentifier:identifier];
//        NSString *lightTypeName = properties[@"type"];
//        if ([lightTypeName isEqualToString:@"ambient"]) {
//            light.type = GLTFKHRLightTypeAmbient;
//        } else if ([lightTypeName isEqualToString:@"directional"]) {
//            light.type = GLTFKHRLightTypeDirectional;
//        } else if ([lightTypeName isEqualToString:@"point"]) {
//            light.type = GLTFKHRLightTypePoint;
//        } else if ([lightTypeName isEqualToString:@"spot"]) {
//            light.type = GLTFKHRLightTypeSpot;
//        }
//        
//        if ([lightTypeName length] > 0) {
//            NSDictionary *lightProperties = properties[lightTypeName];
//            
//            NSArray *colorArray = lightProperties[@"color"];
//            switch ([colorArray count]) {
//                case 3: // This is out of spec, but it happens in the wild, so be graceful.
//                    light.color = GLTFVectorFloat4FromArray([colorArray arrayByAddingObject:@(1)]);
//                    break;
//                case 4:
//                    light.color = GLTFVectorFloat4FromArray(colorArray);
//                    break;
//            }
//
//            if (light.type == GLTFKHRLightTypeDirectional || light.type == GLTFKHRLightTypeSpot) {
//                NSArray *directionArray = lightProperties[@"direction"];
//                if ([directionArray count] == 4) {
//                    light.direction = GLTFVectorFloat4FromArray(directionArray);
//                }
//            }
//
//            if (light.type == GLTFKHRLightTypePoint || light.type == GLTFKHRLightTypeSpot) {
//                NSNumber *distanceValue = lightProperties[@"distance"];
//                if (distanceValue) {
//                    light.distance = [distanceValue floatValue];
//                }
//                NSNumber *constantAttenuationValue = lightProperties[@"constantAttenuation"];
//                if (constantAttenuationValue) {
//                    light.constantAttenuation = [constantAttenuationValue floatValue];
//                }
//                NSNumber *linearAttenuationValue = lightProperties[@"linearAttenuation"];
//                if (linearAttenuationValue) {
//                    light.linearAttenuation = [linearAttenuationValue floatValue];
//                }
//                NSNumber *quadraticAttenuationValue = lightProperties[@"quadraticAttenuation"];
//                if (quadraticAttenuationValue) {
//                    light.quadraticAttenuation = [quadraticAttenuationValue floatValue];
//                }
//            }
//
//            if (light.type == GLTFKHRLightTypeSpot) {
//                NSNumber *falloffAngleValue = lightProperties[@"falloffAngle"];
//                if (falloffAngleValue) {
//                    light.falloffAngle = [falloffAngleValue floatValue];
//                }
//                NSNumber *falloffExponentValue = lightProperties[@"falloffExponent"];
//                if (falloffExponentValue) {
//                    light.falloffExponent = [falloffExponentValue floatValue];
//                }
//            }
//        }
//        
//        lights[identifier] = light;
    }];
    
    _lights = [lights copy];
    return YES;
}

- (BOOL)loadMeshes:(NSArray *)meshesMap {
    if (meshesMap.count == 0) {
        _meshes = @[];
    }
    
    NSMutableArray *meshes = [NSMutableArray arrayWithCapacity:meshesMap.count];
    for (NSDictionary *properties in meshesMap) {
    
        GLTFMesh *mesh = [[GLTFMesh alloc] init];
        mesh.name = properties[@"name"];
        mesh.extensions = properties[@"extensions"];
        mesh.extras = properties[@"extras"];
        
        NSArray *submeshesProperties = properties[@"primitives"];
        NSMutableArray *submeshes = [NSMutableArray arrayWithCapacity:submeshesProperties.count];
        for (NSDictionary *submeshProperties in submeshesProperties) {
            GLTFSubmesh *submesh = [[GLTFSubmesh alloc] init];
            
            NSDictionary *submeshAttributes = submeshProperties[@"attributes"];
            
            NSMutableDictionary *attributeAccessors = [NSMutableDictionary dictionaryWithCapacity:submeshAttributes.count];
            [submeshAttributes enumerateKeysAndObjectsUsingBlock:^(NSString *attributeName, NSNumber *accessorIndexValue, BOOL *stop) {
                NSUInteger accessorIndex = accessorIndexValue.unsignedIntegerValue;
                if (accessorIndex < _accessors.count) {
                    GLTFAccessor *accessor = _accessors[accessorIndex];
                    attributeAccessors[attributeName] = accessor;
                }
            }];

            submesh.accessorsForAttributes = attributeAccessors;
            
            NSUInteger materialIndex = [submeshProperties[@"material"] intValue];
            if (materialIndex < _materials.count) {
                submesh.material = _materials[materialIndex];
            } else {
                submesh.material = _defaultMaterial;
            }
            
            NSUInteger indexAccessorIndex = [submeshProperties[@"indices"] intValue];
            if (indexAccessorIndex < _accessors.count) {
                GLTFAccessor *indexAccessor = _accessors[indexAccessorIndex];
                if (indexAccessor.componentType == GLTFTextureTypeUChar) {
                    // Fix up 8-bit indices, since they're unsupported in modern APIs
                    uint8_t *sourceIndices = indexAccessor.bufferView.buffer.contents + indexAccessor.offset + indexAccessor.bufferView.offset;
                    
                    id<GLTFBuffer> shortBuffer = [_bufferAllocator newBufferWithLength:indexAccessor.count * sizeof(uint16_t)];
                    uint16_t *destIndices = shortBuffer.contents;
                    for (int i = 0; i < indexAccessor.count; ++i) {
                        destIndices[i] = (uint16_t)sourceIndices[i];
                    }
                    _buffers = [_buffers arrayByAddingObject:shortBuffer];
                    
                    GLTFBufferView *shortBufferView = [GLTFBufferView new];
                    shortBufferView.buffer = shortBuffer;
                    shortBufferView.offset = 0;
                    shortBufferView.stride = 0;
                    _bufferViews = [_bufferViews arrayByAddingObject:shortBufferView];
                    
                    GLTFAccessor *shortAccessor = [GLTFAccessor new];
                    shortAccessor.bufferView = shortBufferView;
                    shortAccessor.componentType = GLTFDataTypeUShort;
                    shortAccessor.dimension = GLTFDataDimensionScalar;
                    shortAccessor.count = indexAccessor.count;
                    shortAccessor.offset = 0;
                    shortAccessor.valueRange = indexAccessor.valueRange;
                    _accessors = [_accessors arrayByAddingObject:shortAccessor];
                    
                    indexAccessor = shortAccessor;
                }
                submesh.indexAccessor = indexAccessor;
            }
            
            if (submeshProperties[@"mode"]) {
                submesh.primitiveType = (GLTFPrimitiveType)[submeshProperties[@"mode"] intValue];
            }
            
            [submeshes addObject:submesh];
        }
        
        mesh.submeshes = [submeshes copy];
        
        [meshes addObject:mesh];
    }
    
    _meshes = [meshes copy];
    return YES;
}


- (BOOL)loadMaterials:(NSArray *)materialsMap {
    if (materialsMap.count == 0) {
        _materials = @[];
        return YES;
    }
    
    NSMutableArray *materials = [NSMutableArray arrayWithCapacity:materialsMap.count];
    for (NSDictionary *properties in materialsMap) {
        GLTFMaterial *material = [[GLTFMaterial alloc] init];

        NSDictionary *pbrValuesMap = properties[@"pbrMetallicRoughness"];
        if (pbrValuesMap) {
            NSDictionary *baseColorTextureMap = pbrValuesMap[@"baseColorTexture"];
            NSNumber *baseColorTextureIndexValue = baseColorTextureMap[@"index"];
            if (baseColorTextureIndexValue != nil) {
                NSUInteger baseColorTextureIndex = baseColorTextureIndexValue.integerValue;
                if (baseColorTextureIndex < _textures.count) {
                    material.baseColorTexture = _textures[baseColorTextureIndex];
                }
            }
            NSNumber *baseColorTexCoordValue = baseColorTextureMap[@"texCoord"];
            if (baseColorTexCoordValue != nil) {
                material.baseColorTexCoord = baseColorTexCoordValue.integerValue;
            }

            NSArray *baseColorFactorComponents = pbrValuesMap[@"baseColorFactor"];
            if (baseColorFactorComponents.count == 4) {
                material.baseColorFactor = GLTFVectorFloat4FromArray(baseColorFactorComponents);
            }
            
            NSNumber *metallicFactor = pbrValuesMap[@"metallicFactor"];
            if (metallicFactor != nil) {
                material.metalnessFactor = metallicFactor.floatValue;
            }

            NSDictionary *metallicRoughnessTextureMap = pbrValuesMap[@"metallicRoughnessTexture"];
            NSNumber *metallicRoughnessTextureIndexValue = metallicRoughnessTextureMap[@"index"];
            if (metallicRoughnessTextureIndexValue != nil) {
                NSUInteger metallicRoughnessTextureIndex = metallicRoughnessTextureIndexValue.integerValue;
                if (metallicRoughnessTextureIndex < _textures.count) {
                    material.metallicRoughnessTexture = _textures[metallicRoughnessTextureIndex];
                }
            }

            NSNumber *metallicRoughnessTexCoordValue = metallicRoughnessTextureMap[@"texCoord"];
            if (metallicRoughnessTexCoordValue != nil) {
                material.metallicRoughnessTexCoord = metallicRoughnessTexCoordValue.integerValue;
            }
        }
        
        NSDictionary *normalTextureMap = properties[@"normalTexture"];
        if (normalTextureMap) {
            NSNumber *normalTextureIndexValue = normalTextureMap[@"index"];
            NSUInteger normalTextureIndex = normalTextureIndexValue.integerValue;
            if (normalTextureIndex < _textures.count) {
                material.normalTexture = _textures[normalTextureIndex];
            }
            NSNumber *normalTextureScaleValue = normalTextureMap[@"scale"];
            material.normalTextureScale = (normalTextureScaleValue != nil) ? normalTextureScaleValue.floatValue : 1.0;

            NSNumber *normalTexCoordValue = normalTextureMap[@"texCoord"];
            if (normalTexCoordValue != nil) {
                material.normalTexCoord = normalTexCoordValue.integerValue;
            }
        }

        NSDictionary *emissiveTextureMap = properties[@"emissiveTexture"];
        if (emissiveTextureMap) {
            NSNumber *emissiveTextureIndexValue = emissiveTextureMap[@"index"];
            NSUInteger emissiveTextureIndex = emissiveTextureIndexValue.integerValue;
            if (emissiveTextureIndex < _textures.count) {
                material.emissiveTexture = _textures[emissiveTextureIndex];
            }
            NSNumber *emissiveTexCoordValue = emissiveTextureMap[@"texCoord"];
            if (emissiveTexCoordValue != nil) {
                material.emissiveTexCoord = emissiveTexCoordValue.integerValue;
            }
        }
        
        NSArray *emissiveFactorArray = properties[@"emissiveFactor"];
        if (emissiveFactorArray.count == 3) {
            material.emissiveFactor = GLTFVectorFloat3FromArray(emissiveFactorArray);
        }
        
        NSNumber *doubleSidedValue = properties[@"doubleSided"];
        material.doubleSided = (doubleSidedValue == nil) || (doubleSidedValue != nil && doubleSidedValue.boolValue);
        
        NSString *alphaMode = properties[@"alphaMode"];
        if ([alphaMode isEqualToString:@"BLEND"]) {
            material.alphaMode = GLTFAlphaModeBlend;
        } else if ([alphaMode isEqualToString:@"MASK"]) {
            material.alphaMode = GLTFAlphaModeMask;
        } else {
            material.alphaMode = GLTFAlphaModeOpaque;
        }
        
        NSNumber *alphaCutoffValue = properties[@"alphaCutoff"];
        if (alphaCutoffValue != nil) {
            material.alphaCutoff = alphaCutoffValue.floatValue;
        }

        NSDictionary *occlusionTextureMap = properties[@"occlusionTexture"];
        if (occlusionTextureMap) {
            NSNumber *occlusionTextureIndexValue = occlusionTextureMap[@"index"];
            NSUInteger occlusionTextureIndex = occlusionTextureIndexValue.integerValue;
            if (occlusionTextureIndex < _textures.count) {
                material.occlusionTexture = _textures[occlusionTextureIndex];
            }
            NSNumber *occlusionTexCoordValue = occlusionTextureMap[@"texCoord"];
            if (occlusionTexCoordValue != nil) {
                material.occlusionTexCoord = occlusionTexCoordValue.integerValue;
            }
        }
        
        material.name = properties[@"name"];
        material.extensions = properties[@"extensions"];
        material.extras = properties[@"extras"];

        if (_usesPBRSpecularGlossiness) {
            NSDictionary *pbrSpecularGlossinessProperties = material.extensions[GLTFExtensionKHRMaterialsPBRSpecularGlossiness];
            if (pbrSpecularGlossinessProperties != nil) {
                NSDictionary *diffuseTextureMap = pbrSpecularGlossinessProperties[@"diffuseTexture"];
                if (diffuseTextureMap != nil) {
                    NSNumber *diffuseTextureIndexValue = diffuseTextureMap[@"index"];
                    if (diffuseTextureIndexValue != nil) {
                        NSUInteger diffuseTextureIndex = diffuseTextureIndexValue.integerValue;
                        if (diffuseTextureIndex < _textures.count) {
                            material.baseColorTexture = _textures[diffuseTextureIndex];
                        }
                    }
                    NSNumber *diffuseTexCoordValue = diffuseTextureMap[@"texCoord"];
                    if (diffuseTexCoordValue != nil) {
                        material.baseColorTexCoord = diffuseTexCoordValue.integerValue;
                    }
                }
                
                // TODO: Support specularGlossinessTexture

                NSArray *diffuseFactorComponents = pbrSpecularGlossinessProperties[@"diffuseFactor"];
                if (diffuseFactorComponents.count == 4) {
                    material.baseColorFactor = GLTFVectorFloat4FromArray(diffuseFactorComponents);
                }
                
                NSNumber *glossinessFactorValue = pbrSpecularGlossinessProperties[@"glossinessFactor"];
                material.glossinessFactor = (glossinessFactorValue != nil) ? glossinessFactorValue.floatValue : 0.0;

                NSArray *specularFactorComponents = pbrSpecularGlossinessProperties[@"specularFactor"];
                if (specularFactorComponents.count == 3) {
                    material.specularFactor = GLTFVectorFloat3FromArray(specularFactorComponents);
                }
            }
        }

        [materials addObject: material];
    }

    _materials = [materials copy];

    return YES;
}

- (BOOL)loadNodes:(NSArray *)nodesMap {
    if (nodesMap.count == 0) {
        _nodes = @[];
        return YES;
    }

    NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:nodesMap.count];
    for (NSDictionary *properties in nodesMap) {
        GLTFNode *node = [[GLTFNode alloc] init];

        NSString *cameraIdentifierString = properties[@"camera"];
        if (cameraIdentifierString) {
            NSUInteger cameraIndex = cameraIdentifierString.integerValue;
            if (cameraIndex < _cameras.count) {
                GLTFCamera *camera = _cameras[cameraIndex];
                node.camera = camera;
                camera.referencingNodes = [camera.referencingNodes arrayByAddingObject:node];
            }
        }

        // Copy array of indices for now; we fix this up later in another pass once all nodes are in memory.
        node.children = [properties[@"children"] copy];

        NSNumber *skinIndexValue = properties[@"skin"];
        if (skinIndexValue != nil) {
            NSUInteger skinIndex = skinIndexValue.integerValue;
            if (skinIndex < _skins.count) {
                node.skin = _skins[skinIndex];
            }
        }

        node.jointName = properties[@"jointName"];

        NSNumber *meshIndexValue = properties[@"mesh"];
        if (meshIndexValue != nil) {
            NSUInteger meshIndex = meshIndexValue.integerValue;
            if (meshIndex < _meshes.count) {
                node.mesh = _meshes[meshIndex];
            }
        }

        NSArray *matrixArray = properties[@"matrix"];
        if (matrixArray) {
            node.localTransform = GLTFMatrixFloat4x4FromArray(matrixArray);
        }

        NSArray *rotationArray = properties[@"rotation"];
        if (rotationArray) {
            node.rotationQuaternion = GLTFQuaternionFromArray(rotationArray);
        }

        NSArray *scaleArray = properties[@"scale"];
        if (scaleArray) {
            node.scale = GLTFVectorFloat3FromArray(scaleArray);
        }

        NSArray *translationArray = properties[@"translation"];
        if (translationArray) {
            node.translation = GLTFVectorFloat3FromArray(translationArray);
        }
        
        node.name = properties[@"name"];
        node.extensions = properties[@"extensions"];
        node.extras = properties[@"extras"];
        
        [nodes addObject: node];
    }

    _nodes = [nodes copy];
    
    return [self fixNodeRelationships];
}

- (BOOL)fixNodeRelationships {
    for (GLTFNode *node in _nodes) {
        NSArray *childIdentifiers = node.children;
        NSMutableArray *children = [NSMutableArray arrayWithCapacity:childIdentifiers.count];
        for (NSNumber *childIndexValue in childIdentifiers) {
            NSUInteger childIndex = childIndexValue.integerValue;
            if (childIndex < _nodes.count) {
                GLTFNode *child = _nodes[childIndex];
                child.parent = node;
                [children addObject:child];
            }
        }
        node.children = children;
    }
    
    for (GLTFSkin *skin in _skins) {
        NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:skin.jointNodes.count];
        for (NSInteger i = 0; i < skin.jointNodes.count; ++i) {
            NSNumber *jointIndexValue = (NSNumber *)skin.jointNodes[i];
            if (jointIndexValue != nil && jointIndexValue.intValue < _nodes.count) {
                [nodes addObject:_nodes[jointIndexValue.intValue]];
            }
        }
        skin.jointNodes = [nodes copy];

        NSNumber *skeletonIndexValue = (NSNumber *)skin.skeletonRootNode;
        if (skeletonIndexValue != nil && skeletonIndexValue.intValue < _nodes.count) {
            skin.skeletonRootNode = _nodes[skeletonIndexValue.intValue];
        }
    }
    
    return YES;
}

- (BOOL)loadAnimations:(NSArray *)animationsMap {
    if (animationsMap.count == 0) {
        _animations = @[];
        return YES;
    }

    NSArray *interpolationModes = @[ @"STEP", @"LINEAR", @"CUBICSPLINE", @"CATMULLROMSPLINE" ];

    NSMutableArray *animations = [NSMutableArray arrayWithCapacity:animationsMap.count];

    for (NSDictionary *properties in animationsMap) {
        GLTFAnimation *animation = [[GLTFAnimation alloc] init];
        
        NSArray *samplersProperties = properties[@"samplers"];
        NSMutableArray *samplers = [NSMutableArray arrayWithCapacity:samplersProperties.count];
        [samplersProperties enumerateObjectsUsingBlock:^(NSDictionary *samplerProperties, NSUInteger index, BOOL *stop) {
            GLTFAnimationSampler *sampler = [[GLTFAnimationSampler alloc] init];
            NSNumber *inputIndexValue = samplerProperties[@"input"];
            if (inputIndexValue && inputIndexValue.integerValue < _accessors.count) {
                sampler.inputAccessor = _accessors[inputIndexValue.integerValue];
            }
            NSNumber *outputIndexValue = samplerProperties[@"output"];
            if (outputIndexValue && outputIndexValue.integerValue < _accessors.count) {
                sampler.outputAccessor = _accessors[outputIndexValue.integerValue];
            }
            if (samplerProperties[@"interpolation"]) {
                sampler.interpolationMode = (GLTFInterpolationMode)[interpolationModes indexOfObject:samplerProperties[@"interpolation"]];
            }
            [samplers addObject:sampler];
        }];

        animation.samplers = [samplers copy];

        NSArray *channelsProperties = properties[@"channels"];
        NSMutableArray *channels = [NSMutableArray arrayWithCapacity:channelsProperties.count];
        [channelsProperties enumerateObjectsUsingBlock:^(NSDictionary *channelProperties, NSUInteger index, BOOL *stop) {
            GLTFAnimationChannel *channel = [GLTFAnimationChannel new];
            NSNumber *samplerIndexValue = channelProperties[@"sampler"];
            if (samplerIndexValue && samplerIndexValue.integerValue < samplers.count) {
                channel.sampler = samplers[samplerIndexValue.integerValue];
            }
            NSDictionary *targetProperties = channelProperties[@"target"];
            NSNumber *targetNodeIndexValue = targetProperties[@"node"];
            if (targetNodeIndexValue && targetNodeIndexValue.integerValue < _nodes.count) {
                channel.targetNode = _nodes[targetNodeIndexValue.integerValue];
            }
            channel.targetPath = targetProperties[@"path"];
            [channels addObject:channel];
        }];

        animation.channels = [channels copy];

        animation.name = properties[@"name"];
        animation.extensions = properties[@"extensions"];
        animation.extras = properties[@"extras"];
        
        [animations addObject: animation];
    }
    
    _animations = [animations copy];
    
    return YES;
}

- (BOOL)loadSkins:(NSArray *)skinsMap {
    if (skinsMap.count == 0) {
        _skins = @[];
        return YES;
    }
    
    NSMutableArray *skins = [NSMutableArray arrayWithCapacity:skinsMap.count];
    for (NSDictionary *properties in skinsMap) {
        GLTFSkin *skin = [[GLTFSkin alloc] init];
        
        NSNumber *inverseBindMatricesAccessorIndexValue = properties[@"inverseBindMatrices"];
        if (inverseBindMatricesAccessorIndexValue != nil) {
            NSInteger inverseBindMatricesAccessorIndex = inverseBindMatricesAccessorIndexValue.integerValue;
            if (inverseBindMatricesAccessorIndex < _accessors.count) {
                skin.inverseBindMatricesAccessor = _accessors[inverseBindMatricesAccessorIndex];
            }
        }
        
        NSArray *jointIndices = properties[@"joints"];
        if (jointIndices.count > 0) {
            skin.jointNodes = [jointIndices copy];
        }
        
        NSNumber *skeletonIndexValue = properties[@"skeleton"];
        if (skeletonIndexValue != nil) {
            skin.skeletonRootNode = (id)skeletonIndexValue;
        }
        
        skin.name = properties[@"name"];
        skin.extensions = properties[@"extensions"];
        skin.extras = properties[@"extras"];
        
        [skins addObject:skin];
    }
    
    _skins = [skins copy];
    
    return YES;
}

- (BOOL)loadScenes:(NSArray *)scenesMap {
    if (scenesMap.count == 0) {
        _scenes = @[];
        return YES;
    }

    NSMutableArray *scenes = [NSMutableArray arrayWithCapacity:scenesMap.count];
    for (NSDictionary *properties in scenesMap) {
        GLTFScene *scene = [[GLTFScene alloc] init];

        NSArray *rootNodeIndices = properties[@"nodes"];
        NSMutableArray *rootNodes = [NSMutableArray arrayWithCapacity:rootNodeIndices.count];
        for (NSNumber *nodeIndexValue in rootNodeIndices) {
            NSUInteger nodeIndex = nodeIndexValue.integerValue;
            if (nodeIndex < _nodes.count) {
                GLTFNode *node = _nodes[nodeIndex];
                [rootNodes addObject:node];
            }
        }
        scene.nodes = [rootNodes copy];

        scene.name = properties[@"name"];
        scene.extensions = properties[@"extensions"];
        scene.extras = properties[@"extras"];

        [scenes addObject:scene];
    }

    _scenes = [scenes copy];

    return YES;
}

- (BOOL)loadDefaultScene:(NSNumber *)defaultSceneIndexValue
{
    if (defaultSceneIndexValue != nil) {
        NSUInteger defaultSceneIndex = defaultSceneIndexValue.integerValue;
        if (defaultSceneIndex < _scenes.count) {
            _defaultScene = _scenes[defaultSceneIndex];
        }
    } else {
        _defaultScene = _scenes.firstObject;
    }

    return YES;
}

@end

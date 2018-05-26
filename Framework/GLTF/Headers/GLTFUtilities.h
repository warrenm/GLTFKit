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

#import "GLTFEnums.h"

@import Foundation;
@import simd;

NS_ASSUME_NONNULL_BEGIN

typedef struct __attribute__((packed)) {
    float x, y, z;
} GLTFVector3;

typedef struct __attribute__((packed)) {
    float x, y, z, w;
} GLTFVector4;

typedef struct __attribute__((packed)) {
    GLTFVector4 columns[4];
} GLTFMatrix4;

typedef simd_quatf GLTFQuaternion;

typedef struct {
    simd_float3 minPoint;
    simd_float3 maxPoint;
} GLTFBoundingBox;

typedef struct {
    simd_float3 center;
    float radius;
} GLTFBoundingSphere;

extern bool GLTFBoundingBoxIsEmpty(GLTFBoundingBox b);

extern GLTFBoundingBox *GLTFBoundingBoxUnion(GLTFBoundingBox *a, GLTFBoundingBox b);

extern void GLTFBoundingBoxTransform(GLTFBoundingBox *b, simd_float4x4 transform);

extern GLTFBoundingSphere GLTFBoundingSphereFromBox(const GLTFBoundingBox b);

extern GLTFQuaternion GLTFQuaternionFromEulerAngles(float pitch, float yaw, float roll);

extern simd_float4x4 GLTFMatrixFromUniformScale(float);

extern simd_float4x4 GLTFMatrixFromScale(simd_float3);

extern simd_float4x4 GLTFMatrixFromTranslation(simd_float3);

extern simd_float4x4 GLTFRotationMatrixFromAxisAngle(simd_float3 axis, float angle);

extern simd_float3x3 GLTFMatrixUpperLeft3x3(simd_float4x4);

extern simd_float4x4 GLTFNormalMatrixFromModelMatrix(simd_float4x4);

extern simd_float4x4 GLTFPerspectiveProjectionMatrixAspectFovRH(const float fovY, const float aspect, const float nearZ, const float farZ);

extern simd_float3 GLTFAxisX;
extern simd_float3 GLTFAxisY;
extern simd_float3 GLTFAxisZ;

extern GLTFDataDimension GLTFDataDimensionForName(NSString *name);

extern size_t GLTFSizeOfDataType(GLTFDataType type);

extern size_t GLTFSizeOfComponentTypeWithDimension(GLTFDataType baseType, GLTFDataDimension dimension);

extern NSInteger GLTFComponentCountForDimension(GLTFDataDimension dimension);

extern BOOL GLTFDataTypeComponentsAreFloats(GLTFDataType type);

extern simd_float2 GLTFVectorFloat2FromArray(NSArray *array);

extern simd_float3 GLTFVectorFloat3FromArray(NSArray *array);

extern simd_float4 GLTFVectorFloat4FromArray(NSArray *array);

extern GLTFQuaternion GLTFQuaternionFromArray(NSArray *array);

extern simd_float4x4 GLTFMatrixFloat4x4FromArray(NSArray *array);

NS_ASSUME_NONNULL_END

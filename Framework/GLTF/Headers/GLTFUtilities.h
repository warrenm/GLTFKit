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

#import "GLTFEnums.h"

@import Foundation;
@import simd;

typedef struct {
    vector_float3 minPoint;
    vector_float3 maxPoint;
} GLTFBoundingBox;

typedef struct {
    vector_float3 center;
    float radius;
} GLTFBoundingSphere;

extern bool GLTFBoundingBoxIsEmpty(GLTFBoundingBox b);

extern GLTFBoundingBox *GLTFBoundingBoxUnion(GLTFBoundingBox *a, GLTFBoundingBox b);

extern void GLTFBoundingBoxTransform(GLTFBoundingBox *b, matrix_float4x4 transform);

extern GLTFBoundingSphere GLTFBoundingSphereFromBox(const GLTFBoundingBox b);

extern void GLTFAxisAngleFromQuaternion(vector_float4 q, vector_float3 *outAxis, float *outAngle);

extern simd_float4 GLTFQuaternionMultiply(vector_float4 q, vector_float4 r);

extern vector_float4 GLTFQuaternionFromEulerAngles(float pitch, float yaw, float roll);

extern matrix_float4x4 GLTFRotationMatrixFromQuaternion(vector_float4 q);

extern matrix_float4x4 GLTFMatrixFromUniformScale(float s);

extern matrix_float4x4 GLTFMatrixFromTranslation(float x, float y, float z);

extern matrix_float4x4 GLTFRotationMatrixFromAxisAngle(vector_float3 axis, float angle);

extern vector_float3 GLTFAxisX;
extern vector_float3 GLTFAxisY;
extern vector_float3 GLTFAxisZ;

extern GLTFDataDimension GLTFDataDimensionForName(NSString *name);

extern size_t GLTFSizeOfDataType(GLTFDataType type);

extern size_t GLTFSizeOfComponentTypeWithDimension(GLTFDataType baseType, GLTFDataDimension dimension);

extern vector_float2 GLTFVectorFloat2FromArray(NSArray *array);

extern vector_float3 GLTFVectorFloat3FromArray(NSArray *array);

extern vector_float4 GLTFVectorFloat4FromArray(NSArray *array);

extern matrix_float4x4 GLTFMatrixFloat4x4FromArray(NSArray *array);

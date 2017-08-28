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

#import "GLTFObject.h"

@import simd;

typedef NS_ENUM(NSInteger, GLTFKHRLightType) {
    GLTFKHRLightTypeAmbient,
    GLTFKHRLightTypeDirectional,
    GLTFKHRLightTypePoint,
    GLTFKHRLightTypeSpot,
};

@interface GLTFKHRLight : GLTFObject

@property (nonatomic, assign) GLTFKHRLightType type;

@property (nonatomic, assign) vector_float4 color;

@property (nonatomic, assign) vector_float4 direction;

/// Distance, in world units, over which the light affects objects in the scene.
/// A value of zero indicates infinite distance.
@property (nonatomic, assign) float distance;

// Attenuation properties only apply to point and spot lights
@property (nonatomic, assign) float constantAttenuation;
@property (nonatomic, assign) float linearAttenuation;
@property (nonatomic, assign) float quadraticAttenuation;

@property (nonatomic, assign) float falloffAngle;
@property (nonatomic, assign) float falloffExponent;

@end

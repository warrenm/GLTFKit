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

#import <GLTF/GLTF.h>

@import Foundation;
@import Metal;

NS_ASSUME_NONNULL_BEGIN

@interface GLTFMTLLightingEnvironment : NSObject

@property (nonatomic, retain) id<MTLTexture> environmentCube;
@property (nonatomic, retain) id<MTLTexture> diffuseCube;
@property (nonatomic, retain) id<MTLTexture> specularCube;
@property (nonatomic, retain) id<MTLTexture> brdfLUT;
@property (nonatomic, assign) float intensity;
@property (nonatomic, readonly, assign) int specularMipLevelCount;

- (instancetype)initWithContentsOfURL:(NSURL *)environmentURL device:(id<MTLDevice>)device error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

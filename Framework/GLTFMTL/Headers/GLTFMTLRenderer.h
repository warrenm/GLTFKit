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

#define GLTFMTLRendererMaxInflightFrames 3

@class GLTFMTLLightingEnvironment;

@interface GLTFMTLRenderer : NSObject

@property (nonatomic, assign) CGSize drawableSize;

@property (nonatomic, assign) simd_float4x4 viewMatrix;
@property (nonatomic, assign) simd_float4x4 projectionMatrix;

@property (nonatomic, assign) int sampleCount;
@property (nonatomic, assign) MTLPixelFormat colorPixelFormat;
@property (nonatomic, assign) MTLPixelFormat depthStencilPixelFormat;

@property (nonatomic, strong) GLTFMTLLightingEnvironment * _Nullable lightingEnvironment;

- (instancetype)initWithDevice:(id<MTLDevice>)device;

- (void)renderScene:(GLTFScene *)scene
      commandBuffer:(id<MTLCommandBuffer>)commandBuffer
     commandEncoder:(id<MTLRenderCommandEncoder>)renderEncoder;

- (void)signalFrameCompletion;

@end

NS_ASSUME_NONNULL_END

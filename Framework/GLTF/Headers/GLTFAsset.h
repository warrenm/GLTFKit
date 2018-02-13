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

@import Foundation;

#import "GLTFObject.h"
#import "GLTFEnums.h"

NS_ASSUME_NONNULL_BEGIN

@class GLTFScene, GLTFCamera, GLTFAnimation;
@class GLTFKHRLight;
@protocol GLTFBufferAllocator;

@interface GLTFAsset : NSObject

@property (nonatomic, readonly, copy) NSArray<GLTFScene *> *scenes;
@property (nonatomic, readonly) GLTFScene * _Nullable defaultScene;

@property (nonatomic, readonly, copy) NSArray<GLTFAnimation *> *animations;

@property (nonatomic, readonly, copy) NSArray<GLTFKHRLight *> *lights;

@property (nonatomic, readonly, copy) NSArray<GLTFCamera *> *cameras;

@property (nonatomic, copy) NSString * _Nullable generator;
@property (nonatomic, copy) NSString * _Nullable copyright;
@property (nonatomic, copy) NSString * _Nullable formatVersion;

@property (nonatomic, copy) NSArray<NSString *> *extensionsUsed;

- (instancetype)initWithURL:(NSURL *)url bufferAllocator:(id<GLTFBufferAllocator>)bufferAllocator;

@end

NS_ASSUME_NONNULL_END

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

#import "GLTFMTLTextureLoader.h"
@import MetalKit;

NSString *const GLTFMTLTextureLoaderOptionGenerateMipmaps = @"GLTFMTLTextureLoaderOptionGenerateMipmaps";
NSString *const GLTFMTLTextureLoaderOptionUsageFlags = @"GLTFMTLTextureLoaderOptionUsageFlags";

static inline void storeAsF16(float value, uint16_t *pointer) { *(__fp16 *)pointer = value; }

static void ConvertRGBF32ToRGBAF16(float *src, uint16_t *dst, size_t pixelCount) {
    for (int i = 0; i < pixelCount; ++i) {
        storeAsF16(src[i * 3 + 0], dst + (i * 4) + 0);
        storeAsF16(src[i * 3 + 1], dst + (i * 4) + 1);
        storeAsF16(src[i * 3 + 2], dst + (i * 4) + 2);
        storeAsF16(1.0, dst + (i * 4) + 3);
    }
}

@interface GLTFMTLTextureLoader ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) MTKTextureLoader *internalLoader;
@end

@implementation GLTFMTLTextureLoader

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        _commandQueue = [device newCommandQueue];
        _internalLoader = [[MTKTextureLoader alloc] initWithDevice:device];
    }
    return self;
}

- (id<MTLTexture>)newTextureWithContentsOfURL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
    if (url == nil) {
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:url];
    
    return [self newTextureWithData:data options:options error:error];
}

- (id<MTLTexture>)newTextureWithData:(NSData *)data options:(NSDictionary *)options error:(NSError **)error {
    if (data == nil) {
        return nil;
    }
    
    NSDictionary *sourceOptions = @{ (__bridge NSString *)kCGImageSourceShouldCache : @YES,
                                     (__bridge NSString *)kCGImageSourceShouldAllowFloat : @YES };
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);

    CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0, (__bridge CFDictionaryRef)sourceOptions);

    id<MTLTexture> texture = [self newTextureWithCGImage:image options:options error:error];
    
    CGImageRelease(image);
    if (imageSource != NULL) {
        CFRelease(imageSource);
    }
    
    return texture;
}

- (id<MTLTexture> _Nullable)newTextureWithCGImage:(CGImageRef)image options:(NSDictionary * _Nullable)options error:(NSError **)error {
    if (image == NULL) {
        return nil;
    }
    
    NSNumber *mipmapOption = options[GLTFMTLTextureLoaderOptionGenerateMipmaps];
    BOOL mipmapped = (mipmapOption != nil) ? mipmapOption.boolValue : NO;
    
    size_t bpc = CGImageGetBitsPerComponent(image);
    size_t bpp = CGImageGetBitsPerPixel(image);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);
    MTLPixelFormat pixelFormat = MTLPixelFormatRGBA8Unorm;
    if ((bitmapInfo & kCGBitmapFloatComponents) != 0) {
        pixelFormat = MTLPixelFormatRGBA16Float;
    }
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:mipmapped];
    
    NSNumber *usageOption = options[GLTFMTLTextureLoaderOptionUsageFlags];
    descriptor.usage = (usageOption != nil) ? usageOption.integerValue : MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    
    if (pixelFormat == MTLPixelFormatRGBA16Float) {
        NSAssert(bpc == 32 && bpp == 96, @"GLTFMTLTextureLoader can currently only handle floating-point images with bpc == 32 and bpp == 96");

        CGDataProviderRef dataProvider = CGImageGetDataProvider(image);
        NSData *srcData = (__bridge NSData *)CGDataProviderCopyData(dataProvider);
        float *srcPixels = (float *)srcData.bytes;
        uint16_t *dstPixels = malloc(sizeof(uint16_t) * 4 * width * height);

        ConvertRGBF32ToRGBAF16(srcPixels, dstPixels, width * height);

        [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:dstPixels
                   bytesPerRow:sizeof(uint16_t) * 4 * width];
        free(dstPixels);
        CFRelease((__bridge CFDataRef)srcData);
    } else {
        CGColorSpaceRef sourceColorSpace = CGImageGetColorSpace(image);
        CGColorSpaceModel sourceColorModel = CGColorSpaceGetModel(sourceColorSpace);
        if (sourceColorModel != kCGColorSpaceModelRGB) {
            // TODO: Remove this once the indexed image decode bug in MetalKit is fixed.
            CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            size_t Bpr = width * 4;
            CGContextRef context = CGBitmapContextCreate(nil, width, height, bpc, Bpr, colorSpace, kCGImageAlphaPremultipliedLast);
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
            image = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
        }
        
        NSDictionary *loaderOptions = @{ MTKTextureLoaderOptionOrigin : MTKTextureLoaderOriginTopLeft,
                                         MTKTextureLoaderOptionSRGB : @(NO),
                                         MTKTextureLoaderOptionGenerateMipmaps : @(mipmapped) };
        texture = [self.internalLoader newTextureWithCGImage:image options:loaderOptions error:error];
    }
    
    if (texture != nil && mipmapped) {
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> commandEncoder = [commandBuffer blitCommandEncoder];
        [commandEncoder generateMipmapsForTexture:texture];
        [commandEncoder endEncoding];
        [commandBuffer commit];
//        [commandBuffer waitUntilCompleted];
    }
    
    return texture;
}

@end

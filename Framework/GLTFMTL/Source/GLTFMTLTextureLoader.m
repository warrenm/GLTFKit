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

#import "GLTFMTLTextureLoader.h"
#import "stb_image.h"
@import Accelerate;

NSString *const GLTFMTLTextureLoaderOptionGenerateMipmaps = @"GLTFMTLTextureLoaderOptionGenerateMipmaps";
NSString *const GLTFMTLTextureLoaderOptionUsageFlags = @"GLTFMTLTextureLoaderOptionUsageFlags";

__fp16 *GLTFMTLConvertImageToRGBA16F(CGImageRef image)
{
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    __fp16 *dstPixels = malloc(sizeof(__fp16) * 4 * width * height);
    vImage_Buffer dstBuffer = {
        .data = dstPixels,
        .height = height,
        .width = width,
        .rowBytes = sizeof(__fp16) * 4 * width
    };

    vImage_CGImageFormat srcFormat = {
        .bitsPerComponent = (uint32_t)CGImageGetBitsPerComponent(image),
        .bitsPerPixel = (uint32_t)CGImageGetBitsPerPixel(image),
        .colorSpace = CGImageGetColorSpace(image),
        .bitmapInfo = CGImageGetBitmapInfo(image)
    };

    vImage_CGImageFormat dstFormat = {
        .bitsPerComponent = sizeof(__fp16) * 8,
        .bitsPerPixel = sizeof(__fp16) * 8 * 4,
        .colorSpace = CGImageGetColorSpace(image),
        .bitmapInfo = kCGBitmapByteOrder16Little | kCGBitmapFloatComponents | kCGImageAlphaPremultipliedLast
    };

    vImage_Error error = kvImageNoError;
    CGFloat background[] = { 0, 0, 0, 1 };
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&srcFormat,
                                                                           &dstFormat,
                                                                           background,
                                                                           kvImageNoFlags,
                                                                           &error);

    CGDataProviderRef dataProvider = CGImageGetDataProvider(image);
    CFDataRef srcData = CGDataProviderCopyData(dataProvider);

    const void *srcPixels = CFDataGetBytePtr(srcData);

    vImage_Buffer srcBuffer = {
        .data = (void *)srcPixels,
        .height = height,
        .width = width,
        .rowBytes = sizeof(float) * 3 * width
    };

    vImageConvert_AnyToAny(converter, &srcBuffer, &dstBuffer, NULL, kvImageNoFlags);

    vImageConverter_Release(converter);
    CFRelease(srcData);

    return dstPixels;
}

@interface GLTFMTLTextureLoader ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation GLTFMTLTextureLoader

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
        _commandQueue = [device newCommandQueue];
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
    
    int width = 0;
    int height = 0;
    int fileChannels = 4;
    int targetChannels = 4;
    unsigned char *bytes = stbi_load_from_memory(data.bytes, (int)data.length, &width, &height, &fileChannels, targetChannels);
    
    MTLPixelFormat pixelFormat = MTLPixelFormatRGBA8Unorm;
    
    NSNumber *mipmapOption = options[GLTFMTLTextureLoaderOptionGenerateMipmaps];
    BOOL mipmapped = (mipmapOption != nil) ? mipmapOption.boolValue : NO;

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:mipmapped];

    id<MTLTexture> texture = [self newTextureWithBytes:bytes descriptor:descriptor options:options error:error];
    
    stbi_image_free(bytes);

    return texture;
}

- (id<MTLTexture> _Nullable)newTextureWithBytes:(unsigned char *)bytes
                                     descriptor:(MTLTextureDescriptor *)descriptor
                                        options:(NSDictionary * _Nullable)options
                                          error:(NSError **)error
{
    NSNumber *usageOption = options[GLTFMTLTextureLoaderOptionUsageFlags];
    descriptor.usage = (usageOption != nil) ? usageOption.integerValue : MTLTextureUsageShaderRead;
    
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    
    [texture replaceRegion:MTLRegionMake2D(0, 0, texture.width, texture.height)
               mipmapLevel:0
                 withBytes:bytes
               bytesPerRow:sizeof(unsigned char) * 4 * texture.width];

    if (texture != nil && (texture.mipmapLevelCount > 1)) {
        id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> commandEncoder = [commandBuffer blitCommandEncoder];
        [commandEncoder generateMipmapsForTexture:texture];
        [commandEncoder endEncoding];
        [commandBuffer commit];
    }
    
    return texture;
}

@end

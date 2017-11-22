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

// This loader is inspired by Bruce Walter's RGBE loader (cf. http://www.graphics.cornell.edu/online/formats/rgbe/ )

typedef NS_ENUM(NSInteger, GLTFImageLoaderHeaderField) {
    GLTFImageLoaderHeaderBitProgramType = 1 << 0,
    GLTFImageLoaderHeaderBitGamma       = 1 << 1,
    GLTFImageLoaderHeaderBitExposure    = 1 << 2,
    GLTFImageLoaderHeaderBitFormat      = 1 << 3,
};

typedef NSInteger GLTFImageLoaderHeaderFieldMask;

typedef NS_ENUM(NSInteger, GLTFImageLoaderError) {
    GLTFImageLoaderErrorRead   = -1,
    GLTFImageLoaderErrorWrite  = -2,
    GLTFImageLoaderErrorFormat = -3,
    GLTFImageLoaderErrorMemory = -4,
};

typedef struct {
    GLTFImageLoaderHeaderFieldMask validFieldBits;
    char programType[16];
    float gamma;
    float exposure;
    int width;
    int height;
    size_t dataOffset;
} GLTFRGBEHeader;

static inline void GLTFRGBFromRGBE(const uint8_t *rgbe, float *rgb)
{
    int e = (int)rgbe[3] - (128 + 8);
    
    if (e != 0) {
        float m = ldexp(1.0, e);
        rgb[0] = rgbe[0] * m;
        rgb[1] = rgbe[1] * m;
        rgb[2] = rgbe[2] * m;
        rgb[3] = 1.0;
    }
    else {
        rgb[0] = 0;
        rgb[1] = 0;
        rgb[2] = 0;
        rgb[3] = 1.0;
    }
}

@interface GLTFMTLTextureLoader ()
@property (nonatomic, strong) id<MTLDevice> device;
@end

@implementation GLTFMTLTextureLoader

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if ((self = [super init])) {
        _device = device;
    }
    return self;
}

- (id<MTLTexture>)hdrTextureWithContentsOfURL:(NSURL *)url {
    NSData *data = [NSData dataWithContentsOfURL:url];
    
    if (url == nil || data == nil) {
        return nil;
    }
    
    id<MTLTexture> texture = nil;
    
    const uint8_t *bytes = [data bytes];
    
    GLTFRGBEHeader header;
    NSError *error = nil;
    if ([self readRGBEHeader:&header fromBuffer:bytes error:&error]) {
        float *pixelData = malloc(sizeof(float) * 4 * header.width * header.height);
        if ([self readPixelsRLE:pixelData fromBuffer:bytes header:header error:&error]) {
            MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                                  width:header.width
                                                                                                 height:header.height
                                                                                              mipmapped:NO];
            texture = [self.device newTextureWithDescriptor:descriptor];
            MTLRegion region = MTLRegionMake2D(0, 0, header.width, header.height);
            [texture replaceRegion:region mipmapLevel:0 withBytes:pixelData bytesPerRow:header.width * sizeof(float) * 4];
        }
        free(pixelData);
    }

    return texture;
}

- (NSError *)errorWithCode:(GLTFImageLoaderError)code message:(NSString *)message {
    return [NSError errorWithDomain:@"org.khronos.gltf" code:code userInfo: @{ NSLocalizedDescriptionKey : message }];
}

- (BOOL)readRGBEHeader:(GLTFRGBEHeader *)header fromBuffer:(const uint8_t *)buffer error:(NSError **)error {
    header->validFieldBits = 0;
    header->programType[0] = '\0';
    header->gamma = 1;
    header->exposure = 1;
    
    const uint8_t *originalBuffer = buffer;

    if (buffer[0] != '#' || buffer[1] != '?') {
        if (*error != nil) {
            *error = [self errorWithCode:GLTFImageLoaderErrorFormat message:@"Incorrect RADIANCE file magic cookie"];
            return NO;
        }
    }
    
    header->validFieldBits |= GLTFImageLoaderHeaderBitProgramType;
    buffer += 2;
    char *programName = &header->programType[0];
    while (buffer[0] != '\n') {
        *programName++ = *buffer;
        buffer += 1;
    }
    *programName = '\0';
    buffer += 1;

    float value = 0;
    while (1) {
        if (buffer[0] == '\0' || buffer[0] == '\n') {
            break;
        } else if (strcmp((const char *)buffer, "FORMAT=32-bit_rle_rgbe") == 0) {
            header->validFieldBits |= GLTFImageLoaderHeaderBitFormat;
        } else if (sscanf((const char *)buffer, "GAMMA=%g", &value) == 1) {
            header->gamma = value;
            header->validFieldBits |= GLTFImageLoaderHeaderBitGamma;
        } else if (sscanf((const char *)buffer, "EXPOSURE=%g", &value) == 1) {
            header->exposure = value;
            header->validFieldBits |= GLTFImageLoaderHeaderBitExposure;
        }
        
        while (buffer[0] != '\n') {
            buffer += 1;
        }
        buffer += 1;
    }
    
    if (buffer[0] != '\n') {
        if (error != nil) {
            *error = [self errorWithCode:GLTFImageLoaderErrorFormat message:@"RADIANCE file did not have required newline after format specifier"];
        }
        return NO;
    } else {
        buffer += 1;
    }
    
    if (sscanf((const char *)buffer, "-Y %d +X %d", &header->height, &header->width) < 2) {
        if (error != nil) {
            *error = [self errorWithCode:GLTFImageLoaderErrorFormat message:@"RADIANCE file did not have supported dimension specifier"];
        }
        return NO;
    } else {
        while (*buffer != '\n') {
            buffer += 1;
        }
        buffer += 1;
    }
    
    header->dataOffset = buffer - originalBuffer;

    return YES;
}

- (BOOL)readPixels:(float *)pixelData fromBuffer:(const uint8_t *)buffer header:(GLTFRGBEHeader)header pixelCount:(int)pixelCount error:(NSError **)error {
    uint8_t rgbe[4];
    buffer += header.dataOffset;
    while (pixelCount > 0) {
        memcpy(rgbe, buffer, 4);
        GLTFRGBFromRGBE(rgbe, pixelData);
        buffer += 4;
        pixelData += 4;
        --pixelCount;
    }
    return YES;
}

- (BOOL)readPixelsRLE:(float *)pixelData fromBuffer:(const uint8_t *)buffer header:(GLTFRGBEHeader)header error:(NSError **)error {
    if (header.width < 8 || header.width > INT16_MAX) {
        return [self readPixels:pixelData fromBuffer:buffer header:header pixelCount:(header.width * header.height) error:error];
    }
    
    int pixelCount = header.width * header.height;
    buffer += header.dataOffset;
    uint8_t *scanline = malloc(header.width * 4);
    
    for (int r = 0; r < header.height; ++r) {
        uint8_t rgbe[4];
        memcpy(rgbe, buffer, 4);
        buffer += 4;
        if (rgbe[0] != 2 || rgbe[1] != 2 || rgbe[2] & 0x80) {
            GLTFRGBFromRGBE(buffer, pixelData);
            pixelData += 3;
            buffer += 3;
            pixelCount -= 1;
            free(scanline);
            return [self readPixels:pixelData fromBuffer:buffer header:header pixelCount:pixelCount error:error];
        }
        
        if ((rgbe[2] << 8 | rgbe[3]) != header.width) {
            free(scanline);
            if (error != nil) {
                *error = [self errorWithCode:GLTFImageLoaderErrorRead message:@"Encountered invalid scanline width when parsing RADIANCE file"];
            }
            return NO;
        }

        for (int i = 0; i < 4; ++i) {
            int p = 0;
            while (p < header.width) {
                uint8_t rlb = buffer[0];
                if (rlb > 128) {
                    uint8_t value = buffer[1];
                    int runLength = rlb - 128;
                    for (int b = 0; b < runLength; ++b) {
                        scanline[i * header.width + p] = value;
                        ++p;
                    }
                    buffer += 2;
                } else {
                    uint8_t value = buffer[1];
                    scanline[i * header.width + p] = value;
                    ++p;
                    buffer += 2;
                    --rlb;
                    while(rlb > 0) {
                        scanline[i * header.width + p] = buffer[0];
                        ++p;
                        ++buffer;
                        --rlb;
                    }
                }
            }
        }

        for (int p = 0; p < header.width; ++p) {
            uint8_t rgbe[] = {
                scanline[header.width * 0 + p],
                scanline[header.width * 1 + p],
                scanline[header.width * 2 + p],
                scanline[header.width * 3 + p],
            };
            GLTFRGBFromRGBE(&rgbe[0], pixelData);
            pixelData += 4;
            pixelCount -= header.width;
        }
    }
    
    free(scanline);
    return YES;
}

@end

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

#import "GLTFImage.h"

@implementation GLTFImage

+ (CGImageRef)newImageForDataURI:(NSString *)uriData {
    NSString *pngHeader = @"data:image/png;base64,";
    if ([uriData hasPrefix:pngHeader]) {
        NSString *encodedImageData = [uriData substringFromIndex:pngHeader.length];
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:encodedImageData
                                                                options:NSDataBase64DecodingIgnoreUnknownCharacters];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)imageData);
        
        CGImageRef image = CGImageCreateWithPNGDataProvider(provider, NULL, false, kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);
        return image;
    }
    
    NSString *jpegHeader = @"data:image/jpeg;base64,";
    if ([uriData hasPrefix:jpegHeader]) {
        NSString *encodedImageData = [uriData substringFromIndex:jpegHeader.length];
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:encodedImageData
                                                                options:NSDataBase64DecodingIgnoreUnknownCharacters];
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)imageData);
        
        CGImageRef image = CGImageCreateWithJPEGDataProvider(provider, NULL, false, kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);
        return image;
    }
    
    // TODO: Support for GIF, BMP, etc.
    
    return nil;
}

- (void)dealloc {
    CGImageRelease(_cgImage);
}

@end

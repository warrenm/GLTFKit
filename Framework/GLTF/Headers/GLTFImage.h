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
#import "GLTFBufferView.h"

@import Foundation;
@import CoreGraphics;

@interface GLTFImage : GLTFObject

+ (CGImageRef)newImageForDataURI:(NSString *)uriData;

/// A reference to a buffer view containing image data, if url is nil
@property (nonatomic, strong) GLTFBufferView *bufferView;

/// The MIME type of the data contained in this image's buffer view
@property (nonatomic, copy) NSString *mimeType;

/// A file URL, if the URI was not a decodable data-uri; otherwise nil
@property (nonatomic, copy) NSURL *url;

/// An image, if the URI was a decodable data-uri; otherwise nil
@property (nonatomic, assign) CGImageRef cgImage;

@end

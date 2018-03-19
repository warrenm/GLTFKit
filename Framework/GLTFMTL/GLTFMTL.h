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

#import "TargetConditionals.h"

#if TARGET_OS_OSX
@import Cocoa;
#elif TARGET_OS_IOS
@import UIKit;
#endif

//! Project version number for GLTFMTL.
FOUNDATION_EXPORT double GLTFMTLVersionNumber;

//! Project version string for GLTFMTL.
FOUNDATION_EXPORT const unsigned char GLTFMTLVersionString[];

#import <GLTFMTL/GLTFMTLBufferAllocator.h>
#import <GLTFMTL/GLTFMTLTextureLoader.h>
#import <GLTFMTL/GLTFMTLLightingEnvironment.h>
#import <GLTFMTL/GLTFMTLRenderer.h>
#import <GLTFMTL/GLTFMTLShaderBuilder.h>
#import <GLTFMTL/GLTFMTLUtilities.h>

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

#include "TargetConditionals.h"

#if TARGET_OS_OSX
@import Cocoa;
#elif TARGET_OS_IOS
@import UIKit;
#endif

//! Project version number for GLTF.
FOUNDATION_EXPORT double GLTFVersionNumber;

//! Project version string for GLTF.
FOUNDATION_EXPORT const unsigned char GLTFVersionString[];

#import <GLTF/GLTFAccessor.h>
#import <GLTF/GLTFAnimation.h>
#import <GLTF/GLTFAsset.h>
#import <GLTF/GLTFBinaryChunk.h>
#import <GLTF/GLTFBuffer.h>
#import <GLTF/GLTFBufferAllocator.h>
#import <GLTF/GLTFBufferView.h>
#import <GLTF/GLTFCamera.h>
#import <GLTF/GLTFDefaultBufferAllocator.h>
#import <GLTF/GLTFEnums.h>
#import <GLTF/GLTFExtensionNames.h>
#import <GLTF/GLTFImage.h>
#import <GLTF/GLTFKHRLight.h>
#import <GLTF/GLTFMaterial.h>
#import <GLTF/GLTFMesh.h>
#import <GLTF/GLTFNode.h>
#import <GLTF/GLTFObject.h>
#import <GLTF/GLTFScene.h>
#import <GLTF/GLTFSkin.h>
#import <GLTF/GLTFTexture.h>
#import <GLTF/GLTFTextureSampler.h>
#import <GLTF/GLTFVertexDescriptor.h>
#import <GLTF/GLTFUtilities.h>

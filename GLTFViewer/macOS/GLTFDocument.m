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

#import "GLTFDocument.h"
#import "GLTFViewerViewController.h"

#import <GLTFMTL/GLTFMTL.h>

@interface GLTFDocument()

@property (nonatomic, strong) GLTFViewerViewController *viewerController;

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;
@end

@implementation GLTFDocument

- (void)makeWindowControllers {
    _device = MTLCreateSystemDefaultDevice();
    
    NSRect contentsRect = NSMakeRect(0, 0, 800, 600);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentsRect styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
    
    GLTFViewerViewController *viewController = [[GLTFViewerViewController alloc] init];
    MTKView *mtkView = [[MTKView alloc] initWithFrame:contentsRect device:self.device];
    viewController.view = mtkView;
    viewController.asset = self.asset;
    
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    windowController.contentViewController = viewController;
    [self addWindowController:windowController];
    
    if ([[[NSDocumentController sharedDocumentController] documents] count] == 1) {
        [window center];
    } else {
        NSDocument *mostRecentDocument = [[[NSDocumentController sharedDocumentController] documents] lastObject];
        NSWindowController *mostRecentWindowController = [[mostRecentDocument windowControllers] lastObject];
        NSPoint origin = NSMakePoint(0, 0);
        origin = [[mostRecentWindowController window] cascadeTopLeftFromPoint:origin];
        [window setFrameOrigin:origin];
    }
    
    [windowController.window makeFirstResponder:windowController.contentViewController];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:nil];
    }
    return nil;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
    self.device = MTLCreateSystemDefaultDevice();
    self.bufferAllocator = [[GLTFMTLBufferAllocator alloc] initWithDevice:self.device];
    self.asset = [[GLTFAsset alloc] initWithURL:url bufferAllocator:self.bufferAllocator];
    
    self.displayName = [url lastPathComponent];
    
    return (self.asset != nil);
}

+ (BOOL)autosavesInPlace {
    return YES;
}

@end

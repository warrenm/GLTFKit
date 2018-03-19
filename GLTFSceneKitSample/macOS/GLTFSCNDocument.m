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

#import "GLTFSCNDocument.h"
#import "GLTFSCNViewController.h"

@interface GLTFSCNDocument()
@property (nonatomic, strong) GLTFSCNViewController *viewerController;
@property (nonatomic, strong) id<GLTFBufferAllocator> bufferAllocator;
@end

@implementation GLTFSCNDocument

- (void)makeWindowControllers {
    NSRect contentsRect = NSMakeRect(0, 0, 800, 600);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentsRect styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
    
    GLTFSCNViewController *viewController = [[GLTFSCNViewController alloc] init];
    viewController.view = [[SCNView alloc] initWithFrame:contentsRect];
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
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:nil];
    }
    return nil;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
    self.bufferAllocator = [[GLTFDefaultBufferAllocator alloc] init];
    self.asset = [[GLTFAsset alloc] initWithURL:url bufferAllocator:self.bufferAllocator];
    NSLog(@"INFO: Total live buffer allocation size after document load is %0.2f MB", ([GLTFDefaultBufferAllocator liveAllocationSize] / (float)1e6));

    self.displayName = [url lastPathComponent];
    
    return (self.asset != nil);
}

+ (BOOL)autosavesInPlace {
    return YES;
}

@end

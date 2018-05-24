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

#import "GLTFDocument.h"
#import "GLTFViewerViewController.h"

#import <GLTFMTL/GLTFMTL.h>

@interface GLTFDocument() <GLTFAssetLoadingDelegate>

@property (nonatomic, strong) GLTFViewerViewController *viewerController;

@property (class, nonatomic, readonly, strong) id<MTLDevice> device;
@property (class, nonatomic, readonly, strong) id<GLTFBufferAllocator> bufferAllocator;
@property (class, nonatomic, readonly, strong) GLTFMTLLightingEnvironment *lightingEnvironment;
@property (class, nonatomic, readonly, strong) NSURLSession *urlSession;
@end

@implementation GLTFDocument

+ (id<MTLDevice>)device {
    static id<MTLDevice> _device = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _device = MTLCreateSystemDefaultDevice();
    });
    return _device;
}

+ (id<GLTFBufferAllocator>)bufferAllocator {
    static id<GLTFBufferAllocator> _bufferAllocator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _bufferAllocator = [[GLTFMTLBufferAllocator alloc] initWithDevice:GLTFDocument.device];
    });
    return _bufferAllocator;
}

+ (GLTFMTLLightingEnvironment *)lightingEnvironment {
    static GLTFMTLLightingEnvironment *_lightingEnvironment = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        NSURL *environmentURL = [[NSBundle mainBundle] URLForResource:@"tropical_beach" withExtension:@"hdr"];
        _lightingEnvironment = [[GLTFMTLLightingEnvironment alloc] initWithContentsOfURL:environmentURL
                                                                                  device:GLTFDocument.device
                                                                                   error:&error];
        _lightingEnvironment.intensity = 1.0;
    });
    return _lightingEnvironment;
}

+ (NSURLSession *)urlSession {
    static NSURLSession *_urlSession = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _urlSession = [NSURLSession sessionWithConfiguration:configuration];
    });
    return _urlSession;
}

- (void)setAsset:(GLTFAsset *)asset {
    _asset = asset;
    self.viewerController.asset = asset;
}

- (void)makeWindowControllers {
    NSRect contentsRect = NSMakeRect(0, 0, 800, 600);
    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentsRect styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
    
    GLTFViewerViewController *viewController = [[GLTFViewerViewController alloc] init];
    MTKView *mtkView = [[MTKView alloc] initWithFrame:contentsRect device:GLTFDocument.device];
    viewController.view = mtkView;
    viewController.asset = self.asset;
    viewController.lightingEnvironment = [GLTFDocument lightingEnvironment];
    self.viewerController = viewController;
    
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
    //NSURL *remoteURL = [NSURL URLWithString:@"https://warrenmoore.net/files/gltf/animated_humanoid_robot/scene.gltf"];

    [GLTFAsset loadAssetWithURL:url bufferAllocator:GLTFDocument.bufferAllocator delegate:self];

    self.displayName = [url lastPathComponent];

    return YES;
}

+ (BOOL)autosavesInPlace {
    return YES;
}

- (void)assetWithURL:(nonnull NSURL *)assetURL didFailToLoadWithError:(nonnull NSError *)error {
    NSLog(@"Asset load failed with error: %@", error);
}

- (void)assetWithURL:(nonnull NSURL *)assetURL didFinishLoading:(nonnull GLTFAsset *)asset {
    self.asset = asset;
    NSLog(@"INFO: Total live buffer allocation size after document load is %0.2f MB", ([GLTFMTLBufferAllocator liveAllocationSize] / (float)1e6));
}

- (void)assetWithURL:(nonnull NSURL *)assetURL requiresContentsOfURL:(nonnull NSURL *)url completionHandler:(void (^)(NSData *_Nullable, NSError *_Nullable))completionHandler {
    NSURLSessionDataTask *task = [GLTFDocument.urlSession dataTaskWithURL:url
                                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        completionHandler(data, error);
    }];
    [task resume];
}

@end

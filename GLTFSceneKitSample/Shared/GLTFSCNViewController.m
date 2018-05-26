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

#import "GLTFSCNViewController.h"
#import "GLTFSCNAnimationPlaybackViewController.h"

#import <GLTFSCN/GLTFSCN.h>

@interface GLTFSCNViewController ()
@property (nonatomic, weak) SCNView *scnView;
@property (nonatomic, strong) GLTFSCNAnimationPlaybackViewController *animationController;
@end

@implementation GLTFSCNViewController

- (SCNView *)scnView {
    return (SCNView *)self.view;
}

- (void)setView:(NSView *)view {
    [super setView:view];
    
    self.scnView.allowsCameraControl = YES;
    
    id<MTLCommandQueue> commandQueue = self.scnView.commandQueue;
    // Setting the command queue's label to something other than "com.apple.SceneKit" allows us to capture it for debugging purposes.
    commandQueue.label = @"gltf.scenekit";
}

- (void)setAsset:(GLTFAsset *)asset {
    GLTFSCNAsset *scnAsset = [SCNScene assetFromGLTFAsset:asset options:@{}];
    _scene = scnAsset.defaultScene;
    
    if ([scnAsset.animations count] > 0) {
        [self showAnimationUI];
        self.animationController.animationsForNames = scnAsset.animations;
        self.animationController.scnView = self.scnView;
    }

    _scene.lightingEnvironment.contents = @"piazza_san_marco.hdr";
    _scene.lightingEnvironment.intensity = 2.0;
    
    _scene.background.contents = @"piazza_san_marco.hdr";

    SCNNode *cameraNode = [SCNNode node];
    cameraNode.camera = [SCNCamera camera];
    cameraNode.camera.wantsHDR = YES;
    cameraNode.camera.wantsExposureAdaptation = YES;
    cameraNode.camera.bloomIntensity = 1.0;
    cameraNode.camera.zNear = 0.01;
    cameraNode.camera.zFar = 100.0;
    cameraNode.camera.automaticallyAdjustsZRange = YES;
    cameraNode.position = SCNVector3Make(0, 0, 4);
    [_scene.rootNode addChildNode:cameraNode];

    self.scnView.scene = _scene;
}

- (void)showAnimationUI {
    self.animationController = [[GLTFSCNAnimationPlaybackViewController alloc] initWithNibName:@"AnimationPlaybackView" bundle:nil];
    self.animationController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.animationController.view];
    NSDictionary *views = @{ @"controller" : self.animationController.view };
    [NSLayoutConstraint constraintWithItem:self.animationController.view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                    toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:0 constant:480].active = YES;
    [NSLayoutConstraint constraintWithItem:self.animationController.view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual
                                    toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:0 constant:100].active = YES;
    [NSLayoutConstraint constraintWithItem:self.animationController.view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual
                                    toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0].active = YES;
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[controller]-(12)-|" options:0 metrics:nil views:views]];
}

@end

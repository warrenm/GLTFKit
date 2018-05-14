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

#import "GLTFSCNAnimationPlaybackViewController.h"
#import <GLTFSCN/GLTFSCN.h>

static const NSTimeInterval GLTFSCNAnimationInterval = 1 / 60.0;

typedef NS_ENUM(NSInteger, GLTFSCNAnimationPlaybackState) {
    GLTFSCNAnimationPlaybackStateStopped,
    GLTFSCNAnimationPlaybackStatePlaying,
    GLTFSCNAnimationPlaybackStatePaused,
};

typedef NS_ENUM(NSInteger, GLTFSCNAnimationLoopMode) {
    GLTFSCNAnimationLoopModeDontLoop,
    GLTFSCNAnimationLoopModeLoopOne,
    GLTFSCNAnimationLoopModeLoopAll,
};

@interface GLTFSCNAnimationPlaybackViewController ()
@property (nonatomic, assign) NSTimeInterval nominalStartTime;
@property (nonatomic, assign) NSTimeInterval currentAnimationDuration;
@property (nonatomic, strong) NSTimer *playbackTimer;
@property (nonatomic, assign) GLTFSCNAnimationPlaybackState state;
@property (nonatomic, assign) GLTFSCNAnimationLoopMode loopMode;
@property (nonatomic, strong) NSMutableSet *animatedNodes;
@end

@implementation GLTFSCNAnimationPlaybackViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.state = GLTFSCNAnimationPlaybackStateStopped;
    self.loopMode = GLTFSCNAnimationLoopModeLoopOne;
    self.animatedNodes = [NSMutableSet set];
    
    if ([NSFont respondsToSelector:@selector(monospacedDigitSystemFontOfSize:weight:)])
    {
        NSFont *font = [NSFont monospacedDigitSystemFontOfSize:self.progressLabel.font.pointSize weight:NSFontWeightRegular];
        self.progressLabel.font = font;
        self.durationLabel.font = font;
    }
    
    self.progressLabel.stringValue = @"-.--";
    self.durationLabel.stringValue = @"-.--";
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [self stopAnimation];
}

- (void)setAnimationsForNames:(NSDictionary *)animationsForNames {
    _animationsForNames = animationsForNames;
    
    NSArray *names = [animationsForNames.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    [self.animationNamePopUp removeAllItems];
    [self.animationNamePopUp addItemsWithTitles:names];
    
    NSString *name = [self.animationNamePopUp.selectedItem title];
    [self startAnimationNamed:name];
    [self pauseAnimation];
}

- (void)schedulePlaybackTimer {
    self.playbackTimer = [NSTimer timerWithTimeInterval:GLTFSCNAnimationInterval
                                                 target:self
                                               selector:@selector(playbackTimerDidFire:)
                                               userInfo:nil
                                                repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.playbackTimer forMode:NSRunLoopCommonModes];
}

- (void)invalidatePlaybackTimer {
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
}

- (void)startAnimationNamed:(NSString *)name {
    NSArray *animations = self.animationsForNames[name];
    if (animations.count == 0) {
        NSLog(@"ERROR: Did not find animation named %@", name);
        return;
    }
    
    __block NSTimeInterval minStartTime = FLT_MAX;
    __block NSTimeInterval maxDuration = 0;
    __block CAAnimation *longestAnimation = nil;
    __weak id weakSelf = self;
    [animations enumerateObjectsUsingBlock:^(GLTFSCNAnimationTargetPair *pair, NSUInteger index, BOOL *stop) {
        if (pair.animation.beginTime < minStartTime) {
            minStartTime = pair.animation.beginTime;
        }
        pair.animation.usesSceneTimeBase = YES;
        [pair.target addAnimation:pair.animation forKey:nil];
        [self.animatedNodes addObject:pair.target];
        if (pair.animation.duration > maxDuration) {
            maxDuration = pair.animation.duration;
            longestAnimation = pair.animation;
        }
    }];
    
    self.currentAnimationDuration = maxDuration;
    self.nominalStartTime = minStartTime;
    
    SCNAnimationEvent *endEvent = [SCNAnimationEvent animationEventWithKeyTime:1.0
                                                                         block:^(id<SCNAnimation> animation, id animatedObject, BOOL playingBackward)
    {
       dispatch_async(dispatch_get_main_queue(), ^{
           [weakSelf handleAnimationEnd];
       });
    }];
    longestAnimation.animationEvents = @[endEvent];

    if (longestAnimation == nil) {
        NSLog(@"WARNING: Did not find animation with duration > 0; loop modes will not behave correctly");
    }
    
    self.progressSlider.minValue = 0;
    self.progressSlider.maxValue = self.currentAnimationDuration;
    self.progressSlider.floatValue = 0;
    self.scnView.sceneTime = self.nominalStartTime;
    
    [self schedulePlaybackTimer];
    
    self.state = GLTFSCNAnimationPlaybackStatePlaying;
}

- (void)stopAnimation {
    switch (self.state) {
        case GLTFSCNAnimationPlaybackStatePaused:
        case GLTFSCNAnimationPlaybackStatePlaying:
            [self removeAllAnimations];
            [self invalidatePlaybackTimer];
            self.progressSlider.minValue = 0;
            self.progressSlider.maxValue = 1;
            self.progressSlider.floatValue = 0;
            self.scnView.sceneTime = 0;
            break;
        default:
            break;
    }

    self.state = GLTFSCNAnimationPlaybackStateStopped;
}

- (void)pauseAnimation {
    switch (self.state) {
        case GLTFSCNAnimationPlaybackStatePlaying:
            [self invalidatePlaybackTimer];
            self.state = GLTFSCNAnimationPlaybackStatePaused;
            break;
        case GLTFSCNAnimationPlaybackStatePaused:
        case GLTFSCNAnimationPlaybackStateStopped:
            break;
    }
}

- (void)removeAllAnimations {
    for (id obj in self.animatedNodes) {
        [obj removeAllAnimations];
    }
    [self.animatedNodes removeAllObjects];
}

- (void)handleAnimationEnd {
    if (self.state == GLTFSCNAnimationPlaybackStatePlaying) {
        switch (self.loopMode) {
            case GLTFSCNAnimationLoopModeDontLoop:
                [self pauseAnimation];
                break;
            case GLTFSCNAnimationLoopModeLoopAll:
                [self advanceToNextAnimation];
            default:
                break;
        }
    }
}

- (void)advanceToNextAnimation {
    [self stopAnimation];
    NSInteger nextIndex = (self.animationNamePopUp.indexOfSelectedItem + 1) % self.animationNamePopUp.numberOfItems;
    [self.animationNamePopUp selectItemAtIndex:nextIndex];
    NSString *name = [self.animationNamePopUp.selectedItem title];
    [self startAnimationNamed:name];
}

- (void)updateProgressDisplay:(BOOL)forceUpdateSlider {
    NSTimeInterval time = self.scnView.sceneTime - self.nominalStartTime;
    if (forceUpdateSlider) {
        self.progressSlider.floatValue = fmod(time, self.currentAnimationDuration);
    }
    self.progressLabel.stringValue = [NSString stringWithFormat:@"%0.2f", fmod(time, self.currentAnimationDuration)];
    self.durationLabel.stringValue = [NSString stringWithFormat:@"%0.2f", self.currentAnimationDuration];
}

- (IBAction)didClickPlayPause:(id)sender {
    switch (self.state) {
        case GLTFSCNAnimationPlaybackStatePlaying:
            [self invalidatePlaybackTimer];
            self.state = GLTFSCNAnimationPlaybackStatePaused;
            break;
        case GLTFSCNAnimationPlaybackStatePaused:
            [self schedulePlaybackTimer];
            self.state = GLTFSCNAnimationPlaybackStatePlaying;
            break;
        case GLTFSCNAnimationPlaybackStateStopped: {
            NSString *name = [self.animationNamePopUp.selectedItem title];
            [self startAnimationNamed:name];
            self.state = GLTFSCNAnimationPlaybackStatePlaying;
            break;
        }
    }
}

- (IBAction)didSelectAnimationName:(id)sender {
    [self stopAnimation];
    NSString *name = [self.animationNamePopUp.selectedItem title];
    [self startAnimationNamed:name];
}

- (IBAction)didSelectMode:(id)sender {
    switch (self.modeSegmentedControl.indexOfSelectedItem) {
        case 0: // Loop All
            self.loopMode = GLTFSCNAnimationLoopModeLoopAll;
            break;
        case 1: // Loop One
            self.loopMode = GLTFSCNAnimationLoopModeLoopOne;
            break;
        case 2: // No Loop
            self.loopMode = GLTFSCNAnimationLoopModeDontLoop;
            break;
    }
}

- (IBAction)progressValueDidChange:(id)sender {
    switch (self.state) {
        case GLTFSCNAnimationPlaybackStatePlaying:
            [self invalidatePlaybackTimer];
            self.state = GLTFSCNAnimationPlaybackStatePaused;
            break;
        default:
            break;
    }

    self.scnView.sceneTime = self.progressSlider.floatValue + self.nominalStartTime;
    [self updateProgressDisplay:NO];
}

- (IBAction)playbackTimerDidFire:(id)sender {
    NSTimeInterval time = self.scnView.sceneTime;
    time += GLTFSCNAnimationInterval;
    self.scnView.sceneTime = time;
    [self updateProgressDisplay:YES];
}

@end

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

@import Foundation;

#if TARGET_OS_OSX
@import Cocoa;
typedef NSViewController NSUIViewController;
#else
@import UIKit;
typedef UIViewController NSUIViewController;
#endif

@import SceneKit;

@interface GLTFSCNAnimationPlaybackViewController : NSUIViewController

@property (nonatomic, strong) SCNView *scnView;
@property (nonatomic, strong) NSDictionary *animationsForNames;

#if TARGET_OS_OSX
@property (weak) IBOutlet NSPopUpButton *animationNamePopUp;
@property (weak) IBOutlet NSSegmentedControl *modeSegmentedControl;
@property (weak) IBOutlet NSButton *playPauseButton;
@property (weak) IBOutlet NSTextField *progressLabel;
@property (weak) IBOutlet NSSlider *progressSlider;
@property (weak) IBOutlet NSTextField *durationLabel;
#endif

- (IBAction)didSelectAnimationName:(id)sender;
- (IBAction)didSelectMode:(id)sender;
- (IBAction)didClickPlayPause:(id)sender;
- (IBAction)progressValueDidChange:(id)sender;


@end

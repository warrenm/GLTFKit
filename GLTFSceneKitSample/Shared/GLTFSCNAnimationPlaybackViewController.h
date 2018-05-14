
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

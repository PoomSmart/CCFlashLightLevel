#import <AVFoundation/AVFoundation.h>

#define PLIST_PATH @"/var/mobile/Library/Preferences/com.PS.CCFlashLightLevel.plist"
#define TorchButtonIdent @"com.apple.controlcenter.quicklaunch.torch"
#define torchButton MSHookIvar<SBControlCenterButton *>(self, "_torchButton")
#define flashlight MSHookIvar<AVFlashlight *>(self, "_flashlight")

@interface AVFlashlight : NSObject
@property(readonly, assign, nonatomic) float flashlightLevel;
@property(readonly, assign, nonatomic, getter=isOverheated) BOOL overheated;
@property(readonly, assign, nonatomic, getter=isAvailable) BOOL available;
+ (BOOL)hasFlashlight;
+ (void)initialize;
- (void)handleNotification:(id)notification payload:(id)payload;
- (BOOL)setFlashlightLevel:(float)level withError:(id*)error;
- (void)turnPowerOff;
- (BOOL)turnPowerOnWithError:(id*)error;
- (void)_refreshIsAvailable;
- (void)dealloc;
- (id)init;
- (void)teardownFigRecorder;
- (BOOL)ensureFigRecorderWithError:(id*)error;
- (BOOL)bringupFigRecorderWithError:(id*)error;
@end

@interface SBUIControlCenterButton : UIButton
- (void)_updateSelected:(BOOL)selected highlighted:(BOOL)highlighted;
@end

@interface SBControlCenterButton : SBUIControlCenterButton
@property(copy, nonatomic) NSString *identifier;
@end

@interface SBCCQuickLaunchSectionController
- (NSString *)_bundleIDForButton:(SBControlCenterButton *)button;
- (void)CCFLLInit:(SBControlCenterButton *)button;
@end

@interface CCTControlCenterButton : SBUIControlCenterButton
- (SBCCQuickLaunchSectionController *)delegate;
- (NSString *)identifier;
@end

static UISlider *slider = nil;
static NSTimer *holdTime = nil;
static NSTimer *sliderTime = nil;
static UIView *placeHolder = nil;

static BOOL usingSlider = NO;
static BOOL hookAVFlashlight = NO;
static BOOL tap = NO;

static void invalidate()
{
	if (holdTime != nil) {
		[holdTime invalidate];
		holdTime = nil;
	}
	if (sliderTime != nil) {
		[sliderTime invalidate];
		sliderTime = nil;
	}
}

static void willShowSlider(id self)
{
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	float interval = [dict objectForKey:@"showTime"] ? [[dict objectForKey:@"showTime"] floatValue] : 1.2;
	holdTime = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(CCFLLshowSlider) userInfo:nil repeats:NO];
	[holdTime retain];
}

static void willHideSlider(id self)
{
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	float interval = [dict objectForKey:@"hideTime"] ? [[dict objectForKey:@"hideTime"] floatValue] : 3;
	sliderTime = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(CCFLLhideSlider) userInfo:nil repeats:NO];
	[sliderTime retain];
}

static float readLightLevel()
{
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	if (![[dict objectForKey:@"enableDefault"] boolValue])
		return slider.value != 0.0 ? slider.value : 1;
	float level = [dict objectForKey:@"level"] ? [[dict objectForKey:@"level"] floatValue] : 1;
	return level;
}

%hook CCTControlCenterButton

- (void)setDelegate:(id)section
{
	%orig;
	if ([section isKindOfClass:%c(SBCCQuickLaunchSectionController)] && [self.identifier isEqualToString:TorchButtonIdent])
		[section CCFLLInit:(SBControlCenterButton *)self];
}

%end

%hook AVFlashlight

- (BOOL)setFlashlightLevel:(float)value withError:(NSError *)error
{
	if (!hookAVFlashlight || value == 0 || !tap)
		return %orig;
	float val = readLightLevel();
	if (val == 1)
		val = AVCaptureMaxAvailableTorchLevel;
	return %orig(val, error);
}

%end

%hook SBCCQuickLaunchSectionController

%new
- (void)CCFLLInit:(SBControlCenterButton *)button
{
	button.identifier = TorchButtonIdent;
	[button addTarget:self action:@selector(FLbuttonTouchDown) forControlEvents:UIControlEventTouchDown];
	[button addTarget:self action:@selector(FLbuttonCancel) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	[slider release];
	slider = [[UISlider alloc] init];
	[slider addTarget:self action:@selector(sliderDidChange:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(touchSlider) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(releaseSlider) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	slider.value = flashlight.flashlightLevel;
	slider.frame = CGRectMake(0, button.frame.size.width/2-5, button.frame.size.width, 12);
	[placeHolder release];
	placeHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
	placeHolder.backgroundColor = [UIColor clearColor];
	placeHolder.userInteractionEnabled = NO;
	[placeHolder addSubview:slider];
	[button addSubview:placeHolder];
	slider.alpha = 0;
	slider.hidden = YES;
}

- (void)viewDidLoad
{
	%orig;
	if (%c(CCTControlCenterButton) == nil)
		[self CCFLLInit:torchButton];
}

- (void)_enableTorch:(BOOL)on
{
	hookAVFlashlight = YES;
	%orig;
	hookAVFlashlight = NO;
}

- (void)dealloc
{
	[slider removeFromSuperview];
	[slider release];
	slider = nil;
	[placeHolder removeFromSuperview];
	[placeHolder release];
	placeHolder = nil;
	invalidate();
	%orig;
}

%new
- (void)sliderDidChange:(UISlider *)slider
{
	float value = slider.value;
	if (value == 1)
		value = AVCaptureMaxAvailableTorchLevel;
	[flashlight setFlashlightLevel:value withError:nil];
}

%new
- (void)touchSlider
{
	usingSlider = YES;
}

%new
- (void)releaseSlider
{
	usingSlider = NO;
	willHideSlider(self);
}

%new
- (void)FLbuttonCancel
{
	invalidate();
}

- (void)buttonTapped:(SBControlCenterButton *)button
{
	tap = YES;
	if ([button.identifier isEqualToString:TorchButtonIdent]) {
		invalidate();
		if (usingSlider || !slider.hidden) {
			[button _updateSelected:slider.value != 0.0 highlighted:NO];
			willHideSlider(self);
			return;
		}
	}
	%orig;
	tap = NO;
}

%new
- (void)FLbuttonTouchDown
{
	willShowSlider(self);
}

%new
- (void)CCFLLshowSlider
{
	[UIView animateWithDuration:.9 delay:0 options:0 animations:^{
    	slider.alpha = 1;
    	slider.hidden = NO;
   	 }
	completion:^(BOOL finished) {
		if (slider.value == 1)
			slider.value = AVCaptureMaxAvailableTorchLevel;
		[flashlight setFlashlightLevel:slider.value withError:nil];
		[torchButton _updateSelected:slider.value != 0.0 highlighted:NO];
    	placeHolder.userInteractionEnabled = YES;
		slider.userInteractionEnabled = YES;
		willHideSlider(self);
    }];
}

%new
- (void)CCFLLhideSlider
{
	if (usingSlider)
		return;
	[UIView animateWithDuration:.9 delay:0 options:0 animations:^{
    	slider.alpha = 0;
    }
    completion:^(BOOL finished) {
    	slider.hidden = YES;
		slider.userInteractionEnabled = NO;
		placeHolder.userInteractionEnabled = NO;
		torchButton.userInteractionEnabled = YES;
    }];
}

%end

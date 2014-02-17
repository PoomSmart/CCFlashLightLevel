#import <AVFoundation/AVFoundation.h>

#define PLIST_PATH @"/var/mobile/Library/Preferences/com.PS.CCFlashLightLevel.plist"

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
@end

static UISlider *slider = nil;
static NSTimer *holdTime = nil;
static NSTimer *sliderTime = nil;
static UIView *placeHolder = nil;

static BOOL usingSlider = NO;

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

%hook SBCCQuickLaunchSectionController

- (void)viewDidLoad
{
	%orig;
	SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
	torchButton.identifier = @"CCFlashLightLevel.torchButton";
	AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
	[torchButton addTarget:self action:@selector(FLbuttonTouchDown) forControlEvents:UIControlEventTouchDown];
	[torchButton addTarget:self action:@selector(FLbuttonCancel) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	slider = [[UISlider alloc] init];
	[slider addTarget:self action:@selector(sliderDidChange:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(touchSlider) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(releaseSlider) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	slider.value = flashlight.flashlightLevel;
	slider.frame = CGRectMake(0, torchButton.frame.size.width/2-5, torchButton.frame.size.width, 12);
	placeHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
	placeHolder.backgroundColor = [UIColor clearColor];
	placeHolder.userInteractionEnabled = NO;
	[placeHolder addSubview:slider];
	[torchButton addSubview:placeHolder];
	slider.alpha = 0;
	slider.hidden = YES;
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
	AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
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
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	float interval = [dict objectForKey:@"hideTime"] ? [[dict objectForKey:@"hideTime"] floatValue] : 3;
	sliderTime = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(hideSlider) userInfo:nil repeats:NO];
	[sliderTime retain];
}

%new
- (void)FLbuttonCancel
{
	invalidate();
}

- (void)buttonTapped:(SBControlCenterButton *)button
{
	if ([button.identifier isEqualToString:@"CCFlashLightLevel.torchButton"]) {
		invalidate();
		if (usingSlider || !slider.hidden) {
			[button _updateSelected:slider.value != 0.0 highlighted:NO];
			return;
		}
	}
	%orig;
}

/*%new
- (void)FLbuttonTapped
{
	invalidate();
	if (usingSlider || !slider.hidden)
		return;
	SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
	[self buttonTapped:torchButton];
}*/

%new
- (void)FLbuttonTouchDown
{
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	float interval = [dict objectForKey:@"showTime"] ? [[dict objectForKey:@"showTime"] floatValue] : 1.2;
	holdTime = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(showSlider) userInfo:nil repeats:NO];
	[holdTime retain];
}

%new
- (void)showSlider
{
	AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
	slider.value = flashlight.flashlightLevel;
	if (slider.value == 1)
		slider.value = AVCaptureMaxAvailableTorchLevel;
	[flashlight setFlashlightLevel:slider.value withError:nil];
	SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
	[torchButton _updateSelected:slider.value != 0.0 highlighted:NO];
	
	[UIView animateWithDuration:.9 delay:0 options:0 animations:^{
    	slider.alpha = 1;
    	slider.hidden = NO;
    }
    completion:^(BOOL finished) {
    	placeHolder.userInteractionEnabled = YES;
		slider.userInteractionEnabled = YES;
		NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
		float interval = [dict objectForKey:@"hideTime"] ? [[dict objectForKey:@"hideTime"] floatValue] : 3;
		sliderTime = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(hideSlider) userInfo:nil repeats:NO];
		[sliderTime retain];
    }];
}

%new
- (void)hideSlider
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
		SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
		torchButton.userInteractionEnabled = YES;
    }];
}

/*
- (NSString *)_bundleIDForButton:(SBControlCenterButton *)button
{
	if ([%orig isEqualToString:@"com.apple.camera"]) {
		
	}
	return %orig;
}*/

%end
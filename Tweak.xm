#import <AVFoundation/AVFoundation.h>

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

@interface SBControlCenterButton : UIButton
@end

@interface SBCCQuickLaunchSectionController
- (NSString *)_bundleIDForButton:(SBControlCenterButton *)button;
@end

static UISlider *slider = nil;
static NSTimer *holdTime = nil;
static NSTimer *sliderTime = nil;

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
	AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
	[torchButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[torchButton addTarget:self action:@selector(FLbuttonTapped) forControlEvents:UIControlEventTouchUpInside];
	[torchButton addTarget:self action:@selector(FLbuttonTouchDown) forControlEvents:UIControlEventTouchDown];
	[torchButton addTarget:self action:@selector(FLbuttonCancel) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	slider = [[UISlider alloc] initWithFrame:CGRectMake(0, torchButton.frame.size.height/2-2, torchButton.frame.size.width, 12)];
	[slider addTarget:self action:@selector(sliderDidChange:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(touchSlider) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(releaseSlider) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
	slider.value = flashlight.flashlightLevel;
	[torchButton addSubview:slider];
	slider.alpha = 0;
	slider.hidden = YES;
}

- (void)dealloc
{
	[slider removeFromSuperview];
	[slider release];
	slider = nil;
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
	sliderTime = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideSlider) userInfo:nil repeats:NO];
	[sliderTime retain];
}

%new
- (void)FLbuttonCancel
{
	invalidate();
}

%new
- (void)FLbuttonTapped
{
	invalidate();
	if (usingSlider || !slider.hidden)
		return;
	AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
	if (flashlight.flashlightLevel == 0) {
		float value = slider.value;
		//if (value == 1)
			value = AVCaptureMaxAvailableTorchLevel;
		[flashlight setFlashlightLevel:value withError:nil];
	}
	else
		[flashlight setFlashlightLevel:0 withError:nil];
}

%new
- (void)FLbuttonTouchDown
{
	holdTime = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(showSlider) userInfo:nil repeats:NO];
	[holdTime retain];
}

%new
- (void)showSlider
{
	[UIView animateWithDuration:.9 delay:0 options:0 animations:^{
    	slider.alpha = 1;
    	slider.hidden = NO;
    }
    completion:^(BOOL finished) {
		slider.userInteractionEnabled = YES;
		AVFlashlight *flashlight = MSHookIvar<AVFlashlight *>(self, "_flashlight");
		float value = slider.value;
		if (value == 1)
			value = AVCaptureMaxAvailableTorchLevel;
		[flashlight setFlashlightLevel:value withError:nil];
		sliderTime = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(hideSlider) userInfo:nil repeats:NO];
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
		SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
		torchButton.userInteractionEnabled = YES;
    }];
}

/*- (void)buttonTapped:(SBControlCenterButton *)button
{
	if ([[self _bundleIDForButton:button] isEqualToString:@"com.apple.camera"]) {
	
	}
	%orig;
}

- (NSString *)_bundleIDForButton:(SBControlCenterButton *)button
{
	if ([%orig isEqualToString:@"com.apple.camera"]) {
		
	}
	return %orig;
}*/

%end
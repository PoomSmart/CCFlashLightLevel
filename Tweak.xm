#import "../PS.h"
#import <AVFoundation/AVFoundation.h>
#import <CaptainHook/CaptainHook.h>

NSString *const PLIST_PATH = @"/var/mobile/Library/Preferences/com.PS.CCFlashLightLevel.plist";
CFStringRef const PreferencesNotification = CFSTR("com.PS.CCFlashLightLevel.prefs");
NSString *const defaultTorchButtonIdentifier = @"flashlight";
NSString *const ccTogglesTorchButtonIdentifier = @"com.apple.controlcenter.quicklaunch.torch";
NSString *const a3tweaksTorchButtonIdentifier = @"com.a3tweaks.switch.flashlight";
CGFloat const lowestTorchLevel = 0.01f;

@interface UIView (Private)
- (UIViewController *)mpAncestorViewController;
@end

@interface AVFlashlight : NSObject
@property(readonly, assign, nonatomic) CGFloat flashlightLevel;
@property(readonly, assign, nonatomic, getter=isOverheated) BOOL overheated;
@property(readonly, assign, nonatomic, getter=isAvailable) BOOL available;
+ (BOOL)hasFlashlight;
+ (void)initialize;
- (void)handleNotification:(NSNotification *)notification payload:(id)payload;
- (BOOL)setFlashlightLevel:(CGFloat)level withError:(NSError **)error;
- (void)turnPowerOff;
- (BOOL)turnPowerOnWithError:(NSError **)error;
- (void)_refreshIsAvailable;
- (void)dealloc;
- (id)init;
- (void)teardownFigRecorder;
- (BOOL)ensureFigRecorderWithError:(NSError **)error;
- (BOOL)bringupFigRecorderWithError:(NSError **)error;
@end

//---- iOS 8
@interface SBCCButtonModule : NSObject
@end

@interface SBCCFlashlightSettings : SBCCButtonModule {
	AVFlashlight *_flashlight;
}
@end

@interface SBCCButtonController : UIViewController
@property(nonatomic, retain) SBCCButtonModule *module;
@end

@interface SBCCShortcutButtonController : SBCCButtonController
@end
//---- iOS 8

@protocol SBUIControlCenterButtonDelegate
@end

@interface SBUIControlCenterButton : UIButton
- (void)_updateSelected:(BOOL)selected highlighted:(BOOL)highlighted;
@end

@interface SBControlCenterButton : SBUIControlCenterButton
@property(copy, nonatomic) NSString *identifier;
@property(retain, nonatomic) UIViewController <SBUIControlCenterButtonDelegate> *delegate;
@end

@interface SBCCQuickLaunchSectionController : UIViewController <SBUIControlCenterButtonDelegate>
@end

@interface SBControlCenterViewController : UIViewController
@end

@interface SBControlCenterController : NSObject
+ (SBControlCenterController *)sharedInstanceIfExists;
@end

@interface SBControlCenterContentView : UIView
@property(retain, nonatomic) SBCCQuickLaunchSectionController *quickLaunchSection;
@end

@interface SBCCButtonLayoutView : UIView
@end

@interface SBCCPagingButtonScrollView : UIScrollView
@end

// CCToggles Support
@interface CCTControlCenterButton : SBUIControlCenterButton
- (id)initWithFrame:(CGRect)frame;
- (SBCCQuickLaunchSectionController *)delegate;
- (NSString *)identifier;
@end

// FlipControlCenter Support
@interface _FSSwitchButton : UIButton {
	NSString *switchIdentifier;
	BOOL skippingForHold;
}
- (id)initWithSwitchIdentifier:(NSString *)identifier template:(NSBundle *)aTemplate;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)_held;
- (void)_pressed;
@end

@interface FCCButtonsScrollView : UIScrollView
@end

static BOOL enableDefault;
static BOOL saveValueOnGesture;
static BOOL hookAVFlashlight;
static CGFloat level;

static CGFloat readLightLevel()
{
	if (!enableDefault)
		return 1.0f;
	return level;
}

static void writeLightLevel(CGFloat value)
{
	if (saveValueOnGesture) {
		NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
		[dictionary addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:PLIST_PATH]];
		#if CGFLOAT_IS_DOUBLE
		dictionary[@"level"] = @((double)value);
		#else
		dictionary[@"level"] = @(value);
		#endif
		[dictionary writeToFile:PLIST_PATH atomically:YES];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), PreferencesNotification, NULL, NULL, YES);
	}
}

static void calculateDirectionAndSetFlashlightLevel(NSSet *touches, UIViewController *controller, AVFlashlight *flashlight)
{
	if (flashlight == nil)
		return;
	CGFloat currentLevel = flashlight.flashlightLevel;
	if (currentLevel != 0.0f) {
		UITouch *aTouch = [touches anyObject];
		CGPoint newLocation = [aTouch locationInView:controller.view];
		CGPoint prevLocation = [aTouch previousLocationInView:controller.view];
		CGFloat deltaY = newLocation.y - prevLocation.y;
		CGFloat newLevel = currentLevel - (deltaY/512.0f);
		if (newLevel > 1.0f)
			newLevel = 1.0f;
		if (newLevel < lowestTorchLevel)
			newLevel = lowestTorchLevel;
		// NSLog(@"Setting %f -> %f", currentLevel, newLevel);
		hookAVFlashlight = NO;
		BOOL setLight = [flashlight setFlashlightLevel:newLevel withError:nil];
		if (setLight)
			level = newLevel;
	}
}


%group Common

%hook AVFlashlight

- (BOOL)setFlashlightLevel:(CGFloat)value withError:(NSError *)error
{
	if (!hookAVFlashlight || value == 0.0f)
		return %orig;
	CGFloat val = readLightLevel();
	return %orig(val, error);
}

%end

%hook SBControlCenterButton

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([self.identifier isEqualToString:defaultTorchButtonIdentifier]) {
		AVFlashlight *flashlight = nil;
		UIViewController *controller = nil;
		if (isiOS8Up) {
			controller = [self mpAncestorViewController];
			if (controller == nil)
				return;
			SBCCFlashlightSetting *settings = (SBCCFlashlightSetting *)(((SBCCShortcutButtonController *)controller).module);
			object_getInstanceVariable(settings, "_flashlight", (void **)&flashlight);
		} else {
			controller = self.delegate;
			if (controller == nil)
				return;
			object_getInstanceVariable(controller, "_flashlight", (void **)&flashlight);
		}
		calculateDirectionAndSetFlashlightLevel(touches, controller, flashlight);
		return;
	}
	%orig;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([self.identifier isEqualToString:defaultTorchButtonIdentifier])
		writeLightLevel(level);
	%orig;
}

%end

%end

%group iOS8

%hook SBCCFlashlightSetting

- (BOOL)_enableTorch:(BOOL)on
{
	hookAVFlashlight = YES;
	BOOL orig = %orig;
	hookAVFlashlight = NO;
	return orig;
}

%end

%end

%group CCToggles

%hook CCTControlCenterButton

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([self.identifier isEqualToString:ccTogglesTorchButtonIdentifier]) {
		AVFlashlight *flashlight = nil;
		UIViewController *controller = nil;
		if (isiOS8Up) {
			// CCToggles iOS 8
		} else {
			controller = self.delegate;
			if (controller == nil)
				return;
			object_getInstanceVariable(controller, "_flashlight", (void **)&flashlight);
		}
		calculateDirectionAndSetFlashlightLevel(touches, controller, flashlight);
		return;
	}
	%orig;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([self.identifier isEqualToString:defaultTorchButtonIdentifier])
		writeLightLevel(level);
	%orig;
}

%end

%end

%group FlipControlCenter

%hook _FSSwitchButton

- (void)_pressed
{
	if ([MSHookIvar<NSString *>(self, "switchIdentifier") isEqualToString:a3tweaksTorchButtonIdentifier]) {
		hookAVFlashlight = YES;
		%orig;
		hookAVFlashlight = NO;
		return;
	}
	%orig;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([MSHookIvar<NSString *>(self, "switchIdentifier") isEqualToString:a3tweaksTorchButtonIdentifier]) {
		AVFlashlight *flashlight = nil;
		FCCButtonsScrollView *scrollView = (FCCButtonsScrollView *)[self superview];
		SBCCButtonLayoutView *layoutView = (SBCCButtonLayoutView *)[scrollView superview];
		SBCCQuickLaunchSectionController *controller = (SBCCQuickLaunchSectionController *)[layoutView mpAncestorViewController];
		if (controller == nil)
			return;
		if (isiOS8Up) {
			// Borrow Flipswitch method here !
			SBControlCenterViewController **_viewController = CHIvarRef([%c(SBControlCenterController) sharedInstanceIfExists], _viewController, SBControlCenterViewController *);
			if (_viewController) {
				SBControlCenterContentView **_contentView = CHIvarRef(*_viewController, _contentView, SBControlCenterContentView *);
				if (_contentView && [*_contentView respondsToSelector:@selector(quickLaunchSection)]) {
					id quickLaunchSection = [*_contentView quickLaunchSection];
					NSMutableDictionary **_modulesByID = CHIvarRef(quickLaunchSection, _modulesByID, NSMutableDictionary *);
					id target = _modulesByID && *_modulesByID ? [*_modulesByID objectForKey:@"flashlight"] : quickLaunchSection;
					AVFlashlight **_myflashlight = CHIvarRef(target, _flashlight, AVFlashlight *);
					if (_myflashlight)
						flashlight = *_myflashlight;
				}
			}
		} else {
			object_getInstanceVariable(controller, "_flashlight", (void **)&flashlight);
		}
		calculateDirectionAndSetFlashlightLevel(touches, controller, flashlight);
		return;
	}
	%orig;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if ([MSHookIvar<NSString *>(self, "switchIdentifier") isEqualToString:a3tweaksTorchButtonIdentifier])
		writeLightLevel(level);
	%orig;
}

%end

%end

%group iOS7

%hook SBCCQuickLaunchSectionController

- (void)_enableTorch:(BOOL)on
{
	hookAVFlashlight = YES;
	%orig;
	hookAVFlashlight = NO;
}

- (void)viewDidLoad
{
	%orig;
	SBControlCenterButton *torchButton = MSHookIvar<SBControlCenterButton *>(self, "_torchButton");
	torchButton.identifier = defaultTorchButtonIdentifier; // well..
}

%end

%end

static void prefs()
{
	CFPreferencesAppSynchronize(CFSTR("com.PS.CCFlashLightLevel"));
	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
	enableDefault = [dict[@"enableDefault"] boolValue];
	saveValueOnGesture = [dict[@"saveValueOnGesture"] boolValue];
	#if CGFLOAT_IS_DOUBLE
	level = dict[@"level"] ? [dict[@"level"] doubleValue] : 1.0f;
	#else
	level = dict[@"level"] ? [dict[@"level"] floatValue] : 1.0f;
	#endif
}

static void reloadSettings(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	prefs();
}

%ctor
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, &reloadSettings, PreferencesNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
	prefs();
	if (isiOS8Up) {
		%init(iOS8);
	} else {
		%init(iOS7);
	}
	%init(Common);
	if (dlopen("/Library/MobileSubstrate/DynamicLibraries/FlipControlCenter.dylib", RTLD_LAZY) && dlopen("/Library/MobileSubstrate/DynamicLibraries/Flipswitch.dylib", RTLD_LAZY)) {
		%init(FlipControlCenter);
	}
	if (dlopen("/Library/MobileSubstrate/DynamicLibraries/CCToggles.dylib", RTLD_LAZY)) {
		%init(CCToggles);
	}
	[pool drain];
}

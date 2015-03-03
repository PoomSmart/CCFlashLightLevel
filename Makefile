SDKVERSION = 7.0
GO_EASY_ON_ME = 1
ARCHS = armv7 arm64

include theos/makefiles/common.mk
TWEAK_NAME = CCFlashLightLevel
CCFlashLightLevel_FILES = Tweak.xm
CCFlashLightLevel_FRAMEWORKS = AVFoundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp -R CCFlashLightLevel $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCFlashLightLevel$(ECHO_END)
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name .DS_Store | xargs rm -rf$(ECHO_END)


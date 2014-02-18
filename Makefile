GO_EASY_ON_ME = 1
ARCHS = armv7 armv7s arm64

include theos/makefiles/common.mk
TWEAK_NAME = CCZFlashLightLevel
CCZFlashLightLevel_FILES = Tweak.xm
CCZFlashLightLevel_FRAMEWORKS = AVFoundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp -R CCFlashLightLevel $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCFlashLightLevel$(ECHO_END)
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name .DS_Store | xargs rm -rf$(ECHO_END)


TARGET := iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SubwayCoinHack

SubwayCoinHack_FILES = Tweak.x
SubwayCoinHack_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

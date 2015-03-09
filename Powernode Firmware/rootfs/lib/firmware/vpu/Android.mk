
ifeq ($(BOARD_HAVE_VPU),true)
ifeq ($(EXCLUDED_CODEC_BUILD),false)

LOCAL_PATH := $(call my-dir)

vpu_fw_target := $(TARGET_OUT)/lib/firmware/vpu

soc := $(shell echo "$(BOARD_SOC_TYPE)" | tr 'A-Z' 'a-z')
vpu_fw_file := vpu_fw_$(soc).bin

# Firmware
include $(CLEAR_VARS)
LOCAL_MODULE := $(vpu_fw_file)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(vpu_fw_target)
LOCAL_MODULE_TAGS := eng
LOCAL_SRC_FILES := $(LOCAL_MODULE)
include $(BUILD_PREBUILT)

endif
endif

########################################################################
# Kernel settings for the Xiaomi Mi 10 (umi)
########################################################################

# Android (downstream) kernel
VARIANT = android

# Kernel base version (LineageOS lineage-23.2 = 4.19.325)
KERNEL_BASE_VERSION = 4.19-325

# Boot image cmdline. Based on the stock MIUI 13 cmdline, with the
# Droidian/Halium additions:
#   - console=tty0 for the VT
#   - apparmor/lsm for Droidian
#   - firmware_class.path for the qca6390 Wi-Fi firmware
#   - droidian.lvm.prefer (Droidian initramfs; falls back to /data/rootfs.img)
KERNEL_BOOTIMAGE_CMDLINE = console=tty0 androidboot.hardware=qcom androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 loop.max_part=7 cgroup.memory=nokmem,nosocket reboot=panic_warm firmware_class.path=/vendor/firmware_mnt/image apparmor=1 security=apparmor lsm=lockdown,yama,integrity,apparmor printk.devkmsg=on droidian.lvm.prefer

# Device vendor / model slugs (package and KERNELRELEASE names)
DEVICE_VENDOR = xiaomi
DEVICE_MODEL = umi

# Marketing name
DEVICE_FULL_NAME = Xiaomi Mi 10

# Use kernel config fragments
KERNEL_CONFIG_USE_FRAGMENTS = 1
KERNEL_CONFIG_USE_DIFFCONFIG = 0

# Common fragments: LineageOS debugfs + Xiaomi sm8250 common config.
# The device fragment (droidian/umi.config) and the Halium fragment are
# added by the snippet via KERNEL_CONFIG_DEVICE_FRAGMENTS.
KERNEL_CONFIG_COMMON_FRAGMENTS = $(KERNEL_SOURCES)/droidian/debugfs.config $(KERNEL_SOURCES)/droidian/sm8250-common.config
KERNEL_CONFIG_EXTRA_FRAGMENTS = halium.config

# Defconfig
KERNEL_DEFCONFIG = vendor/kona-perf_defconfig

# Device trees: the bootloader expects the three kona base DTBs, in this
# order; the umi-sm8250 overlay (dtbo partition) is applied on top by ABL.
# `make dtbs` builds these as prerequisites of the umi overlay targets.
KERNEL_IMAGE_WITH_DTB = 1
KERNEL_IMAGE_DTB = arch/arm64/boot/dts/vendor/qcom/kona.dtb arch/arm64/boot/dts/vendor/qcom/kona-v2.dtb arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb

# We keep the stock MIUI dtbo partition (umi overlay)
KERNEL_IMAGE_WITH_DTB_OVERLAY = 0
KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL = 0

# Boot image parameters, from the stock MIUI 13 boot.img header
KERNEL_BOOTIMAGE_PAGE_SIZE = 4096
KERNEL_BOOTIMAGE_BASE_OFFSET = 0x00000000
KERNEL_BOOTIMAGE_KERNEL_OFFSET = 0x00008000
KERNEL_BOOTIMAGE_INITRAMFS_OFFSET = 0x01000000
KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET = 0x00f00000
KERNEL_BOOTIMAGE_TAGS_OFFSET = 0x00000100
KERNEL_BOOTIMAGE_DTB_OFFSET = 0x01f00000
KERNEL_BOOTIMAGE_VERSION = 2

########################################################################
# Android verified boot
########################################################################

# Build an empty vbmeta image (disables verification/hashtree). The device
# is unlocked; this is only needed if dm-verity blocks the vendor partition.
DEVICE_VBMETA_REQUIRED = 1
DEVICE_VBMETA_IS_SAMSUNG = 0

########################################################################
# Automatic flashing on package upgrades
########################################################################

# We flash boot.img manually via fastboot for now.
FLASH_ENABLED = 0
FLASH_IS_AONLY = 1
FLASH_IS_LEGACY_DEVICE = 1

FLASH_INFO_MANUFACTURER = Xiaomi
FLASH_INFO_MODEL = Mi 10
FLASH_INFO_CPU = Qualcomm Technologies, Inc KONA
FLASH_INFO_DEVICE_IDS = umi

########################################################################
# Kernel build settings
########################################################################

BUILD_CROSS = 1
BUILD_TRIPLET = aarch64-linux-android-
BUILD_CLANG_TRIPLET = aarch64-linux-gnu-
BUILD_CC = clang
CLANG_CUSTOM = 1
BUILD_PATH = /usr/lib/llvm-android-14.0-r450784d/bin

# LineageOS 23.2 is strict about unused symbols; keep the build going.
KERNEL_BUILD_FLAGS = KCFLAGS="-Wno-error=unused-variable -Wno-error=unused-but-set-variable -Wno-error=unused-function -Wno-error=unused-const-variable"

DEB_TOOLCHAIN = device-tree-compiler, linux-initramfs-halium-generic:arm64, binutils-aarch64-linux-gnu, clang-android-14.0-r450784d, gcc-4.9-aarch64-linux-android, g++-4.9-aarch64-linux-android, libgcc-4.9-dev-aarch64-linux-android-cross

DEB_BUILD_ON = amd64
DEB_BUILD_FOR = arm64

KERNEL_ARCH = arm64
KERNEL_BUILD_TARGET = Image

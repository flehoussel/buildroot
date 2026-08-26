#!/bin/sh

linux_image()
{
	if grep -Eq "^BR2_LINUX_KERNEL_UIMAGE=y$" ${BR2_CONFIG}; then
		echo "uImage"
	elif grep -Eq "^BR2_LINUX_KERNEL_IMAGE=y$" ${BR2_CONFIG}; then
		echo "Image"
	elif grep -Eq "^BR2_LINUX_KERNEL_IMAGEGZ=y$" ${BR2_CONFIG}; then
		echo "Image.gz"
	else
		echo "zImage"
	fi
}

generic_getty()
{
	if grep -Eq "^BR2_TARGET_GENERIC_GETTY=y$" ${BR2_CONFIG}; then
		echo ""
	else
		echo "s/\s*console=\S*//"
	fi
}

PARTUUID="$($HOST_DIR/bin/uuidgen)"

install -d "$TARGET_DIR/boot/extlinux/"

# Buildroot's own board/orangepi/common/extlinux.conf uses "devicetreedir /boot"
# and relies on U-Boot to derive the fdt path from the ${fdtfile} env var. On
# U-Boot 2026.01 (ATF v2.12) that derivation duplicates the vendor subdir,
# producing /boot/allwinner/allwinner/sun50i-h618-orangepi-zero2w.dtb, which
# doesn't exist. Hardcode the fdt path instead of relying on devicetreedir.
sed -e "$(generic_getty)" \
	-e "s/%LINUXIMAGE%/$(linux_image)/g" \
	-e "s/%PARTUUID%/$PARTUUID/g" \
	"${BR2_EXTERNAL_AA_PROXY_OS_PATH}/board/orangepi-z2w/extlinux.conf" > "$TARGET_DIR/boot/extlinux/extlinux.conf"

sed "s/%PARTUUID%/$PARTUUID/g" "board/orangepi/common/genimage.cfg" > "$BINARIES_DIR/genimage.cfg"

date > "$TARGET_DIR/etc/build-time"

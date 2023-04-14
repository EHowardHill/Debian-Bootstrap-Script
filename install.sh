#!/bin/ash

chmod +x ./setup-debian.sh
apk add bash debootstrap lsblk parted sgdisk dosfstools
./setup-debian.sh
#!/bin/bash
set -e

echo "WARNING!!! The following script will install Debian on the following hard drive, wiping anything else on it."
echo "This includes FILES as well as any existing OPERATING SYSTEMS."
echo "Only use if you know exactly what you are doing!!!"
echo ""

# get the list of all block devices under /dev except mounted drives
devices=$(lsblk -rno NAME,SIZE,MOUNTPOINT | awk '$3 == "" {print "/dev/"$1,$2}')

# display the available drives
echo "Available drives:"
echo "$devices"

# prompt the user to select a drive
read -p "Enter the device name for the drive you want to install on (e.g. /dev/sda): " disk

# if the user input is invalid, set the default to /dev/sda
if [[ ! $devices =~ (^|[[:space:]])"$disk"($|[[:space:]]) ]]; then
  echo "Invalid input. Setting disk to /dev/sda"
  disk="/dev/sda"
fi

echo "You selected $disk."
echo ""

# Preliminary commands
mkdir -p /mnt
sgdisk --zap-all "$disk"
parted "$disk" mklabel gpt
parted "$disk" mkpart ESP fat32 0% 512MB
parted "$disk" mkpart primary ext4 512MB 100%

# Set up main partition
yes | mkfs.ext4 "${disk}2"
mount "${disk}2" /mnt

debootstrap --arch=amd64 buster /mnt http://ftp.us.debian.org/debian/

# Set up EFI partition
yes | mkfs.fat -F32 "${disk}1"
mkdir /mnt/efi
mount "${disk}1" /mnt/efi

# Set up bindings
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

# Chroot to set up grub
chroot /mnt /bin/bash << "EOT"
apt update -y
apt install -y linux-image-amd64 grub-efi-amd64 grub-efi-amd64-signed shim-signed
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=debian --recheck --no-floppy --force-extra-removable
update-grub
EOT

cp -R /root/ref/bin/. /mnt/bin/
cp -R /root/ref/home/. /mnt/home/

# chroot to install programs
chroot /mnt /bin/bash << "EOT"

# Add the community repositories to the sources list
echo "deb http://deb.debian.org/debian/ stable main contrib non-free" >> /etc/apt/sources.list
echo "deb-src http://deb.debian.org/debian/ stable main contrib non-free" >> /etc/apt/sources.list
dpkg --add-architecture i386
apt update -y
apt upgrade -y

# Set up user
mkdir /home/user
apt install -y sudo
useradd -m -d /home/user user
echo "root:password" | chpasswd
echo "user:password" | chpasswd
usermod -aG sudo user

# Set up sddm
apt install -y sddm
systemctl enable sddm

# Set up internet
echo localhost > /etc/hostname
echo "auto lo
iface lo inet loopback
allow-hotplug eth0
iface eth0 inet dhcp
source-directory /etc/network/interfaces.d" > /etc/network/interfaces
apt install -yi network-manager

# Desktop
apt install -y xorg xserver-xorg-video-all xserver-xorg-core xinit fonts-liberation fonts-dejavu fonts-droid-fallback fonts-noto fonts-roboto openbox qterminal xscreensaver pulseaudio
echo "/dev/sda2 /   ext4    defaults    0   0" > /etc/fstab
EOT

# Unmount bindings
umount -l /mnt/sys
umount -l /mnt/proc
umount -l /mnt/dev

# Unmount filesystems
umount -l /mnt/efi
umount -l /mnt

reboot

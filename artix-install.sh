#!/bin/sh

# Skip partitioning


format_partitions()
{
	# Format partitions
	mkfs.ext4 -L ROOT /dev/sda2
	mkfs.ext4 -L HOME /dev/sda3
	mkswap -L SWAP /dev/sda1
	if [ -d /sys/firmware/efi ]; then
		mkfs.fat -F 32 /dev/sda4
		fatlabel /dev/sda4 BOOT
	else
		mkfs.ext4 -L BOOT /dev/sda4
	fi
}

mount_partitions()
{
	# Mount Partitions
	swapon /dev/disk/by-label/SWAP
	mount /dev/disk/by-label/ROOT /mnt
	[ ! -d /mnt/boot ] && mkdir /mnt/boot
	[ ! -d /mnt/home ] && mkdir /mnt/home
	mount /dev/disk/by-label/HOME /mnt/home
	mount /dev/disk/by-label/BOOT /mnt/boot
}

set_ethernet()
{
	iface="eth0"

	rfkill unblock 0
	if ip a | grep -q "inet .*${iface}" && 
		ip link show "$iface" | grep -q "state UP"; then
		echo "Ethernet connected."
	elif
		echo "Ethernet not connected."
		echo "Running dhclient..."
		dhclient "$iface"	
	fi	
}

install_sys()
{
	basestrap /mnt base base-devel seatd seatd-openrc
	basestrap /mnt linux linux-firmware
}

fstab_n_chroot()
{
	fstabgen_data="$(fstabgen -U /mnt)"
	echo "Fstabgen data:"
	echo "$fstabgen_data"
	echo "$fstabgen_data" >> /mnt/etc/fstab

	read "Press enter key to chroot..."
	artix-chroot /mnt
}

format_partitions
mount_partitions
set_ethernet
install_sys
fstab_n_chroot

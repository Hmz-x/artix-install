#!/bin/sh

# Program data
IFACE="eth0"
ZONE="America/Indiana/Indianapolis"
LOCALE_1="en_US ISO-8859-1"
LOCALE_2="en_US.UTF-8 UTF-8"
boot_sys="BIOS"
PROGRAM_NAME="artix-install.sh"
PROGRAM_HELP=\
"
usage: ${PROGRAM_NAME} [install_base] [config_base]" 


# Skip partitioning

determine_boot()
{
	if [ -d /sys/firmware/efi ]; then
		boot_sys="UEFI"
	else
		boot_sys="BIOS"
	fi
}

format_partitions()
{
	# Format partitions
	mkfs.ext4 -L ROOT /dev/sda2
	mkfs.ext4 -L HOME /dev/sda3
	mkswap -L SWAP /dev/sda1
	if [ "$boot_sys" = "UEFI" ]; then
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

	rfkill unblock 0
	if ip a | grep -q "inet .*${IFACE}" && ip link show "$IFACE" | grep -q "state UP"; then
		echo "Ethernet connected."
	else
		echo "Ethernet not connected."
		echo "Running dhclient..."
		dhclient "$IFACE"	
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
	
	read -p "Press enter key confirm fstabgen data..."
	echo "$fstabgen_data" >> /mnt/etc/fstab

	read -p "Press enter key to chroot..."
	artix-chroot /mnt
}

time_config()
{
	ln -sf /usr/share/zoneinfo/"${ZONE}" /etc/localtime
	hwclock --systohc

	echo "$LOCALE_1" > /etc/locale.gen
	echo "$LOCALE_2" >> /etc/locale.gen
	locale-gen
	
	echo "export LANG=\"${LOCALE_2}\"" > /etc/locale.conf
	echo "export LC_COLLATE=\"C\"" > /etc/locale.conf
}

set_bootloader()
{
	pacman -S vim grub os-prober efibootmgr
	if [ "$boot_sys" = "BIOS" ]; then
		grub-install --recheck /dev/sda
	else
		grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
	fi
	grub-mkconfig -o /boot/grub/grub.cfg
}

set_users()
{
	echo "Enter new password for root user."
	passwd

	read -p "Enter new username: " username
	useradd -m "$username"	

	echo "Enter new password for $username."
	passwd $username
}

network_config()
{

	read -p "Enter new hostname: " hostname
	echo "$hostname" > /etc/hostname

	echo "127.0.0.1        localhost" > /etc/hosts
	echo "::1			   localhost" >> /etc/hosts
	echo "127.0.0.1        ${hostname}.localhost ${hostname}" >> /etc/hosts

	echo "hostname='${hostname}'" > /etc/conf.d/hostname
	pacman -S dhclient
}

parse_opts()
{
	# Parse and evaluate each option one by one 
	while [ "$#" -gt 0 ]; do
		case "$1" in
			install_base)
				determine_boot
				format_partitions
				mount_partitions
				set_ethernet
				install_sys
				fstab_n_chroot;;
			config_base)
				determine_boot
				time_config
				set_bootloader
				set_users
				network_config;;
			-h|--help)
				printf -- "%s\n" "$PROGRAM_HELP"
				exit 0;;
			*) 
				echo "Unknown option '$1'";;
		esac
		shift
	done
}

parse_opts "$@"

#!/bin/sh

# Program config data
IFACE="eth0"
ZONE="America/Indiana/Indianapolis"
LOCALE_1="en_US ISO-8859-1"
LOCALE_2="en_US.UTF-8 UTF-8"

# Program constant data
DOTFILES_REPO='https://github.com/Hmz-x/dotfiles'
YAY_REPO='https://aur.archlinux.org/yay.git'
PROGRAM_NAME="artix-install.sh"
PROGRAM_HELP=\
"
usage: ${PROGRAM_NAME} [install_base] [config_base] [config_fresh]" 

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

set_time()
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

get_username()
{
	read -p "Enter username: " user
}

set_groups()
{
	groupadd seatd

	usermod root -a -G audio,input,seatd
	usermod "$user" -a -G network,wheel,audio,disk,input,storage,video,seatd
}

set_yay()
{	
	# Update packages & install git
	pacman -Syu
	pacman -S git

	cd "/home/${user}/.local/builds"
	git clone "$YAY_REPO"
	cd yay
	makepkg -si
}

install_packages()
{
	# Packages by line: X stuff, language utils, workflow utils, general utils, 
	# fonts, WM stuff
	yay -S xorg-server \
	cmake python3 \
	vim rxvt-unicode zathura-git zathura-pdf-poppler-git \
	man-db aspell aspell-en mpv \ 
	noto-fonts noto-fonts-emoji noto-fonts-extra ttf-font-awesome \
	herbstluftwm timeshift pulseaudio pulseaudio-alsa pamixer-git lemonbar-xft-git \
	mpc-git mpd
}

set_home()
{
	mkdir -p "/home/${user}/Documents/pics" "/home/${user}/Videos" \
		"/home/${user}/Music" "/home/${user}/Downloads"
}

set_dotlocal()
{
	# Create .local directories
	mkdir -p "/home/${user}/.local/bin" "/home/${user}/.local/src" \
		"/home/${user}/.local/lib" "/home/${user}/.local/share" \
		"/home/${user}/.local/builds"
	
	# Set up dotfiles dir
	cd "/home/${user}/.local/"
	git clone "$DOTFILES_REPO"

	# Bash stuff
	cp "/home/${user}/.local/dotfiles/bash/.bashrc" "/home/${user}/"
	cp "/home/${user}/.local/dotfiles/bash/.bashrc" /root/
	cp "/home/${user}/.local/dotfiles/bash/.bash_profile" "/home/${user}/"

	# X stuff
	cp "/home/${user}/.local/dotfiles/.xinitrc" "/home/${user}/"
	cp "/home/${user}/.local/dotfiles/.Xresources" "/home/${user}/"

	# WM, System, & Misc stuff
	cp -r "/home/${user}/.local/dotfiles/WM" "/home/${user}/.local/bin/"
	cp -r "/home/${user}/.local/dotfiles/misc" "/home/${user}/.local/bin/"
	cp -r "/home/${user}/.local/dotfiles/system" "/home/${user}/.local/bin/"

	# Etc stuff
	cp "/home/${user}/.local/dotfiles/etc/"* /etc/

	# Herbstluftwm stuff
	cp "/home/${user}/.local/dotfiles/herbstluftwm/autostart" \
		"/home/${user}/.config/herbstherbstluftwm/"
	
	# Mpd stuff
	mkdir "/home/${user}/.config/mpd/"
	cp "/home/${user}/.local/dotfiles/mpd/mpd.conf" "/home/${user}/.config/mpd/"

	# Vim stuff
	cp "/home/${user}/.local/dotfiles/vim/.vimrc" "/home/${user}/"
}

parse_opts()
{
	if (($UID!=0)); then
		echo "Run as root. Exitting." 2>&1
		exit 1
	fi

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
				set_time
				set_bootloader
				set_users
				network_config;;
			config_fresh)
				get_username
				set_groups
				set_yay
				install_packages
				set_home
				set_dotlocal;;
			-h|--help)
				printf -- "%s\n" "$PROGRAM_HELP"
				exit 0;;
			*) 
				echo "Unknown option '$1'";;
		esac
		shift
	done
}

parse_opts $@

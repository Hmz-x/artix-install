#!/bin/sh

# HOW TO USE
# 1) Boot into live environment
# 2) Mount usb and copy artix-install.sh to /root and unmount usb
# 3) Have ethernet connected
# 4) Format partitions sda2 30G (root), sda1 1G (swap), sda4 1G (boot), sda3 rest (home)
# 5) Run /root/artix-install.sh -i INIT_SYS install_base
# 6) Enter bash shell and sudo su
# 7) Repeat #2
# 8) Run /root/artix-install.sh -i INIT_SYS config_base
# 9) exit bash shell, exit chroot environment, umount -R /mnt, reboot, remove installation media
# 10) Run /root/artix-install.sh -i INIT_SYS config_fresh
# 11) Log back in as regular user. Source ~/.local/bin/artix-install/artix-install.sh. 
# 12) Run init_sys=INIT_SYS; set_yay; install_packages
# 13) Run sudo artix-install.sh -i INIT_SYS finish_setup
# 14) Reboot

# Program config data
IFACE="eth0"
ZONE="America/Indiana/Indianapolis"
LOCALE_1="en_US ISO-8859-1"
LOCALE_2="en_US.UTF-8 UTF-8"

# Program constant data
DOTFILES_REPO='https://github.com/Hmz-x/dotfiles'
YAY_REPO='https://aur.archlinux.org/yay.git'
PROGRAM_NAME="artix-install.sh"
PROGRAM_HELP="usage: ${PROGRAM_NAME} [-i|--init INIT_SYS] [install_base] [config_base] [config_fresh]" 

root_check()
{
	if (($UID!=0)); then
		echo "Run as root. Exitting." 2>&1
		exit 1
	fi
}

confirm_in()
{
	input="$1"
	read -p "${input} - confirm input [Y/n]: " user_ans

	if [ -n "$user_ans" ] && [ "$user_ans" != "y" ] && [ "$user_ans" != "Y" ]; then
		echo "Input is not confirmed. Exitting." 2>&1
		exit 1
	fi
}

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
	basestrap /mnt base base-devel "$init_sys" "seatd-${init_sys}"
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
	
	locale_str="$(echo "$LOCALE_2" | cut -d ' ' -f 1)"
	echo "export LANG=\"${locale_str}\"" > /etc/locale.conf
	echo "export LC_COLLATE=\"C\"" >> /etc/locale.conf
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
	confirm_in "$username"
	useradd -m "$username"	

	echo "Enter new password for $username."
	passwd "$username"
}

network_config()
{

	read -p "Enter new hostname: " hostname
	confirm_in "$hostname"
	echo "$hostname" > /etc/hostname

	echo "127.0.0.1        localhost" > /etc/hosts
	echo "::1			   localhost" >> /etc/hosts
	echo "127.0.0.1        ${hostname}.localhost ${hostname}" >> /etc/hosts
	
	# extra openrc network configuration step
	[ "$init_sys" = "openrc" ] && echo "hostname='${hostname}'" > /etc/conf.d/hostname

	pacman -S dhclient
}

get_username()
{
	read -p "Enter username: " user
	confirm_in "$user"

	# Add user if user does not exist on system
	id "$user" &> /dev/null || { useradd -m "$user" && passwd "$user"; }
}

set_groups()
{
	groupadd seatd

	usermod root -a -G audio,input,seatd
	usermod "$user" -a -G network,wheel,audio,disk,input,storage,video,seatd
}

set_home()
{
	install -d --owner="$user" --group="$user" --mode=755 \
		"/home/${user}/Documents" "/home/${user}/Documents/pics" "/home/${user}/Videos" \
		"/home/${user}/Music" "/home/${user}/Downloads" "/home/${user}/.local/" \
		"/home/${user}/.local/builds"
}

set_yay()
{	
	# Update packages & install git
	sudo pacman -Syu
	sudo pacman -S git go
	git config --global credential.helper store

	cd "/home/${user}/.local/builds" && git clone "$YAY_REPO" && cd yay && makepkg -si
}

install_packages()
{
	[ -z "$init_sys" ] && echo "init_sys is not set. Returning" && return

	# Packages by line: X stuff, language utils, workflow utils, general utils, 
	# media utils, fonts, WM stuff + GUI programs
	yay -S xorg-server xorg-xinit \
	cmake python python-pip cxxopts-git jre-openjdk \
	vim imagemagick xterm alacritty-git zathura-git zathura-pdf-poppler-git dmenu \
	man-db aspell aspell-en acpi networkmanager networkmanager-${init_sys} nm-connection-editor xclip \
	openssh openssh-${init_sys} openntpd openntpd-${init_sys} cronie cronie-${init_sys} \
	notify-send.sh xfce4-notifyd abeep-git scrot ccrypt \
	ffmpeg mpv youtube-dl deluge-gtk deluge-${init_sys} \
	noto-fonts noto-fonts-emoji noto-fonts-extra ttf-font-awesome \
	herbstluftwm picom feh timeshift pulseaudio pulseaudio-alsa pamixer-git redshift polybar \
	lemonbar-xft-git mpc-git mpd firefox librewolf-bin dolphin qt5ct oxygen oxygen-icons oxygen-cursors ttf-oxygen-gf
	
	# Pip packages
	pip3 install pirate-get python-spotdl
	
	# Repositories
	cd "/home/${user}/.local/builds/" && 
		git clone "https://github.com/sysstat/sysstat" && cd sysstat && ./configure && make
	cd "/home/${user}/.local/builds/sysstat/" && sudo make install
}

set_dotlocal()
{
	# Set up dotfiles dir
	su "$user" -c "git clone \"$DOTFILES_REPO\" \"/home/${user}/.local/dotfiles\""
	"/home/${user}/.local/dotfiles/dotfiles-install.sh" "$user"

	# Copy artix-install to user /home/${user}/.local/bin/
	cp -vr /root/artix-install "/home/${user}/.local/bin"

	# Change owner to be $user
	chown -R "${user}:${user}" "/home/${user}/.local/bin/artix-install"

	# Reboot for changes to sudoers file to take place
	read -p "Press enter key to reboot in order for sudo permissions to apply to user..."
	echo "Log back in as regular user after reboot..."
	sleep 3
	reboot
}

set_services()
{
	# Set up services
	if [ "$init_sys" = "openrc" ]; then
		rc-update add ntpd boot default
		rc-update add sshd default
		rc-update add deluged default
		rc-update add cronie default
	fi
}

set_vim_plugins()
{
	su "$user" -c "git clone https://github.com/VundleVim/Vundle.vim.git \
		\"/home/${user}/.vim/bundle/Vundle.vim\""
	su "$user" -c "vim +PluginInstall +qall"
}

parse_opts()
{
	
	# Set default init sys to be openrc
	init_sys="openrc"

	# Parse and evaluate each option one by one 
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-i|--init)
				init_sys="$2"
				shift;;
			install_base)
				root_check
				determine_boot
				format_partitions
				mount_partitions
				set_ethernet
				install_sys
				fstab_n_chroot;;
			config_base)
				root_check
				determine_boot
				set_time
				set_bootloader
				set_users
				network_config;;
			config_fresh)
				root_check
				set_ethernet
				get_username
				set_groups
				set_home
				set_dotlocal;;
			finish_setup)
				root_check
				set_services
				set_vim_plugins;;
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

#!/bin/bash
#
# XanMod kernel and BBRv3 Bash Script
# Author: github.com/opiran-club
#
# It provides options to install required packages, configure XanMod kernel and BBRv3
# download the appropriate configuration and program.
#
# supported architectures: x86_64, amd64
# Supported operating systems: Ubuntu 18.04/20.04/22.04 , Debian 10/11
#
# Usage:
#   - Run the script with root privileges.
#   - Follow the on-screen prompts to install, configure, or uninstall
#
# For more information and updates, visit github.com/opiran-club and @opiranclub on telegram.
#
# Disclaimer:
# This script comes with no warranties or guarantees. Use it at your own risk.

CYAN="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
BLUE="\e[94m"
MAGENTA="\e[95m"
NC="\e[0m"

ask_reboot() {
echo ""
echo -e "\n ${YELLOW}Reboot now? (Recommended) ${GREEN}[y/n]${NC}"
echo ""
read reboot
case "$reboot" in
        [Yy]) 
        systemctl reboot
        ;;
        *) 
        return 
        ;;
    esac
exit
}

press_enter() {
    echo -e "\n ${RED}Press Enter to continue... ${NC}"
    read
}

# Define logo segments
logo1="     ______    _______    __      _______        __      _____  ___   "
logo2="    /      \  |   __  \  |  \    /       \      /  \     \    \|   \  "
logo3="   /  ____  \ (  |__)  ) |   |  |         |    /    \    |.\   \    | "
logo4="  /  /    )  )|   ____/  |   |  |_____/   )   /' /\  \   |: \   \   | "
logo5=" (  (____/  / (   /      |.  |   //      /   //  __'  \  |.  \    \.| "
logo6="  \        / /    \      /\  |\ |:  __   \  /   /  \\   \ |    \    \| "
logo7="   \_____/ (_______)    (__\_|_)|__|  \___)(___/    \___)\___|\____\) "

logo() {
echo -e "${BLUE}${logo1:0:24}${RED}${logo1:24:19}${WHITE}${logo1:43:14}${GREEN}${logo1:57}${NC}"
echo -e "${BLUE}${logo2:0:24}${RED}${logo2:24:19}${WHITE}${logo2:43:14}${GREEN}${logo2:57}${NC}"
echo -e "${BLUE}${logo3:0:24}${RED}${logo3:24:19}${WHITE}${logo3:43:14}${GREEN}${logo3:57}${NC}"
echo -e "${BLUE}${logo4:0:24}${RED}${logo4:24:19}${WHITE}${logo4:43:14}${GREEN}${logo4:57}${NC}"
echo -e "${BLUE}${logo5:0:24}${RED}${logo5:24:19}${WHITE}${logo5:43:14}${GREEN}${logo5:57}${NC}"
echo -e "${BLUE}${logo6:0:24}${RED}${logo6:24:19}${WHITE}${logo6:43:14}${GREEN}${logo6:57}${NC}"
echo -e "${BLUE}${logo7:0:24}${RED}${logo7:24:19}${WHITE}${logo7:43:14}${GREEN}${logo7:57}${NC}"
}

if [ "$EUID" -ne 0 ]; then
    echo -e "\n ${RED}This script must be run as root.${NC}"
    exit 1
fi

cpu_level() {
    os=""
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        case $ID in
            "debian" | "ubuntu")
                os="Debian/Ubuntu"
                ;;
            "centos")
                os="CentOS"
                ;;
            "fedora")
                os="Fedora"
                ;;
            "arch")
                os="Arch"
                ;;
            *)
                os="Unknown"
                ;;
        esac
    fi

cpu_support_info=$(/usr/bin/awk -f <(wget -qO - https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/checkcpu.sh))
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo -e "${MAGENTA}Current CPU Level:${GREEN} x86-64 Level $cpu_support_level${NC}"
        return $cpu_support_level
    else
        echo -e "${RED}OS or CPU level is not supported by the XanMod kernel and cannot be installed.${NC}"
        return 0
    fi
}

XANMOD_GRUB_HELPER="/usr/local/bin/xanmod-set-grub-default"
XANMOD_GRUB_HOOK="/etc/kernel/postinst.d/zz-xanmod-grub-default"

# GRUB picks the newest kernel version for the default boot entry; a stock 7.x
# image can stay ahead of XanMod 6.x unless GRUB_DEFAULT points at XanMod explicitly.
# After a XanMod package upgrade the menu title changes — GRUB_DEFAULT must be updated too.
install_xanmod_grub_helper() {
    mkdir -p /etc/kernel/postinst.d "$(dirname "$XANMOD_GRUB_HELPER")"

    cat <<'EOF' > "$XANMOD_GRUB_HELPER"
#!/bin/bash
set -e

grub_cfg="/boot/grub/grub.cfg"
mode="${1:-refresh}"

if [ ! -f "$grub_cfg" ]; then
    echo "GRUB configuration not found at ${grub_cfg}." >&2
    exit 1
fi

if [ "$mode" = "refresh" ]; then
    update-grub
fi

krel=$(ls -1 /boot/vmlinuz-*xanmod* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
if [ -z "$krel" ]; then
    echo "No XanMod kernel image found under /boot." >&2
    exit 1
fi

read -r submenu entry < <(awk -v krel="$krel" '
    /^submenu / {
        submenu = ""
        if (match($0, /'\''[^'\'']+'\''/)) {
            submenu = substr($0, RSTART + 1, RLENGTH - 2)
        }
    }
    /menuentry / && index($0, krel) && $0 !~ /recovery mode/ {
        if (match($0, /'\''[^'\'']+'\''/)) {
            entry = substr($0, RSTART + 1, RLENGTH - 2)
            if (submenu != "") {
                print submenu, entry
            } else {
                print "", entry
            }
            exit
        }
    }
' "$grub_cfg")

if [ -z "$entry" ]; then
    echo "Could not find a GRUB menu entry for kernel ${krel}." >&2
    exit 1
fi

if [ -n "$submenu" ]; then
    grub_default="${submenu}>${entry}"
else
    grub_default="$entry"
fi

if [ ! -f /etc/default/grub.bak.xanmod ]; then
    cp /etc/default/grub /etc/default/grub.bak.xanmod
fi

grub_default_escaped=${grub_default//\\/\\\\}
grub_default_escaped=${grub_default_escaped//|/\\|}

if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
    sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"${grub_default_escaped}\"|" /etc/default/grub
else
    echo "GRUB_DEFAULT=\"${grub_default_escaped}\"" >> /etc/default/grub
fi

if [ "$mode" = "refresh" ]; then
    update-grub
fi

echo "GRUB default set to: ${grub_default} (kernel ${krel})"
EOF
    chmod 755 "$XANMOD_GRUB_HELPER"

    cat <<EOF > "$XANMOD_GRUB_HOOK"
#!/bin/sh
set -e
case "\$1" in
    *-xanmod*)
        if [ -x "$XANMOD_GRUB_HELPER" ]; then
            "$XANMOD_GRUB_HELPER" refresh
        fi
        ;;
esac
exit 0
EOF
    chmod 755 "$XANMOD_GRUB_HOOK"
}

remove_xanmod_grub_helper() {
    rm -f "$XANMOD_GRUB_HELPER" "$XANMOD_GRUB_HOOK"
}

refresh_xanmod_grub_boot() {
    install_xanmod_grub_helper
    if "$XANMOD_GRUB_HELPER" refresh; then
        echo -e "${GREEN}GRUB updated; newest XanMod kernel is set as the default boot entry.${NC}"
        return 0
    fi
    echo -e "${RED}Failed to refresh GRUB for XanMod.${NC}"
    return 1
}

update_xanmod_grub_menu() {
    clear
    echo ""
    echo -e "${YELLOW}Refresh GRUB after a XanMod kernel upgrade${NC}"
    echo ""
    echo -e "${CYAN}This runs update-grub and points GRUB_DEFAULT at the newest XanMod image in /boot.${NC}"
    echo ""
    refresh_xanmod_grub_boot
    press_enter
}

install_xanmod() {
    clear
    cpu_support_info=$(/usr/bin/awk -f <(wget -qO - https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/checkcpu.sh))
    
    if [[ $cpu_support_info == "CPU supports x86-64-v"* ]]; then
        cpu_support_level=${cpu_support_info#CPU supports x86-64-v}
        echo -e "${CYAN}Current CPU Level: x86-64 Level $cpu_support_level${NC}"
    else
        echo -e "${RED}OS or CPU level is not supported by the XanMod kernel and cannot be installed.${NC}"
        return 1
    fi
    echo ""
    echo ""
    echo -e "${YELLOW}     Installing XanMod kernel${NC}"
    echo ""
    echo -e "${CYAN}Kernel official website: https://xanmod.org${NC}"
    echo -e "${CYAN}SourceForge: https://sourceforge.net/projects/xanmod/files/releases/lts/${NC}"
    echo ""
    echo ""
    echo -ne "${YELLOW}Do you want to continue downloading and installing the XanMod kernel? [y/n]:${NC}   "
    read continue

    if [[ $continue == [Yy] ]]; then
        echo ""
        echo ""
        wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/xanmod-release.list

        temp_folder=$(mktemp -d)
        cd $temp_folder

        case $cpu_support_level in
            1)
                apt-get update
                apt-get install linux-xanmod-lts-x64v1 -y
                ;;
            2)
                apt-get update
                apt-get install linux-xanmod-lts-x64v2 -y
                ;;
            3)
                apt-get update
                apt-get install linux-xanmod-lts-x64v3 -y
                ;;
            4)
                apt-get update
                apt-get install linux-xanmod-lts-x64v3 -y
                ;;
            *)
                echo -e "${RED}Your CPU is not supported by the XanMod kernel and cannot be installed.${NC}"
                return 1
                ;;
        esac

        echo -e "${GREEN}The XanMod kernel has been installed successfully.${NC}"
        press_enter
        sleep 0.5
        clear
        echo ""
        echo -e "${GREEN}       GRUB boot updating ${NC}"
        echo ""
        echo ""
        echo -ne "${YELLOW}Do you need to update the GRUB boot configuration? (y/n) [Default: y]:${NC}    "
        read grub

        case $grub in
            [Yy]|"")
                if ! refresh_xanmod_grub_boot; then
                    echo ""
                    echo -e "${YELLOW}Set GRUB_DEFAULT in /etc/default/grub to the XanMod menu item, then run update-grub.${NC}"
                fi
                ;;
            [Nn])
                echo -e "${RED}It is not recommended, but the optimization has been aborted.${NC}"
                ;;
            *)
                echo -e "${RED}Invalid option, skipping GRUB boot configuration update.${NC}"
                ;;
        esac
    else
        echo -e "${RED}XanMod kernel installation failed.${NC}"
    fi
}

uninstall_xanmod() {
    clear
    current_kernel_version=$(uname -r)

    if [[ $current_kernel_version == *-xanmod* ]]; then
        echo -e "${CYAN}Current kernel: ${GREEN}$current_kernel_version${NC}"
        echo -e "${RED}Uninstalling XanMod Kernel...${NC}"
        echo ""
        echo -ne "${GREEN}Do you want to uninstall the XanMod kernel and restore the original kernel? (y/n): ${NC}"
        read confirm

        if [[ $confirm == [yY] ]]; then
            echo -e "${GREEN}Uninstalling XanMod kernel and restoring the original kernel...${NC}"
            for i in $(seq 1 4); do
            apt-get purge linux-xanmod-x64v$i -y
            done
            apt-get update
            apt-get autoremove -y
            remove_xanmod_grub_helper
            if [ -f /etc/default/grub.bak.xanmod ]; then
                cp /etc/default/grub.bak.xanmod /etc/default/grub
            fi
            update-grub

            if [ $? -eq 0 ]; then
                echo ""
                echo -e "${GREEN}The XanMod kernel has been uninstalled, and the original kernel has been restored.${NC}"
                echo -e "${GREEN}The GRUB boot configuration has been updated. Please reboot to take effect.${NC}"
            else
                echo ""
                echo -e "${RED}XanMod kernel uninstallation failed.${NC}"
            fi
        else
            echo ""
            echo -e "${RED}Canceled the uninstall operation.${NC}"
        fi
    else
        echo ""
        echo -e "${RED}The current kernel is not the XanMod kernel, and the uninstall operation cannot be performed.${NC}"
    fi
}

bbrv3() {
    clear
    echo ""
    echo ""
    echo -e "${YELLOW}Are you sure you want to optimize kernel parameters for better network performance? (y/n): ${NC}${GREEN}   "
    read optimize_choice
    echo -e "${NC}"
    case $optimize_choice in
        y|Y)
            clear
            sysctl_dropin="/etc/sysctl.d/99-bbr-optimizations.conf"
            mkdir -p /etc/sysctl.d

            echo -e "${YELLOW}Backing up original kernel parameter configuration... ${NC}"
            if [ -f /etc/sysctl.conf ]; then
                cp /etc/sysctl.conf /etc/sysctl.conf.bak
                # Drop-in files are loaded before /etc/sysctl.conf, so previously
                # appended BBRv3 lines would override 99-bbr-optimizations.conf.
                sed -i \
                    -e '/^# BBRv3 Optimization for Better Network Performance$/d' \
                    -e '/^net\.ipv4\.tcp_timestamps = 1$/d' \
                    -e '/^net\.ipv4\.tcp_sack = 1$/d' \
                    -e '/^net\.ipv4\.tcp_window_scaling = 1$/d' \
                    -e '/^net\.core\.rmem_max = 16777216$/d' \
                    -e '/^net\.core\.wmem_max = 16777216$/d' \
                    -e '/^net\.ipv4\.tcp_rmem = 4096 87380 16777216$/d' \
                    -e '/^net\.ipv4\.tcp_wmem = 4096 65536 16777216$/d' \
                    -e '/^net\.ipv4\.tcp_congestion_control = bbr$/d' \
                    /etc/sysctl.conf
            fi
            if [ -f "$sysctl_dropin" ]; then
                cp "$sysctl_dropin" "${sysctl_dropin}.bak"
            fi

            echo -e "${YELLOW}Optimizing kernel parameters for better network performance... ${NC}"

            if cat <<EOL > "$sysctl_dropin"
# BBRv3 Optimization for Better Network Performance
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
EOL
            then
                echo -e "${GREEN}Created ${sysctl_dropin}.${NC}"
            else
                echo -e "${RED}Failed to create ${sysctl_dropin}. Restoring the original configuration...${NC}"
                if [ -f "${sysctl_dropin}.bak" ]; then
                    mv "${sysctl_dropin}.bak" "$sysctl_dropin"
                fi
                if [ -f /etc/sysctl.conf.bak ]; then
                    mv /etc/sysctl.conf.bak /etc/sysctl.conf
                fi
                return
            fi

            if sysctl -p "$sysctl_dropin"; then
                echo -e "${GREEN}Kernel parameter optimization for better network performance was successful.${NC}"
            else
                echo -e "${YELLOW}Settings are saved in ${sysctl_dropin}. Applying them in the current session failed; they stay on disk and load on the next boot.${NC}"
            fi
            ;;
        n|N)
            echo ""
            echo -e "${RED}Canceled kernel parameter optimization.${NC}"
            ;;
        *)
            echo ""
            echo -e "${RED}Invalid input. Optimization canceled.${NC}"
            ;;
    esac
}

while true; do
    linux_version=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
    kernel_version=$(uname -r)
    tg_title="https://t.me/OPIran-Official"
    yt_title="youtube.com/@opiran-inistitute"
    clear
    logo
    echo -e "\e[93m╔═══════════════════════════════════════════════╗\e[0m"  
    echo -e "\e[93m║            \e[96mBBRv3 using xanmod kernel          \e[93m║\e[0m"   
    echo -e "\e[93m╠═══════════════════════════════════════════════╣\e[0m"
    echo ""
    echo -e "${CYAN}   ${tg_title}   ${NC}"
    echo -e "${CYAN}   ${yt_title}   ${NC}"
    echo ""
    printf "\e[93m+-----------------------------------------------+\e[0m\n" 
    echo ""
    echo -e "${MAGENTA}linux version Info：${GREEN}${linux_version}${NC}"
    echo -e "${MAGENTA}kernel Info：${GREEN}${kernel_version}${NC}"
    cpu_level
    echo ""
    echo -e "${RED} !! TIP !! ${NC}"
    echo ""
    echo -e "${CYAN}Supported OS: ${GREEN} Ubuntu / Debian ${NC}"
    echo -e "${CYAN}Supported CPU level ${GREEN} [1/2/3/4] ${NC}"
    echo ""
    printf "\e[93m+-----------------------------------------------+\e[0m\n" 
    echo ""
    echo -e "${GREEN} 1) ${NC} Install XanMod kernel & BBRv3 & Grub boot conf. ${NC}"
    echo -e "${GREEN} 2) ${NC} Uninstall XanMod kernel and restore to default ${NC}"
    echo -e "${GREEN} 3) ${NC} Update GRUB default after XanMod kernel upgrade ${NC}"
    echo ""
    echo -e "${GREEN} E) ${NC} Exit the menu${NC}"
    echo ""
    echo -ne "${GREEN}Select an option: ${NC}  "
    read choice

    case $choice in
 
        1)
            install_xanmod
            bbrv3
            ask_reboot
            ;;
        2)
            uninstall_xanmod
            ask_reboot
            ;;
        3)
            update_xanmod_grub_menu
            ;;
        E|e)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a valid option."
            ;;
    esac

    echo -e "\n${RED}Press Enter to continue... ${NC}"
    read
done

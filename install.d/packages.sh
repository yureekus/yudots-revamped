#!/usr/bin/env bash

bootstrap_build_tools() {
    require_commands pacman sudo || return 1
    # Install rust up front so makepkg never prompts for a cargo provider.
    run_cmd sudo pacman -S --needed --noconfirm --color always base-devel git rust
}

install_paru_from_source() {
    if command -v paru >/dev/null 2>&1; then
        info "paru is already installed, skipping source build"
        return 0
    fi

    require_commands git makepkg mktemp || return 1

    if [[ -n "$paru_build_dir" && -d "$paru_build_dir" ]]; then
        safe_remove_dir "$paru_build_dir" || return 1
    fi

    paru_build_dir="$(mktemp -d /tmp/yudots-revamped-paru-XXXXXX)" || {
        error "could not create a temporary build directory for paru"
        return 1
    }

    run_cmd git clone https://aur.archlinux.org/paru.git "$paru_build_dir/paru" || return 1
    run_cmd bash -lc "cd '$paru_build_dir/paru' && makepkg -si --noconfirm --needed" || return 1
}

install_package_group() {
    local group_name="$1"
    shift

    local -a packages=("$@")

    require_command paru || return 1
    info "$group_name packages:"
    info "${packages[*]}"

    run_cmd paru -S --needed --noconfirm --skipreview --color always "${packages[@]}"
}

install_required_packages() {
    local -a desktop_packages=(
        dbus
        elogind
        elogind-openrc
        seatd
        power-profiles-daemon
        power-profiles-daemon-openrc
        niri
        xorg-xwayland
        xwayland-satellite
        xdg-desktop-portal-gnome
        polkit-gnome
        waybar
        fuzzel
        mako
        swayidle
        awww
        jack2
        ffmpeg
        zenity
    )

    local -a audio_packages=(
        pipewire
        wireplumber
        pipewire-pulse
        wiremix-git
    )

    local -a app_packages=(
        helium-browser-bin
        visual-studio-code-bin
        vscodium-bin
        flclashx-bin
        dolphin
        ghostty
        fish
        starship
        matugen-bin
        swaylock-effects
        brightnessctl
        fzf
    )


    local -a font_and_theme_packages=(
        ttf-dejavu
        ttf-firacode-nerd
        ttf-liberation
        ttf-ms-fonts
        otf-commit-mono-nerd
        noto-fonts
        noto-fonts-cjk
        noto-fonts-emoji
        noto-fonts-extra
        adw-gtk-theme
        breeze-icons
        breeze-gtk
        qt6ct-kde
        qt5ct-kde
        breeze
        breeze5
    )

    local -a network_packages=(
        bluez
        bluez-openrc
        bluez-utils
        networkmanager
        networkmanager-openrc
    )

    install_package_group "desktop" "${desktop_packages[@]}" || return 1
    install_package_group "audio" "${audio_packages[@]}" || return 1
    install_package_group "apps" "${app_packages[@]}" || return 1
    install_package_group "fonts and themes" "${font_and_theme_packages[@]}" || return 1
    install_package_group "network" "${network_packages[@]}"
}

ensure_video_group_membership() {
    require_commands getent grep id sudo usermod || return 1

    if ! getent group video >/dev/null 2>&1; then
        warn "group 'video' was not found; skipping brightness permission setup"
        return 0
    fi

    if id -nG "$target_user" | grep -qw "video"; then
        info "user $target_user is already in the video group"
        return 0
    fi

    run_cmd sudo usermod -aG video "$target_user" || return 1
    info "added $target_user to video group (effective after relogin/reboot)"
}

install_micmute_led_rule() {
    local target_rule="/etc/udev/rules.d/99-yudots-micmute-led.rules"

    require_commands install sudo || return 1
    run_cmd sudo install -Dm644 "$repo_system_dir/udev/99-yudots-micmute-led.rules" "$target_rule" || return 1

    if command -v udevadm >/dev/null 2>&1; then
        run_cmd sudo udevadm control --reload || return 1
        run_cmd sudo udevadm trigger --subsystem-match=leds || return 1
    else
        warn "udevadm was not found; reload the udev rules manually after install"
    fi
}

install_elogind_lid_lock_config() {
    local target_conf_dir="/etc/elogind/logind.conf.d"
    local target_conf="$target_conf_dir/90-yudots-lid-lock.conf"

    require_commands install sudo || return 1
    run_cmd sudo install -d "$target_conf_dir" || return 1
    run_cmd sudo install -Dm644 "$repo_system_dir/elogind/logind.conf.d/90-yudots-lid-lock.conf" "$target_conf" || return 1

    if command -v loginctl >/dev/null 2>&1; then
        run_cmd sudo loginctl reload || return 1
    else
        warn "loginctl was not found; reload elogind manually after install"
    fi
}


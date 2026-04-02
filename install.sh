#!/usr/bin/env bash

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_config_dir="$script_dir/config"
repo_wallpapers_dir="$script_dir/wallpapers"
repo_system_dir="$script_dir/system"
default_wallpaper_name="yureek_protogen.png"
log_file="/tmp/yudots-revamped-install-$(date +%Y%m%d-%H%M%S).log"

target_user="${USER:-}"
target_home="${HOME:-}"
paru_build_dir=""
networkmanager_service=""
connman_service=""

declare -a service_runlevels=()
declare -a connman_enabled_levels=()
declare -a networkmanager_enabled_levels=()

connman_was_running=0
connman_was_enabled=0
networkmanager_was_running=0
networkmanager_was_enabled=0

use_color=0
if [[ -t 1 ]]; then
    use_color=1
fi

if (( use_color )); then
    c_reset=$'\033[0m'
    c_bold=$'\033[1m'
    c_dim=$'\033[2m'
    c_purple=$'\033[1;35m'
    c_blue=$'\033[1;34m'
    c_cyan=$'\033[1;36m'
    c_green=$'\033[1;32m'
    c_yellow=$'\033[1;33m'
    c_red=$'\033[1;31m'
else
    c_reset=""
    c_bold=""
    c_dim=""
    c_purple=""
    c_blue=""
    c_cyan=""
    c_green=""
    c_yellow=""
    c_red=""
fi

init_log() {
    : > "$log_file" || {
        printf 'could not write log file: %s\n' "$log_file" >&2
        exit 1
    }
}

strip_colors() {
    printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'
}

log_line() {
    local level_color="$1"
    local level_name="$2"
    shift 2

    local message="$*"
    local prefix="${c_purple}[yudots-revamped]${c_reset}"

    printf '%b %b%s%b %s\n' "$prefix" "$level_color" "$level_name" "$c_reset" "$message"
    printf '%s %s %s\n' "[yudots-revamped]" "$level_name" "$(strip_colors "$message")" >> "$log_file"
}

info() {
    log_line "$c_blue" "info" "$@"
}

step() {
    log_line "$c_cyan" "step" "$@"
}

ok() {
    log_line "$c_green" "ok" "$@"
}

warn() {
    log_line "$c_yellow" "warn" "$@"
}

error() {
    log_line "$c_red" "error" "$@"
}

cmd_log() {
    local line="$1"
    local prefix="${c_purple}[yudots-revamped]${c_reset}"
    printf '%b %bcmd%b %s\n' "$prefix" "$c_dim" "$c_reset" "$line"
    printf '%s %s %s\n' "[yudots-revamped]" "cmd" "$(strip_colors "$line")" >> "$log_file"
}

stream_command_output() {
    local line=""

    while IFS= read -r line; do
        cmd_log "$line"
    done
}

run_cmd() {
    info "running: $*"
    "$@" 2>&1 | stream_command_output
    return "${PIPESTATUS[0]}"
}

prompt_retry_or_abort() {
    if [[ ! -t 0 ]]; then
        return 1
    fi

    local reply=""
    while true; do
        printf '%b %bretry%b or %babort%b? [r/a]: ' "${c_purple}[yudots-revamped]${c_reset}" "$c_yellow" "$c_reset" "$c_red" "$c_reset"
        read -r reply || return 1
        reply="${reply,,}"

        case "$reply" in
            r|retry|"")
                return 0
                ;;
            a|abort)
                return 1
                ;;
        esac
    done
}

pause_on_warning() {
    local message="$1"
    local reply=""

    warn "$message"

    if [[ ! -t 0 ]]; then
        return 1
    fi

    while true; do
        printf '%b %bcontinue%b, %bretry%b, or %babort%b? [c/r/a]: ' "${c_purple}[yudots-revamped]${c_reset}" "$c_green" "$c_reset" "$c_yellow" "$c_reset" "$c_red" "$c_reset"
        read -r reply || return 1
        reply="${reply,,}"

        case "$reply" in
            c|continue|"")
                return 0
                ;;
            r|retry)
                return 2
                ;;
            a|abort)
                return 1
                ;;
        esac
    done
}

run_step() {
    local description="$1"
    shift

    while true; do
        step "$description"
        if "$@"; then
            ok "$description"
            return 0
        fi

        error "$description failed"
        if prompt_retry_or_abort; then
            warn "retrying: $description"
            continue
        fi

        return 1
    done
}

cleanup() {
    local exit_code=$?

    if [[ -n "$paru_build_dir" && -d "$paru_build_dir" ]]; then
        rm -rf -- "$paru_build_dir"
    fi

    if (( exit_code == 0 )); then
        ok "cleanup finished"
        info "full log saved to $log_file"
    else
        warn "cleanup finished after a failure"
        warn "full log saved to $log_file"
    fi
}

on_interrupt() {
    error "the installer was interrupted"
    exit 1
}

trap cleanup EXIT
trap on_interrupt INT TERM

check_user_context() {
    if [[ "${EUID}" -eq 0 ]]; then
        error "run this script as your normal user with sudo access, not as root"
        return 1
    fi

    if [[ -z "$target_user" || -z "$target_home" ]]; then
        error "could not detect the target user or home directory"
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required for this installer"
        return 1
    fi

    if ! command -v bash >/dev/null 2>&1; then
        error "bash is required for this installer"
        return 1
    fi

    run_cmd sudo -v || return 1
    info "install target: $target_user"
    info "target home: $target_home"
}

check_repo_layout() {
    if [[ ! -d "$repo_config_dir" ]]; then
        error "missing config directory: $repo_config_dir"
        return 1
    fi

    if [[ ! -f "$repo_config_dir/bash_profile" ]]; then
        error "missing config/bash_profile"
        return 1
    fi

    if [[ ! -d "$repo_wallpapers_dir" ]]; then
        error "missing wallpapers directory: $repo_wallpapers_dir"
        return 1
    fi

    if [[ ! -f "$repo_wallpapers_dir/$default_wallpaper_name" ]]; then
        error "missing default wallpaper: $repo_wallpapers_dir/$default_wallpaper_name"
        return 1
    fi

    if [[ ! -f "$repo_system_dir/udev/99-yudots-micmute-led.rules" ]]; then
        error "missing udev rule: $repo_system_dir/udev/99-yudots-micmute-led.rules"
        return 1
    fi

    if [[ ! -f "$repo_system_dir/elogind/logind.conf.d/90-yudots-lid-lock.conf" ]]; then
        error "missing elogind config: $repo_system_dir/elogind/logind.conf.d/90-yudots-lid-lock.conf"
        return 1
    fi
}

check_supported_system() {
    if [[ ! -r /etc/os-release ]]; then
        error "could not read /etc/os-release"
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    info "detected os: ${PRETTY_NAME:-${NAME:-unknown}}"

    if [[ "${ID:-}" != "artix" ]]; then
        error "this installer only supports artix linux with openrc"
        error "it will not continue on this system"
        error "if you want these dots somewhere else, you will need to port them manually"
        return 1
    fi

    if ! command -v rc-service >/dev/null 2>&1 || ! command -v rc-update >/dev/null 2>&1; then
        error "openrc tools were not found"
        error "this installer will not continue"
        error "if you want these dots somewhere else, you will need to port them manually"
        return 1
    fi

    if [[ ! -d /etc/runlevels ]]; then
        error "openrc runlevels were not found"
        error "this installer will not continue"
        error "if you want these dots somewhere else, you will need to port them manually"
        return 1
    fi

    if [[ ! -e /run/openrc/softlevel && ! -d /run/openrc ]]; then
        error "openrc runtime markers were not detected"
        error "this does not look like an artix linux system currently running openrc"
        error "the installer will not continue"
        error "if you want these dots somewhere else, you will need to port them manually"
        return 1
    fi

    ok "artix linux with openrc detected"
}

bootstrap_build_tools() {
    run_cmd sudo pacman -S --needed --noconfirm --color always base-devel git
}

install_paru_from_source() {
    if command -v paru >/dev/null 2>&1; then
        info "paru is already installed, skipping source build"
        return 0
    fi

    if [[ -n "$paru_build_dir" && -d "$paru_build_dir" ]]; then
        rm -rf -- "$paru_build_dir"
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
        swww
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
        pacman-contrib
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

    run_cmd sudo install -d "$target_conf_dir" || return 1
    run_cmd sudo install -Dm644 "$repo_system_dir/elogind/logind.conf.d/90-yudots-lid-lock.conf" "$target_conf" || return 1

    if command -v loginctl >/dev/null 2>&1; then
        run_cmd sudo loginctl reload || return 1
    else
        warn "loginctl was not found; reload elogind manually after install"
    fi
}

find_service_name() {
    local candidate=""

    for candidate in "$@"; do
        if [[ -e "/etc/init.d/$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

collect_service_runlevels() {
    local service_name="$1"
    local level_dir=""

    service_runlevels=()

    for level_dir in /etc/runlevels/*; do
        [[ -d "$level_dir" ]] || continue
        if [[ -e "$level_dir/$service_name" ]]; then
            service_runlevels+=("$(basename "$level_dir")")
        fi
    done
}

service_is_running() {
    local service_name="$1"
    sudo rc-service "$service_name" status >/dev/null 2>&1
}

disable_service_everywhere() {
    local service_name="$1"
    local level=""

    collect_service_runlevels "$service_name"

    if (( ${#service_runlevels[@]} == 0 )); then
        info "$service_name is not enabled in any openrc runlevel"
        return 0
    fi

    for level in "${service_runlevels[@]}"; do
        run_cmd sudo rc-update del "$service_name" "$level" || return 1
    done
}

enable_service_in_default() {
    local service_name="$1"

    collect_service_runlevels "$service_name"
    if (( ${#service_runlevels[@]} == 0 )); then
        run_cmd sudo rc-update add "$service_name" default || return 1
    else
        info "$service_name is already enabled in: ${service_runlevels[*]}"
    fi

    if service_is_running "$service_name"; then
        info "$service_name is already running"
        return 0
    fi

    run_cmd sudo rc-service "$service_name" start
}

enable_core_services() {
    local dbus_service=""
    local elogind_service=""
    local bluetooth_service=""
    local power_profiles_service=""

    dbus_service="$(find_service_name dbus)" || {
        error "could not find the openrc service for dbus"
        return 1
    }

    elogind_service="$(find_service_name elogind)" || {
        error "could not find the openrc service for elogind"
        return 1
    }

    enable_service_in_default "$dbus_service" || return 1
    enable_service_in_default "$elogind_service" || return 1

    if power_profiles_service="$(find_service_name power-profiles-daemon)"; then
        enable_service_in_default "$power_profiles_service" || return 1
    else
        warn "power-profiles-daemon openrc service was not found, skipping it"
    fi

    if bluetooth_service="$(find_service_name bluetoothd)"; then
        enable_service_in_default "$bluetooth_service" || return 1
    else
        warn "bluetooth openrc service was not found, skipping it"
    fi
}

record_network_state() {
    networkmanager_service="$(find_service_name NetworkManager networkmanager)" || {
        error "could not find the openrc service for networkmanager"
        return 1
    }

    connman_service="$(find_service_name connmand connman || true)"

    collect_service_runlevels "$networkmanager_service"
    networkmanager_enabled_levels=("${service_runlevels[@]}")
    networkmanager_was_enabled=0
    if (( ${#networkmanager_enabled_levels[@]} > 0 )); then
        networkmanager_was_enabled=1
    fi

    networkmanager_was_running=0
    if service_is_running "$networkmanager_service"; then
        networkmanager_was_running=1
    fi

    connman_enabled_levels=()
    connman_was_enabled=0
    connman_was_running=0

    if [[ -n "$connman_service" ]]; then
        collect_service_runlevels "$connman_service"
        connman_enabled_levels=("${service_runlevels[@]}")
        if (( ${#connman_enabled_levels[@]} > 0 )); then
            connman_was_enabled=1
        fi
        if service_is_running "$connman_service"; then
            connman_was_running=1
        fi
    fi
}

verify_networkmanager() {
    local attempt=""
    local daemon_ready=1
    local running_state=""

    for attempt in 1 2 3 4 5; do
        info "networkmanager daemon check attempt $attempt of 5"

        if command -v nmcli >/dev/null 2>&1; then
            running_state="$(nmcli -t -f RUNNING general 2>/dev/null || true)"
            if [[ "$running_state" == "running" ]]; then
                daemon_ready=0
                run_cmd nmcli general status || true
                break
            fi
        elif pgrep -x NetworkManager >/dev/null 2>&1; then
            daemon_ready=0
            break
        fi

        sleep 2
    done

    if (( daemon_ready != 0 )); then
        error "networkmanager did not become ready after being enabled"
        return 1
    fi

    for attempt in 1 2 3 4 5; do
        info "networkmanager connectivity check attempt $attempt of 5"

        if run_cmd ping -c 1 -W 5 1.1.1.1 && run_cmd ping -c 1 -W 5 google.com; then
            return 0
        fi

        sleep 2
    done

    warn "networkmanager is running, but internet connectivity is not ready yet"
    warn "this is expected on some first installs while networkmanager waits for the first connection"
    return 0
}

restore_service_runlevels() {
    local service_name="$1"
    shift

    local level=""
    local -a saved_levels=("$@")

    if (( ${#saved_levels[@]} == 0 )); then
        return 0
    fi

    for level in "${saved_levels[@]}"; do
        run_cmd sudo rc-update add "$service_name" "$level" || return 1
    done
}

rollback_network_changes() {
    warn "rolling back the network changes so you are not stranded"

    if [[ -n "$networkmanager_service" ]]; then
        if (( ! networkmanager_was_running )); then
            run_cmd sudo rc-service "$networkmanager_service" stop || true
        fi

        if (( ! networkmanager_was_enabled )); then
            disable_service_everywhere "$networkmanager_service" || true
        fi
    fi

    if [[ -n "$connman_service" ]]; then
        restore_service_runlevels "$connman_service" "${connman_enabled_levels[@]}" || true

        if (( connman_was_running )); then
            run_cmd sudo rc-service "$connman_service" start || true
        fi
    fi
}

remove_connman_packages() {
    local -a packages_to_remove=()

    if pacman -Qq connman >/dev/null 2>&1; then
        packages_to_remove+=("connman")
    fi

    if pacman -Qq connman-openrc >/dev/null 2>&1; then
        packages_to_remove+=("connman-openrc")
    fi

    if (( ${#packages_to_remove[@]} == 0 )); then
        info "no connman packages were installed, nothing to remove"
        return 0
    fi

    run_cmd sudo pacman -Rns --noconfirm "${packages_to_remove[@]}"
}

handle_network_stack() {
    local warning_result=0

    record_network_state || return 1

    if (( connman_was_enabled || connman_was_running )); then
        while true; do
            warning_result=0
            pause_on_warning "connman is enabled on this system. the installer will disable it, switch you to networkmanager, test connectivity, and only then remove connman." || warning_result=$?

            case "$warning_result" in
                0)
                    break
                    ;;
                1)
                    error "stopping because the network migration was declined"
                    return 1
                    ;;
                2)
                    warn "asking again before the network migration starts"
                    ;;
            esac
        done

        if (( connman_was_running )); then
            run_cmd sudo rc-service "$connman_service" stop || return 1
        fi

        disable_service_everywhere "$connman_service" || return 1
    elif pacman -Qq connman >/dev/null 2>&1 || pacman -Qq connman-openrc >/dev/null 2>&1; then
        warn "connman is installed but not enabled, so the installer will leave the packages alone"
    fi

    enable_service_in_default "$networkmanager_service" || return 1

    if ! verify_networkmanager; then
        if (( connman_was_enabled || connman_was_running )); then
            rollback_network_changes
        fi
        return 1
    fi

    if (( connman_was_enabled || connman_was_running )); then
        remove_connman_packages || return 1
    fi
}

remove_existing_path() {
    local target_path="$1"

    if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
        return 0
    fi

    info "removing existing $target_path"
    run_cmd rm -rf -- "$target_path" || return 1
}

is_yudots_already_installed() {
    local data_root="$target_home/.local/share/yudots-revamped"
    local niri_config="$target_home/.config/niri/config.kdl"

    if [[ -d "$data_root" || -f "$niri_config" ]]; then
        return 0
    fi

    return 1
}

show_one_time_preinstall_warning() {
    local warning_state_dir="$target_home/.local/state/yudots-revamped"
    local warning_marker="$warning_state_dir/preinstall-warning-shown"
    local warning_result=0

    if is_yudots_already_installed; then
        info "existing yudots install detected, skipping one-time preinstall warning"
        return 0
    fi

    if [[ -f "$warning_marker" ]]; then
        info "one-time preinstall warning was already acknowledged, skipping"
        return 0
    fi

    while true; do
        warning_result=0
        pause_on_warning "this installer will replace matching files under ~/.config and ~/.bash_profile. this warning is shown once before first install." || warning_result=$?

        case "$warning_result" in
            0)
                break
                ;;
            1)
                error "stopping because the one-time preinstall warning was declined"
                return 1
                ;;
            2)
                warn "showing the one-time preinstall warning again"
                ;;
        esac
    done

    mkdir -p "$warning_state_dir" || return 1
    : > "$warning_marker" || return 1
    info "recorded one-time preinstall warning marker: $warning_marker"
}

copy_dotfiles() {
    local source=""
    local entry=""
    local target_path=""

    mkdir -p "$target_home/.config" || return 1

    for source in "$repo_config_dir"/*; do
        entry="$(basename "$source")"

        if [[ "$entry" == "bash_profile" ]]; then
            continue
        fi

        target_path="$target_home/.config/$entry"
        remove_existing_path "$target_path" || return 1
        run_cmd cp -a "$source" "$target_home/.config/" || return 1
    done

    remove_existing_path "$target_home/.bash_profile" || return 1
    run_cmd cp -a "$repo_config_dir/bash_profile" "$target_home/.bash_profile"
}

copy_wallpapers() {
    local data_root="$target_home/.local/share/yudots-revamped"

    mkdir -p "$target_home/.local/share" || return 1
    remove_existing_path "$data_root" || return 1
    mkdir -p "$data_root" || return 1
    run_cmd cp -a "$repo_wallpapers_dir" "$data_root/"
}

prepare_wallpaper_and_theme_state() {
    local state_dir="$target_home/.local/state/matugen"
    local state_file="$state_dir/current_wallpaper"
    local default_wallpaper_path="$target_home/.local/share/yudots-revamped/wallpapers/$default_wallpaper_name"
    local skip_marker="$state_dir/skip_theme_reapply_once"
    local current_wallpaper=""

    if [[ ! -f "$default_wallpaper_path" ]]; then
        error "default wallpaper was not copied to $default_wallpaper_path"
        return 1
    fi

    mkdir -p "$state_dir" || return 1

    if [[ -f "$state_file" ]]; then
        current_wallpaper="$(<"$state_file")"
    fi

    if [[ -n "$current_wallpaper" && -f "$current_wallpaper" ]]; then
        rm -f -- "$skip_marker" || return 1
        run_cmd matugen image "$current_wallpaper" --source-color-index 0 || return 1
        info "kept existing wallpaper state: $current_wallpaper"
        info "regenerated the color scheme from the existing wallpaper"
        return 0
    fi

    printf '%s\n' "$default_wallpaper_path" > "$state_file" || return 1
    : > "$skip_marker" || return 1

    info "default wallpaper seeded as $default_wallpaper_path"
    info "the current bundled theme files are kept as the default colors"
}

ensure_bash_login_shell() {
    local bash_path=""
    local current_shell=""

    bash_path="$(command -v bash)" || return 1
    current_shell="$(getent passwd "$target_user" | cut -d: -f7)"

    if [[ "$current_shell" == "$bash_path" ]]; then
        info "default login shell already uses bash"
        return 0
    fi

    run_cmd sudo chsh -s "$bash_path" "$target_user"
}

finish_message() {
    ok "install finished"
    warn "you should now relogin or reboot"
    warn "rebooting is the better option here"
    warn "join @haxiPorts to report a problem or something"
}

main() {
    init_log
    info "logging to $log_file"
    info "starting yudots-revamped install"

    run_step "checking who is running the installer" check_user_context || exit 1
    run_step "checking the repo layout" check_repo_layout || exit 1
    run_step "checking for artix linux with openrc" check_supported_system || exit 1
    run_step "showing the one-time preinstall replacement warning" show_one_time_preinstall_warning || exit 1
    run_step "installing bootstrap packages for building paru" bootstrap_build_tools || exit 1
    run_step "installing paru from source" install_paru_from_source || exit 1
    run_step "installing the required packages" install_required_packages || exit 1
    run_step "ensuring brightness permissions (video group membership)" ensure_video_group_membership || exit 1
    run_step "installing the microphone LED permission rule" install_micmute_led_rule || exit 1
    run_step "installing the elogind lid-close lock configuration" install_elogind_lid_lock_config || exit 1
    run_step "enabling the core openrc services" enable_core_services || exit 1
    run_step "copying the yudots config into place" copy_dotfiles || exit 1
    run_step "copying the bundled wallpapers" copy_wallpapers || exit 1
    run_step "preparing wallpaper and theme state" prepare_wallpaper_and_theme_state || exit 1
    run_step "making sure the default shell is bash" ensure_bash_login_shell || exit 1
    run_step "switching from connman to networkmanager when needed" handle_network_stack || exit 1
    finish_message
}

main "$@"

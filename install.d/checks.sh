#!/usr/bin/env bash

check_user_context() {
    local detected_user=""
    local passwd_entry=""
    local detected_home=""

    require_commands bash getent id sudo || return 1

    if [[ "${EUID}" -eq 0 ]]; then
        error "run this script as your normal user with sudo access, not as root"
        return 1
    fi

    detected_user="$(id -un 2>/dev/null || true)"
    if [[ -z "$detected_user" ]]; then
        detected_user="${target_user:-}"
    fi

    if [[ -z "$detected_user" ]]; then
        error "could not detect the target user"
        return 1
    fi

    passwd_entry="$(getent passwd "$detected_user" || true)"
    if [[ -z "$passwd_entry" ]]; then
        error "could not resolve passwd entry for user: $detected_user"
        return 1
    fi

    detected_home="$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"
    if [[ -z "$detected_home" || "$detected_home" != /* ]]; then
        error "could not detect a valid home directory for user: $detected_user"
        return 1
    fi

    if [[ -n "${target_home:-}" && "$target_home" != "$detected_home" ]]; then
        warn "HOME does not match the passwd home; using $detected_home instead of $target_home"
    fi

    target_user="$detected_user"
    target_home="$detected_home"

    if [[ ! -d "$target_home" ]]; then
        error "target home does not exist: $target_home"
        return 1
    fi

    if [[ ! -w "$target_home" ]]; then
        error "target home is not writable: $target_home"
        return 1
    fi

    if [[ ! -O "$target_home" ]]; then
        warn "target home is not owned by the current user: $target_home"
    fi

    run_cmd sudo -v || return 1
    start_sudo_keepalive || return 1
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
    require_commands rc-service rc-update || return 1

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

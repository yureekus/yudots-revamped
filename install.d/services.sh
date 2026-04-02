#!/usr/bin/env bash

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

    require_commands rc-service sudo || return 1
    sudo rc-service "$service_name" status >/dev/null 2>&1
}

disable_service_everywhere() {
    local service_name="$1"
    local level=""

    require_commands rc-update sudo || return 1
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

    require_commands rc-service rc-update sudo || return 1
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
    require_commands rc-service sudo || return 1

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
    local connectivity_state=""

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

    if command -v nm-online >/dev/null 2>&1; then
        if run_cmd nm-online -q --timeout=20; then
            return 0
        fi
        warn "nm-online did not report readiness yet; falling back to connectivity probes"
    fi

    if command -v nmcli >/dev/null 2>&1; then
        connectivity_state="$(nmcli -t -f CONNECTIVITY general 2>/dev/null || true)"
        case "$connectivity_state" in
            full|limited|portal)
                info "networkmanager connectivity state: $connectivity_state"
                return 0
                ;;
        esac
    fi

    if command -v ping >/dev/null 2>&1; then
        for attempt in 1 2 3 4 5; do
            info "networkmanager connectivity check attempt $attempt of 5"

            if run_cmd ping -c 1 -W 5 1.1.1.1 && run_cmd ping -c 1 -W 5 google.com; then
                return 0
            fi

            sleep 2
        done
    else
        warn "ping was not found; skipping the fallback connectivity probes"
    fi

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

    require_commands pacman sudo || return 1

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

    require_commands pacman sudo || return 1
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

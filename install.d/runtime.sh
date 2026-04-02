#!/usr/bin/env bash

require_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    error "required command not found: $command_name"
    return 1
}

require_commands() {
    local command_name=""

    for command_name in "$@"; do
        require_command "$command_name" || return 1
    done
}

path_is_within() {
    local path="$1"
    local prefix="$2"

    case "$path" in
        "$prefix"|"$prefix"/*)
            return 0
            ;;
    esac

    return 1
}

assert_managed_target_path() {
    local target_path="$1"

    if [[ -z "$target_home" || "$target_home" != /* ]]; then
        error "target home is not an absolute path: ${target_home:-unset}"
        return 1
    fi

    case "$target_path" in
        "$target_home/.bash_profile"|\
        "$target_home/.config"|\
        "$target_home/.config"/*|\
        "$target_home/.local/share/yudots-revamped"|\
        "$target_home/.local/share/yudots-revamped/"*|\
        "$target_home/.local/state/yudots-revamped"|\
        "$target_home/.local/state/yudots-revamped/"*|\
        "$target_home/.local/state/matugen"|\
        "$target_home/.local/state/matugen/"*)
            return 0
            ;;
    esac

    error "refusing to touch unmanaged path: $target_path"
    return 1
}

safe_remove_dir() {
    local target_path="$1"

    if [[ -z "$target_path" || "$target_path" == "/" ]]; then
        error "refusing to remove an unsafe path: ${target_path:-<empty>}"
        return 1
    fi

    if ! path_is_within "$target_path" "/tmp" && ! path_is_within "$target_path" "$target_home"; then
        error "refusing to remove a path outside the installer scope: $target_path"
        return 1
    fi

    run_cmd rm -rf -- "$target_path"
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

    if [[ -n "$sudo_keepalive_pid" ]] && kill -0 "$sudo_keepalive_pid" >/dev/null 2>&1; then
        kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
        wait "$sudo_keepalive_pid" 2>/dev/null || true
    fi

    if [[ -n "$paru_build_dir" && -d "$paru_build_dir" ]]; then
        if path_is_within "$paru_build_dir" "/tmp" && [[ "$paru_build_dir" == /tmp/yudots-revamped-paru-* ]]; then
            rm -rf -- "$paru_build_dir"
        else
            warn "skipping cleanup for unexpected temporary directory: $paru_build_dir"
        fi
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

start_sudo_keepalive() {
    if [[ -n "$sudo_keepalive_pid" ]] && kill -0 "$sudo_keepalive_pid" >/dev/null 2>&1; then
        return 0
    fi

    (
        while true; do
            sleep 60
            sudo -n true >/dev/null 2>&1 || exit 0
        done
    ) &
    sudo_keepalive_pid=$!
    info "started sudo credential keepalive in the background"
}

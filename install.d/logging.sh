#!/usr/bin/env bash

init_log() {
    local previous_umask=""

    previous_umask="$(umask)"
    umask 077
    : > "$log_file" || {
        umask "$previous_umask"
        printf 'could not write log file: %s\n' "$log_file" >&2
        exit 1
    }
    umask "$previous_umask"
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
    local exit_code=0
    local -a cmd=("$@")

    if (( ${#cmd[@]} > 0 )) && [[ "${cmd[0]}" == "sudo" ]]; then
        if ! (( ${#cmd[@]} > 1 )) || [[ "${cmd[1]}" != "-v" ]]; then
            cmd=(sudo -n "${cmd[@]:1}")
        fi
    fi

    info "running: ${cmd[*]}"
    "${cmd[@]}" 2>&1 | stream_command_output
    exit_code="${PIPESTATUS[0]}"

    if (( exit_code != 0 )); then
        error "command failed with exit code $exit_code: ${cmd[*]}"
    fi

    return "$exit_code"
}

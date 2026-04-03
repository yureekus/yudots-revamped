#!/usr/bin/env bash

set -Euo pipefail
shopt -s nullglob

IFS=$'\n\t'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
repo_config_dir="$script_dir/config"
readonly repo_config_dir
repo_wallpapers_dir="$script_dir/wallpapers"
readonly repo_wallpapers_dir
repo_system_dir="$script_dir/system"
readonly repo_system_dir
default_wallpaper_name="yureek_protogen.png"
readonly default_wallpaper_name
log_file="/tmp/yudots-revamped-install-$(date +%Y%m%d-%H%M%S).log"

target_user="$(id -un 2>/dev/null || printf '%s' "${USER:-}")"
target_home="${HOME:-}"
paru_build_dir=""
networkmanager_service=""
connman_service=""
sudo_keepalive_pid=""

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

source_installer_module() {
    local module_path="$script_dir/install.d/$1"

    if [[ ! -r "$module_path" ]]; then
        printf 'missing installer module: %s\n' "$module_path" >&2
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$module_path"
}

source_installer_module "logging.sh"
source_installer_module "runtime.sh"
source_installer_module "checks.sh"
source_installer_module "packages.sh"
source_installer_module "services.sh"
source_installer_module "dotfiles.sh"

trap cleanup EXIT
trap on_interrupt INT TERM

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
    run_step "installing the LibreWolf extension policy" install_librewolf_policy_config || exit 1
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

#!/usr/bin/env bash

replace_path_atomically() {
    local source_path="$1"
    local target_path="$2"
    local parent_dir=""
    local staging_dir=""
    local staged_path=""
    local backup_path=""
    local had_existing_target=0

    require_commands cp mktemp mv || return 1
    assert_managed_target_path "$target_path" || return 1

    parent_dir="$(dirname -- "$target_path")"
    mkdir -p "$parent_dir" || return 1

    staging_dir="$(mktemp -d "$parent_dir/.yudots-stage-XXXXXX")" || {
        error "could not create a staging directory in $parent_dir"
        return 1
    }

    staged_path="$staging_dir/new"
    backup_path="$staging_dir/original"

    if ! run_cmd cp -a "$source_path" "$staged_path"; then
        safe_remove_dir "$staging_dir" || true
        return 1
    fi

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        had_existing_target=1
        info "replacing existing $target_path"
        if ! run_cmd mv -T "$target_path" "$backup_path"; then
            safe_remove_dir "$staging_dir" || true
            return 1
        fi
    fi

    if run_cmd mv -T "$staged_path" "$target_path"; then
        safe_remove_dir "$staging_dir" || true
        return 0
    fi

    if (( had_existing_target )) && [[ -e "$backup_path" || -L "$backup_path" ]]; then
        warn "restoring previous contents for $target_path after a failed replacement"
        run_cmd mv -T "$backup_path" "$target_path" || warn "automatic restore failed for $target_path"
    fi

    safe_remove_dir "$staging_dir" || true
    return 1
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

    assert_managed_target_path "$warning_state_dir" || return 1
    mkdir -p "$warning_state_dir" || return 1
    : > "$warning_marker" || return 1
    info "recorded one-time preinstall warning marker: $warning_marker"
}

copy_dotfiles() {
    local source=""
    local entry=""
    local target_path=""

    assert_managed_target_path "$target_home/.config" || return 1
    mkdir -p "$target_home/.config" || return 1

    for source in "$repo_config_dir"/*; do
        entry="$(basename "$source")"

        if [[ "$entry" == "bash_profile" ]]; then
            continue
        fi

        if [[ "$entry" == "niri" ]]; then
            copy_niri_dotfiles || return 1
            continue
        fi

        target_path="$target_home/.config/$entry"
        replace_path_atomically "$source" "$target_path" || return 1
    done

    replace_path_atomically "$repo_config_dir/bash_profile" "$target_home/.bash_profile"
}

copy_niri_dotfiles() {
    local source_dir="$repo_config_dir/niri"
    local target_dir="$target_home/.config/niri"
    local target_custom_dir="$target_dir/custom"
    local source=""
    local entry=""
    local target_path=""
    local is_first_install=0

    if ! is_yudots_already_installed; then
        is_first_install=1
    fi

    assert_managed_target_path "$target_dir" || return 1
    mkdir -p "$target_dir" || return 1

    for source in "$source_dir"/*; do
        entry="$(basename "$source")"

        if [[ "$entry" == "custom" ]]; then
            if (( is_first_install )); then
                if [[ -e "$target_custom_dir" || -L "$target_custom_dir" ]]; then
                    info "preserving existing $target_custom_dir"
                    continue
                fi
            else
                info "skipping $target_custom_dir because niri custom config is only seeded on first install"
                continue
            fi
        fi

        target_path="$target_dir/$entry"
        replace_path_atomically "$source" "$target_path" || return 1
    done
}

copy_wallpapers() {
    local data_root="$target_home/.local/share/yudots-revamped"
    local target_wallpapers_dir="$data_root/wallpapers"

    assert_managed_target_path "$data_root" || return 1
    mkdir -p "$data_root" || return 1
    replace_path_atomically "$repo_wallpapers_dir" "$target_wallpapers_dir"
}

prepare_wallpaper_and_theme_state() {
    local state_dir="$target_home/.local/state/matugen"
    local state_file="$state_dir/current_wallpaper"
    local default_wallpaper_path="$target_home/.local/share/yudots-revamped/wallpapers/$default_wallpaper_name"
    local skip_marker="$state_dir/skip_theme_reapply_once"
    local current_wallpaper=""

    require_command matugen || return 1

    if [[ ! -f "$default_wallpaper_path" ]]; then
        error "default wallpaper was not copied to $default_wallpaper_path"
        return 1
    fi

    assert_managed_target_path "$state_dir" || return 1
    mkdir -p "$state_dir" || return 1

    if [[ -f "$state_file" ]]; then
        current_wallpaper="$(<"$state_file")"
    fi

    if [[ -n "$current_wallpaper" && -f "$current_wallpaper" ]]; then
        rm -f -- "$skip_marker" || return 1

        # Only trigger live template hooks when running inside a graphical session.
        if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" || -n "${NIRI_SOCKET:-}" ]]; then
            run_cmd matugen image "$current_wallpaper" --source-color-index 0 || return 1
            info "regenerated the color scheme from the existing wallpaper"
        else
            info "detected a non-graphical session; skipped live theme reload hooks"
        fi

        info "kept existing wallpaper state: $current_wallpaper"
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

    require_commands bash chsh getent sudo || return 1
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

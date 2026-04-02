{ config, lib, pkgs, ... }:

let
  cfg = config.programs.yudots;
  repoRoot = ../..;
  defaultWallpaperName = "yureek_protogen.png";
  matugenBin =
    if lib.hasAttrByPath [ "matugen" ] pkgs then
      lib.getExe pkgs.matugen
    else
      null;
in
{
  options.programs.yudots = {
    enable = lib.mkEnableOption "Yudots Revamped home configuration";

    launchFromTty1 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start niri from tty1 through ~/.bash_profile.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.enable = true;

    home.activation.installYudots = config.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu

      repo_config_dir='${repoRoot}/config'
      repo_wallpapers_dir='${repoRoot}/wallpapers'
      target_config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      target_data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/yudots-revamped"
      target_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/matugen"
      current_wallpaper_file="$target_state_dir/current_wallpaper"
      default_wallpaper_path="$target_data_dir/wallpapers/${defaultWallpaperName}"

      mkdir -p "$target_config_dir" "$target_data_dir" "$target_state_dir"

      for source in "$repo_config_dir"/*; do
        entry="$(basename "$source")"

        if [[ "$entry" == "bash_profile" ]]; then
          continue
        fi

        if [[ "$entry" == "niri" ]]; then
          mkdir -p "$target_config_dir/niri"

          for niri_source in "$source"/*; do
            niri_entry="$(basename "$niri_source")"

            if [[ "$niri_entry" == "custom" ]]; then
              if [[ ! -e "$target_config_dir/niri/custom" && ! -L "$target_config_dir/niri/custom" ]]; then
                cp -a "$niri_source" "$target_config_dir/niri/custom"
              fi
              continue
            fi

            rm -rf "$target_config_dir/niri/$niri_entry"
            cp -a "$niri_source" "$target_config_dir/niri/$niri_entry"
          done

          continue
        fi

        rm -rf "$target_config_dir/$entry"
        cp -a "$source" "$target_config_dir/$entry"
      done

      rm -rf "$target_data_dir/wallpapers"
      cp -a "$repo_wallpapers_dir" "$target_data_dir/wallpapers"

      if [[ -f "$default_wallpaper_path" && ! -f "$current_wallpaper_file" ]]; then
        printf '%s\n' "$default_wallpaper_path" > "$current_wallpaper_file"
        : > "$target_state_dir/skip_theme_reapply_once"
      fi

    '' + lib.optionalString (matugenBin != null) ''
      if [[ -f "$current_wallpaper_file" ]]; then
        current_wallpaper="$(cat "$current_wallpaper_file")"

        if [[ -f "$current_wallpaper" ]]; then
          rm -f "$target_state_dir/skip_theme_reapply_once"
          ${matugenBin} image "$current_wallpaper" --source-color-index 0 >/dev/null 2>&1 || true
        fi
      fi
    '';

    home.file.".bash_profile" = lib.mkForce {
      text = ''
        [[ -f ~/.bashrc ]] && . ~/.bashrc
      '' + lib.optionalString cfg.launchFromTty1 ''
        
        if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
            exec dbus-run-session niri --session
        fi
      '';
    };
  };
}
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.yudots;

  maybePkg = attrPath:
    lib.optional (lib.hasAttrByPath attrPath pkgs) (lib.getAttrFromPath attrPath pkgs);

  basePackages =
    maybePkg [ "brightnessctl" ]
    ++ maybePkg [ "dolphin" ]
    ++ maybePkg [ "ffmpeg" ]
    ++ maybePkg [ "fish" ]
    ++ maybePkg [ "fuzzel" ]
    ++ maybePkg [ "ghostty" ]
    ++ maybePkg [ "mako" ]
    ++ maybePkg [ "matugen" ]
    ++ maybePkg [ "niri" ]
    ++ maybePkg [ "polkit_gnome" ]
    ++ maybePkg [ "swayidle" ]
    ++ maybePkg [ "swaylock-effects" ]
    ++ maybePkg [ "swww" ]
    ++ maybePkg [ "vscodium" ]
    ++ maybePkg [ "waybar" ]
    ++ maybePkg [ "xwayland-satellite" ]
    ++ maybePkg [ "zenity" ];

  fontPackages =
    maybePkg [ "dejavu_fonts" ]
    ++ maybePkg [ "fira-code-nerdfont" ]
    ++ maybePkg [ "liberation_ttf" ]
    ++ maybePkg [ "noto-fonts" ]
    ++ maybePkg [ "noto-fonts-cjk-sans" ]
    ++ maybePkg [ "noto-fonts-color-emoji" ]
    ++ maybePkg [ "noto-fonts-extra" ]
    ++ maybePkg [ "nerd-fonts" "commit-mono" ];

  themePackages =
    maybePkg [ "adw-gtk3" ]
    ++ maybePkg [ "breeze" ]
    ++ maybePkg [ "breeze-icons" ]
    ++ maybePkg [ "libsForQt5" "qt5ct" ]
    ++ maybePkg [ "qt6ct" ];
in
{
  options.programs.yudots = {
    enable = lib.mkEnableOption "yudots nixos integration";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = "User to add to the video group for brightness and LED access.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install alongside the yudots defaults.";
    };

    withFonts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the font set used by the dotfiles.";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      programs.niri.enable = true;
      programs.fish.enable = true;
      programs.dconf.enable = true;

      environment.systemPackages = basePackages ++ themePackages ++ cfg.extraPackages;
      fonts.packages = lib.optionals cfg.withFonts fontPackages;

      networking.networkmanager.enable = true;
      hardware.bluetooth.enable = true;
      security.polkit.enable = true;
      security.rtkit.enable = true;
      services.dbus.enable = true;
      services.power-profiles-daemon.enable = true;
      services.pipewire = {
        enable = true;
        pulse.enable = true;
        wireplumber.enable = true;
      };

      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "suspend";
      };

      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp video /sys%p/brightness", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys%p/brightness"
      '';

      xdg.portal = {
        enable = true;
        extraPortals = lib.optional (lib.hasAttrByPath [ "xdg-desktop-portal-gnome" ] pkgs) pkgs.xdg-desktop-portal-gnome;
      };
    }
    // lib.optionalAttrs (cfg.user != null) {
      users.users = {
        ${cfg.user} = {
          extraGroups = [ "video" ];
        };
      };
    }
  );
}
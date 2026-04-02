# yudots-revamped

<p align="center">
  <img src="./preview.png" alt="Preview of yudots-revamped" />
</p>

An opinionated NixOS desktop setup built around Niri, Waybar, Matugen, and a small pile of personal preferences.

This repository is packaged as a flake. It uses a NixOS module for system services and packages plus a Home Manager module that seeds the user config into place.

## What This Includes

- `niri` as the compositor
- `waybar` as the status bar
- `fuzzel` as the launcher
- `mako` for notifications
- `ghostty` as the terminal
- `matugen` for wallpaper-based theming
- GTK / Qt theming, fonts, wallpapers, and helper scripts
- NixOS service wiring for audio, bluetooth, portals, power profiles, and NetworkManager

## Install

Add the repo as a flake input and import both exported modules.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    yudots.url = "github:yureekus/yudots-revamped";
  };

  outputs = { nixpkgs, home-manager, yudots, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        yudots.nixosModules.default
        {
          programs.yudots = {
            enable = true;
            user = "your-user";
          };

          home-manager.users.your-user = {
            imports = [ yudots.homeModules.default ];

            programs.yudots = {
              enable = true;
              launchFromTty1 = true;
            };

            home.stateVersion = "25.05";
          };
        }
      ];
    };
  };
}
```

Then apply it with:

```bash
sudo nixos-rebuild switch --flake .#my-host
```

## Module Behavior

The NixOS module exports `programs.yudots` and enables the core desktop services, package set, udev rule, and logind lid settings used by these dotfiles.

The Home Manager module exports `programs.yudots` and seeds these paths into your home directory:

- `~/.config/fish`
- `~/.config/fuzzel`
- `~/.config/ghostty`
- `~/.config/gtk-3.0`
- `~/.config/gtk-4.0`
- `~/.config/mako`
- `~/.config/matugen`
- `~/.config/niri`
- `~/.config/qt5ct`
- `~/.config/qt6ct`
- `~/.config/swaylock`
- `~/.config/waybar`
- `~/.bash_profile`
- `~/.local/share/yudots-revamped/wallpapers`

`niri/custom` is only seeded when it does not already exist, so per-machine overrides survive later rebuilds.

Matugen-generated files remain writable. On each Home Manager activation the repo defaults are copied in, then the saved wallpaper state is reapplied when possible so the active theme is not lost.

## Notes

- The Waybar update module runs `nixos-rebuild switch --flake` by default against `/etc/nixos#$(hostname)`. Override that with `YUDOTS_FLAKE_PATH` and `YUDOTS_HOSTNAME` if your system flake lives elsewhere.
- The Ghostty config no longer hardcodes `/usr/bin/fish`, which avoids the usual NixOS path breakage.
- Some optional applications are not forced here. The NixOS module only installs packages that are present in the selected `nixpkgs`, and you can extend that with `programs.yudots.extraPackages`.
- Audio recovery helper:
  - `~/.config/niri/scripts/audio-recover ensure`
  - `~/.config/niri/scripts/audio-recover status`
  - `~/.config/niri/scripts/audio-recover watch`

## Repository Structure

```text
.
|-- config/        # User config seeded by the Home Manager module
|-- nix/           # NixOS and Home Manager modules
|-- wallpapers/    # Bundled wallpapers copied into ~/.local/share
|-- flake.nix      # Flake entrypoint
|-- preview.png    # Screenshot used in this README
`-- README.md
```

## Credits

- [end-4](https://github.com/end-4) for the original inspiration
- [mechabar](https://github.com/sejjy/mechabar) for the Waybar base and ideas
- [Nawnii](https://t.me/ihazaadhdcuzamafreak) for the awesome art

## Contributing

If you find something messy, broken, or unnecessarily annoying to use, open an issue or PR. Improvements that make the setup cleaner without making it less reproducible are especially welcome.

<div align="center">

## 🤖 mechabar

A mecha-themed, modular Waybar configuration.

| ![Mechabar](./assets/catppuccin-mocha.png) |
| :----------------------------------------: |

<details>
<summary>Themes</summary>

<ins><b>Catppuccin:</b></ins>

| Mocha (default)                                    |
| :------------------------------------------------: |
| ![Catppuccin Mocha](./assets/catppuccin-mocha.png) |

| Macchiato                                                  |
| :--------------------------------------------------------: |
| ![Catppuccin Macchiato](./assets/catppuccin-macchiato.png) |

| Frappe                                               |
| :--------------------------------------------------: |
| ![Catppuccin Frappe](./assets/catppuccin-frappe.png) |

| Latte                                              |
| :------------------------------------------------: |
| ![Catppuccin Latte](./assets/catppuccin-latte.png) |

Feel free to open a pull request to add new themes! :^)

</details>
</div>

#

### Prerequisites

1. **[Waybar](https://github.com/Alexays/Waybar)**

> [!IMPORTANT]
> If you have **v0.14.0** installed,
> [clone the `fix/v0.14.0` branch](#clone-fix-branch) instead.

2. A **terminal emulator** (default: Kitty)

> [!IMPORTANT]
> If you use a different emulator, replace all `kitty` commands accordingly. For
> example:
>
> ```diff
> - "on-click": "kitty -e ..."
> + "on-click": "ghostty -e ..."
> ```

#

### Installation

1. Back up your current config:

	```bash
	mv ~/.config/waybar{,.bak}
	```

2. Clone the repository:

	```bash
	git clone https://github.com/sejjy/mechabar.git ~/.config/waybar
	```

	<a name="clone-fix-branch">**For Waybar v0.14.0**</a>:

	```bash
	git clone -b fix/v0.14.0 https://github.com/sejjy/mechabar.git ~/.config/waybar
	```

3. Install the dependencies and restart Waybar:

	```bash
	~/.config/waybar/install
	```

	<details>
	<summary>Dependencies (5)</summary>

	| Package                | Command         | Description                                                                    |
	| ---------------------- | --------------- | ------------------------------------------------------------------------------ |
	| `bluez-utils`          | `bluetoothctl`  | Development and debugging utilities for the bluetooth protocol stack<tr></tr>  |
	| `brightnessctl`        | `brightnessctl` | Lightweight brightness control tool<tr></tr>                                   |
	| `fzf`                  | `fzf`           | Command-line fuzzy finder<tr></tr>                                             |
	| `networkmanager`       | `nmcli`         | Network connection manager and user applications<tr></tr>                      |
	| `otf-commit-mono-nerd` | -               | Patched font Commit Mono from nerd fonts library                               |

	</details>

#

### Configuration

<details>
<summary><code>user.jsonc</code></summary>

The leftmost module has no default function and is reserved for custom use. You
can configure it to run any command. For example:

```jsonc
// modules/custom/user.jsonc

"custom/user": {
	// Run your script
	"on-click": "/path/to/my/script",
	// Restart Waybar
	"on-click-right": "pkill -SIGUSR2 waybar",
}
```

#

</details>

<details>
<summary>Binds</summary>

You can define keybinds to interact with modules using their respective
[scripts](./scripts/). For example, in Niri:

```kdl
// ~/.config/niri/custom/binds.kdl

binds {
	Mod+B { spawn "ghostty" "--class=org.haxi0.waybar-popup" "--title=bt" "-e" "~/.config/waybar/scripts/bluetooth"; }
	Mod+N { spawn "ghostty" "--class=org.haxi0.waybar-popup" "--title=net" "-e" "~/.config/waybar/scripts/network"; }
	Mod+P { spawn "ghostty" "--class=org.haxi0.waybar-popup" "--title=power" "-e" "~/.config/waybar/scripts/power"; }
	Mod+U { spawn "ghostty" "--class=org.haxi0.waybar-popup" "--title=update" "-e" "~/.config/waybar/scripts/update"; }

	Mod+Alt+B { spawn-sh "~/.config/waybar/scripts/bluetooth off"; }
	Mod+Alt+N { spawn-sh "~/.config/waybar/scripts/network off"; }
	Mod+Alt+U { spawn-sh "pkill -RTMIN+1 waybar"; }

	XF86AudioMicMute allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/volume input mute"; }
	XF86AudioMute allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/volume output mute"; }
	XF86AudioLowerVolume allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/volume output lower"; }
	XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/volume output raise"; }

	XF86MonBrightnessDown allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/backlight down"; }
	XF86MonBrightnessUp allow-when-locked=true { spawn-sh "~/.config/waybar/scripts/backlight up"; }
}
```

#

</details>

<details>
<summary>Icons</summary>

You can search for icons on
[Nerd Fonts: Cheat Sheet ↗](https://www.nerdfonts.com/cheat-sheet). For example:

```
battery charging
```

For consistency, most modules use icons from Material Design, prefixed with
`nf-md`:

```
nf-md battery charging
```

#

</details>

<details open>
<summary>Theme</summary>

Copy your preferred theme from the [themes](./themes/) directory to `theme.css`.
For example:

```bash
cd ~/.config/waybar
cp themes/catppuccin-latte.css theme.css
```

</details>

#

### References

- [Nerd Fonts wiki: Glyph Sets](https://github.com/ryanoasis/nerd-fonts/wiki/Glyph-Sets-and-Code-Points)
- [Waybar wiki](https://github.com/Alexays/Waybar/wiki)

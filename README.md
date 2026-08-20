<div align="center">
  <img src="wave-launcher.gif" alt="Wave Launcher demo" width="560" />
  <p>A cool Quickshell app launcher for Wayland</p>
</div>

## Run

```sh
nix run github:Kalkaro/wave-launcher
```
or shell:

```sh
nix shell github:Kalkaro/wave-launcher
wave-launcher
```

## Colors

Wave Launcher reads its colors from environment variables when its Quickshell
daemon starts:

| Variable | Purpose | Default |
| --- | --- | --- |
| `WAVE_LAUNCHER_BG` | Center-vignette background | `#100e1c` |
| `WAVE_LAUNCHER_FG` | Primary text | `#f4ebfc` |
| `WAVE_LAUNCHER_ACCENT` | Text shadows | `#c084fc` |

For example:

```sh
WAVE_LAUNCHER_BG='#140811' \
WAVE_LAUNCHER_FG='#e1ccc9' \
WAVE_LAUNCHER_ACCENT='#140811' \
wave-launcher
```

Changing these variables does not update an already-running daemon. Restart
Wave Launcher after changing them so the new colors are inherited.

The included NixOS and Home Manager modules expose font, animation, and custom
color options. The font defaults to BigBlueTermPlus Nerd Font, and both text
effects are enabled by default:

```nix
programs.wave-launcher = {
  enable = true;
  font = "BigBlueTermPlus Nerd Font";
  wave.enable = true;
  scramble.enable = true;

  colors = {
    background = "#140811";
    foreground = "#e1ccc9";
    accent = "#140811";
  };
};
```

Set `wave.enable = false` for flat text or `scramble.enable = false` to show
application names immediately without randomized characters. To source colors
from Stylix instead, set `stylix.enable = true`; this maps Stylix `base05` to the
primary text and `base00` to both the background and text shadows.

## Piped input

When stdin is piped in, Wave Launcher works as a dmenu-style selector and writes
the selected line to stdout:

```sh
cliphist list | wave-launcher | cliphist decode | wl-copy
```

Piped menus display the second tab-separated column (like Rofi's
`-display-columns 2`) with a 25-character limit, while returning the complete
original line. The first input row is selected initially. Use the arrow keys to
navigate, Enter to select, or Escape to cancel; text search is disabled in this
mode. Running `wave-launcher` without piped input keeps the normal application
launcher behavior.

Search logic is ported from [Rofi](https://github.com/davatorium/rofi) (MIT).

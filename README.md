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

Pass `--fall` to enable falling-letter physics for that invocation:

```sh
wave-launcher --fall
```

Pass `--special` to roll for a rare special effect instead. Each launch has a
1% chance (`special.chance`) of picking one of the special effects at random;
the rest of the time the launcher opens normally. Falling letters are currently
the only effect in the pool:

```sh
wave-launcher --special
```

## Colors

Wave Launcher reads declarative settings from
`$XDG_CONFIG_HOME/wave-launcher/config.json` (normally
`~/.config/wave-launcher/config.json`). The file is watched for changes, so an
already-running launcher reloads updated colors and behavior automatically.

The Home Manager module generates this file from the options below. The NixOS
module generates the same file at `/etc/xdg/wave-launcher/config.json`.

The included NixOS and Home Manager modules expose font, animation, and custom
color options. The font defaults to BigBlueTermPlus Nerd Font, and both text
effects are enabled by default:

```nix
programs.wave-launcher = {
  enable = true;
  font = "BigBlueTermPlus Nerd Font";
  wave.enable = true;
  scramble.enable = true;
  fall.enable = false;
  special.chance = 0.01;
  background.enable = true;
  maxCharacters = 25;

  colors = {
    background = "#140811";
    foreground = "#e1ccc9";
    accent = "#140811";
  };
};
```

Without a Nix module, the equivalent color configuration is:

```json
{
  "background": "#140811",
  "foreground": "#e1ccc9",
  "accent": "#140811"
}
```

Set `wave.enable = false` for flat text, `scramble.enable = false` to show
application names immediately without randomized characters,
`fall.enable = true` to keep falling-letter physics enabled,
`special.chance` to tune how often `--special` triggers an effect (0 disables
them), or
`background.enable = false` to hide the blurred rectangle behind the text. To
source colors from Stylix instead, set `stylix.enable = true`; this maps Stylix
`base05` to the primary text and `base00` to both the background and text
shadows.

## Startup

Both Nix modules install a `wave-launcher` systemd user service bound to
`graphical-session.target`, so the launcher is already resident when the
keybind is first pressed rather than paying Quickshell startup on the first
launch of the session. Set `service.enable = false` for the on-demand
behaviour, where the first launch starts the daemon itself.

Outside of systemd, `wave-launcher --daemon` runs the launcher in the
foreground without opening it.

## Piped input

When stdin is piped in, Wave Launcher works as a dmenu-style selector and writes
the selected line to stdout:

```sh
cliphist list | wave-launcher | cliphist decode | wl-copy
```

Piped menus display the second tab-separated column (like Rofi's
`-display-columns 2`) with a limit controlled by the Home Manager and NixOS
module's `maxCharacters` option (25 by default), while returning the complete
original line. The first input row is selected initially. Use the arrow keys to
navigate, Enter to select, or Escape to cancel; text search is disabled in this
mode. Running `wave-launcher` without piped input keeps the normal application
launcher behavior.

Search logic is ported from [Rofi](https://github.com/davatorium/rofi) (MIT).

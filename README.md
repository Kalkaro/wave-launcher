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

## Piped input

When stdin is piped in, Wave Launcher works as a dmenu-style selector and writes
the selected line to stdout:

```sh
cliphist list | wave-launcher | cliphist decode | wl-copy
```

Piped menus display the second tab-separated column (like Rofi's
`-display-columns 2`) with a 15-character limit, while returning the complete
original line. The final input row is selected initially. Use the arrow keys to
navigate, Enter to select, or Escape to cancel; text search is disabled in this
mode. Running `wave-launcher` without piped input keeps the normal application
launcher behavior.

Search logic is ported from [Rofi](https://github.com/davatorium/rofi) (MIT).

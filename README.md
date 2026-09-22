# Iris for Omarchy

A floating, always-on-top circular webcam mirror for the Omarchy shell,
modelled on [ahmetb/Iris](https://github.com/ahmetb/Iris) for macOS.
Pure QML (Qt Multimedia) running inside `omarchy-shell` as plugin `alex.iris`.

## Install

The repository root is the plugin (`manifest.json` at the top), so Omarchy can
install it straight from git:

```bash
omarchy plugin add <repo-url> --enable
```

## Develop

From a checkout, `install.sh` validates and copies it into
`~/.config/omarchy/plugins/alex.iris`:

```bash
./install.sh --enable     # first time: copy and enable
./install.sh              # after BarWidget.qml edits (hot-reloads)
./install.sh --restart    # after Panel.qml edits: keepLoaded panels need a shell restart
```

## Use

| Action | Effect |
|---|---|
| Bar icon, left click | show / hide the bubble |
| Bar icon, right click | show the bubble with its menu open |
| Drag inside the circle | move |
| Drag the rim, or scroll | resize |
| Arrows button (bottom of the bubble, on hover) | **framing mode**: drag moves the image, scroll zooms it toward the pointer; ✓ or right click to finish |
| Right-drag, or middle-drag | move the image directly, without framing mode |
| Hold right button + scroll | zoom the image directly, without framing mode |
| Double click | toggle mirror |
| Right click the circle | menu: camera, mirror, adjust framing, reset framing, show at login, hide |

From a keybinding or script:

```bash
omarchy-shell shell toggle alex.iris '{}'
omarchy-shell shell summon alex.iris '{"mirror":false,"camera":"Integrated Camera"}'
omarchy-shell shell call alex.iris toggleMirror ''
omarchy-shell shell call alex.iris nextCamera ''
omarchy-shell shell call alex.iris resetFraming ''
omarchy-shell shell call alex.iris toggleFraming ''
```

Hyprland binding, e.g. in `~/.config/hypr/bindings.conf`:

```
bind = SUPER CTRL, C, exec, omarchy-shell shell toggle alex.iris '{}'
```

State (position, size, framing, camera, mirror, show-at-login) lives in
`~/.local/state/omarchy/iris.json`.

## Iris feature map

| Iris (macOS) | Here |
|---|---|
| Circular always-on-top window | Overlay layer surface with an elliptical input region |
| Drag to move / resize from edge | Same |
| Menu bar icon + menu | Bar widget + right-click menu |
| Camera selection, mirror view | Same, persisted |
| Launch at login | "Show at login" (plugin is `keepLoaded`, restores the bubble) |
| Remembers size/position/camera | Same, per screen name |

## Notes

Framing is free: zoom goes from the whole camera frame fitting inside the
circle up to 4×, and zooming out or moving the image aside shows the
background around it.

Modifier keys can't be used for gestures: the bubble never takes keyboard
focus, so Wayland never tells it about held keys.

## Limitations

- The bubble lives on one monitor; it can't be dragged across screens yet.

## License

MIT, see [LICENSE](LICENSE).

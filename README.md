# Cavalier

A DankMaterialShell-style **media pill** for the [Noctalia](https://noctalia.dev)
bar: a live audio visualizer next to prev / play-pause / next transport buttons,
all in one widget.

![preview](docs/preview.png)

- 🎵 **Audio visualizer** — cava-style bars driven by Noctalia's built-in
  PipeWire spectrum (no `cava` process needed).
- ⏮ ⏯ ⏭ **Transport buttons** — control whatever is actually playing (prefers a
  Playing player over a paused background tab), with a filled accent play-pause.
- 🖱️ **Click the visualizer** to open the built-in Control Center media view.
- 🎚️ Tunable **sensitivity**, **smoothing**, bar count and accent colour.

## Requirements

- Noctalia **5+**
- [`playerctl`](https://github.com/altdesktop/playerctl) on `PATH` (MPRIS control)

## Install

Add this repository as a plugin source, then enable the plugin:

```bash
noctalia msg plugins source add cavalier git https://github.com/werdin/cavalier
noctalia msg plugins update cavalier   # fetch the source
noctalia msg plugins enable werdin/cavalier
```

> If the plugin doesn't appear right after adding the source, restart Noctalia
> so it fetches the new git source, then run the `enable` command.

Then add the **Cavalier** widget to a bar from Noctalia's **widget picker**
(Settings → Bar → *+ Add widget*). Adding it through the picker is what attaches
the settings gear (⚙) — a hand-edited bar entry renders but has no settings.

## Settings

| Setting          | Type   | Default   | Description                                            |
| ---------------- | ------ | --------- | ------------------------------------------------------ |
| `audio_spectrum` | bool   | `true`    | React to the PipeWire audio spectrum.                  |
| `show_visualizer`| bool   | `true`    | Draw the visualizer bars.                              |
| `sensitivity`    | double | `2.0`     | Gain applied to the bars. Lower = calmer.              |
| `smoothing`      | double | `0.6`     | Damps how fast the bars move. Higher = smoother.       |
| `bar_count`      | int    | `14`      | Number of spectrum bars.                               |
| `accent_color`   | color  | `primary` | Colour of the bars and the play-pause button.          |
| `cc_context`     | string | `media`   | Control Center view opened when clicking the cava.     |

## Usage

- **Click the visualizer** → opens the Control Center media view.
- **⏮ / ⏯ / ⏭** → previous / play-pause / next on the active MPRIS player.
- **Hover** → tooltip with the current track.

## Notes

- The visualizer uses PipeWire's spectrum, so the bars react to whatever is
  playing on the default sink — not just the MPRIS player.
- If you edit `widget.luau` while developing, the audio spectrum only re-wires
  when the plugin is **disabled and re-enabled** (or Noctalia restarts); UI edits
  hot-reload on their own.

## License

[MIT](LICENSE)

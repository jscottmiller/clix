# Waybar Status Bar

The CLIX status bar is waybar, configured at `/etc/xdg/waybar/config` with
styling in `/etc/xdg/waybar/style.css`. Both come from the repo
(`config/waybar/`) and are deployed by `modules/sway.nix`.

## Layout

```
 1 2 3        window title        ( system pill )( hardware pill )( clock ) tray
```

| Pill | Modules |
|---|---|
| system | cpu, memory, CPU temp, GPU temp |
| hardware | network, brightness, volume, battery |
| clock | time, click to show the date |

Modules sit inside `group/` containers that share one muted background, instead
of each carrying its own saturated colour. The point is that an alert has
something to stand out against: when a module crosses its warning or critical
threshold it takes a solid yellow or red background and becomes the only
saturated element in the bar. A bar where everything is bright cannot do that.

Per-metric identity comes from the icon tint rather than the background.

## Interaction

| Module | Action |
|---|---|
| cpu, memory, temps | click opens `btop` in a floating terminal |
| brightness | scroll to adjust (5% steps) |
| volume | scroll to adjust, click to mute |
| network | click opens `nmtui` in a floating terminal |
| battery | click swaps the percentage for time remaining |
| clock | click swaps the time for the date |

Floating terminals are launched as `foot -a floatterm`; `config/sway/config`
has a `for_window` rule that floats and centres them.

Brightness also responds to the `XF86MonBrightnessUp` / `Down` keys. Both the
keys and the scroll action use `brightnessctl`, which works without root
because the user is in the `video` group.

## Icons: always use escapes, never literal characters

**This is the single most important thing to know before editing the config.**

Nerd Font icons live in the Basic Multilingual Plane Private Use Area,
`U+E000`–`U+F8FF`. That range is routinely stripped or mangled in transit by
editors, terminals, web forms and copy-paste. When it happens there is no error
of any kind: the icon simply becomes an empty string, and the bar renders a
format string with a stray leading space.

CLIX shipped exactly that bug from its initial commit until this config was
rewritten. Every `format` string began with a bare space where an icon was
intended, and `format-icons` were arrays of empty strings, so the bar showed
bare numbers. The fonts were installed and complete the whole time.

So in `config/waybar/config`, write icons as JSON `\uXXXX` escapes:

```json
"format": "<span color='#8be9fd'>\uf2db</span> {usage}%"
```

and in shell scripts, build them with `printf`:

```sh
printf -v ICON '\uf2c9'        # BMP
printf -v ICON '\U000f08ae'    # above the BMP
```

Escapes are plain ASCII on disk, so nothing can silently eat them, and they
document which glyph is meant.

### Checking a glyph before you use it

`fc-list` reporting coverage is not sufficient evidence that an icon will
appear. Render it and look:

```bash
printf '\uf2db \uf1c0 \uf2c9' > /tmp/g.txt
pango-view --font='FiraCode Nerd Font 24' -q -o /tmp/g.png /tmp/g.txt
imv /tmp/g.png
```

Note that `U+F538` (the Font Awesome "memory" icon used by many waybar configs
found online) is **not** present in the shipped FiraCode Nerd Font. `U+F1C0` is
used instead.

### Tint and background must differ

Icon colours are set with Pango markup inside the format string, because GTK
CSS styles the whole module label and cannot target the icon separately. A
consequence worth remembering: a Pango tint equal to the background behind it
renders the icon invisible, which looks identical to a missing glyph.

Because Pango markup overrides CSS, any module that can enter an alert state
needs an untinted `format-<state>` as well, or its icon keeps the normal-state
colour on top of the alert background:

```json
"format": "<span color='#8be9fd'>\uf2db</span> {usage}%",
"format-warning": "\uf2db {usage}%",
"format-critical": "\uf2db {usage}%"
```

`battery` resolves `format-{status}-{state}` before `format-{state}`, so it
needs `format-discharging-warning` and `format-discharging-critical` spelled
out — on battery is the only time those states can occur.

## Temperatures

The temperature modules call `clix-sensor`, a helper shipped by
`modules/sway.nix` from `scripts/clix-sensor`:

```bash
clix-sensor cpu
clix-sensor gpu --warn 70 --crit 85
clix-sensor --help
```

waybar's built-in `temperature` module is not used because it identifies a
sensor by thermal-zone number or `hwmon` index, and both are assigned in probe
order. They are not stable across reboots, let alone across machines, so
neither can be hardcoded in a config shipped as part of a live image. Its
default, `thermal_zone0`, does not exist at all on many AMD laptops.

`clix-sensor` matches on the hwmon `name` attribute instead (`k10temp`,
`coretemp`, `amdgpu`, `i915`, ...), falls back to matching thermal zones by
type, and prints nothing when a machine has neither — which makes waybar hide
the module rather than leave a gap.

## Customising

`~/.config/waybar/config` takes priority over the system config. waybar
supports `include`, and keys in the including file win, so a personal config
can be a thin layer over the shipped one rather than a full copy:

```json
{
    "include": ["/etc/xdg/waybar/config"],
    "clock": {
        "timezone": "America/Chicago",
        "format": "<span color='#8be9fd'>\uf017</span> {:%I:%M %p}"
    }
}
```

Stylesheets work the same way with `@import`:

```css
@import url("file:///etc/xdg/waybar/style.css");
#clock { background-color: #bd93f9; }
```

Note that arrays are replaced rather than merged, so changing `modules-right`
means restating the whole list.

Without an `include`, a personal config silently shadows every later
improvement to the shipped one. If the bar stops picking up CLIX updates, check
whether `~/.config/waybar/config` is a real file rather than the symlink to
`/etc/xdg/waybar/config` that `modules/sway.nix` creates on first boot.

Reload after editing:

```bash
pkill -SIGUSR2 waybar
```

## Troubleshooting

**An icon is missing.** Almost always the PUA stripping described above. Check
with `grep -n 'format' /etc/xdg/waybar/config` — a format string starting with
a bare space had an icon eaten. Confirm the file's bytes:

```bash
python3 -c "
raw = open('/etc/xdg/waybar/config', encoding='utf-8').read()
print(sorted({hex(ord(c)) for c in raw if ord(c) > 0x7f}))"
```

**An icon is missing but the bytes are present.** Check the Pango tint against
the background it is drawn on; equal colours render invisibly.

**A temperature module is absent.** Expected when the machine has no matching
sensor. Check with `clix-sensor cpu` — no output means no match. List what the
machine does expose:

```bash
for h in /sys/class/hwmon/hwmon*; do echo "$(cat $h/name): $h"; done
```

**Brightness does not scroll.** Confirm `brightnessctl set +5%` works as your
user. If it reports permission denied, check that you are in the `video` group
with `id`.

**The bar does not reflect a config change.** See the shadowing note under
Customising.

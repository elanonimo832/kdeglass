# style-kde-macos — the M6 QStyle (slices 0-2: the skeleton, its instrument, and the push button)

A Qt 6 widget style plugin that Qt can select by the key **`KdeMacOS`**. It is M6 in
[`../docs/ROADMAP.md`](../docs/ROADMAP.md): a QStyle of our own so native Qt applications are
drawn like macOS without depending on Kvantum. The full plan, with the decisions, the measurements
behind them and the slices that follow, is [`../docs/M6-QSTYLE-PLAN.md`](../docs/M6-QSTYLE-PLAN.md).

**What is drawn, and what is still delegated.** The style is a `QProxyStyle` that chains to the base
style the desktop was already using, and it overrides exactly TWO things: `sizeFromContents` and
`drawControl`, both for the push button (slice 2). Everything else -- sixteen primitives measured by
the gallery -- is still the base's, pixel for pixel. That is deliberate: M6's done criterion asks for
a style that is "selectable **without breaking applications**", and each slice keeps that true by
moving ONE control and proving the rest did not budge.

`tests/test-style.sh` asserts which overrides exist (and that no unmeasured one appears), and
`tests/style-probe.cpp` proves the delegation property by rendering the same widget twice -- once
under the base style, once under ours -- and comparing the images pixel by pixel. Measured here:
**`DIFF: 0`**, on a control no slice has touched yet.

## Slice 2: the push button

The first control that moved, and the numbers are the kit's own, not taste:

| what | the kit says | where | the base answered | ours |
|---|---|---|---|---|
| height | **24** | `tokens/tokens-sizes.toml:88` `[global] height.medium` | 34 | **24** |
| horizontal padding | **16** | `:24` `[button] padding_horizontal.medium` | 6 (`PM_ButtonMargin`) | **16** |
| corner radius | **6** | `:27` `[button] radius.medium` | -- | **6** |

The corner is a plain **arc** rather than the window's clothoid, and that is a measurement: at 6 px
the two families differ by less than the antialiasing (0.29 px at 96 px, and sub-pixel at 6 px), so a
Fresnel integral in the paint path of every button would buy less than a pixel. `../docs/HANDOFF.md`
§10j has the rest, including the two Qt 6 facts that decided the hook.

## The primitive instrument (slice 1)

Slice 1 of the plan is what measures **before** anything is redrawn, and it lives in
`tests/primitive-gallery.cpp`:

```bash
./build.sh
QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$PWD/build" ./build/bin/primitive-gallery
QT_QPA_PLATFORM=offscreen QT_PLUGIN_PATH="$PWD/build" ./build/bin/primitive-gallery \
    --render /tmp/gallery.png --baseline /tmp/baseline.txt
```

It renders nineteen controls under the base style and under ours and reports, **per widget**, the
pixel difference between the two, what Qt answers for that control (`sizeHint`, `pixelMetric`,
`sizeFromContents`, `subControlRect`, `subElementRect`) and whether our answers differ from the
base's. After slice 2 exactly three rows differ -- the three push buttons -- and the other sixteen
are still zero, which is the assertion that separates "the slice changed the button" from "the slice
broke the style". `--render` draws the two panels side by side (our own drawing, never a screenshot)
and `--baseline` writes the "before" table, with OUR answers in it: a table of the base alone would
have shown the button as 34 px after it had already been changed to 24.

A difference that is not zero makes the tool **exit non-zero on purpose**: it means a primitive
changed, and a primitive changes only with its measurement in the test that goes with it -- so the
suite accepts exit 5 and asserts the exact set of rows behind it.

## Build

```bash
./build.sh
```

Produces `build/styles/kdemacosstyle.so` (the plugin Qt loads) and `build/bin/style-probe` (the
probe the test drives). Qt 6.12's Widgets development files and cmake/ninja are the only
requirements, and they are already present on this machine.

## Try it on ONE application, without installing and without a relogin

```bash
QT_PLUGIN_PATH="$PWD/build" QT_STYLE_OVERRIDE=KdeMacOS dolphin
```

This changes nothing on disk and nothing outside that process. Because the skeleton delegates
everything, what you should see is **exactly the same window as before** — which is the point, and
the thing to check.

## Install it for the whole session

```bash
../install.sh aplicar --si      # copies the plugin and sets the plugin path
# then log out and back in: the environment file is read at login
```

Then select it (the installer does **not** select it for you: changing the style of every
application is the user's decision, not an installer's side effect):

```bash
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle KdeMacOS
```

or pick it in *System Settings → Appearance → Colors & Themes → Application Style*. To go back:

```bash
../install.sh rollback          # removes the plugin and the environment file, restores the config
```

## Where it installs, and why there

`$HOME/.local/lib/qt6/plugins/styles/kdemacosstyle.so`, plus
`$HOME/.config/environment.d/50-kde-macos-style.conf` setting `QT_PLUGIN_PATH`. Both halves are
needed, and both were **measured** with a probe plugin:

* `QStyleFactory` does not scan a plugin path: it scans its **`styles/` subdirectory**. The plugin
  must be *inside* `styles/`, which is why `CMakeLists.txt` sets `CMAKE_LIBRARY_OUTPUT_DIRECTORY`.
* Qt does **not** search `$HOME/.local/lib/qt6/plugins` on its own — the library paths are
  `QT_PLUGIN_PATH`, then `/usr/lib/qt6/plugins`, then the application's directory. Without the
  environment file the plugin is installed and invisible.

The user-level path (rather than `/usr/lib/qt6/plugins/styles`, which would work with no environment
file at all) is deliberate: it is what lets the installer stay **sudo-free and reversible**, which is
the golden rule of `../install.sh`.

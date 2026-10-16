# style-kde-macos — the M6 QStyle (first slice: a skeleton that compiles, installs and is selectable)

A Qt 6 widget style plugin that Qt can select by the key **`KdeMacOS`**. It is the first slice of
M6 in [`../docs/ROADMAP.md`](../docs/ROADMAP.md): a QStyle of our own so native Qt applications are
drawn like macOS without depending on Kvantum. The full plan, with the decisions, the measurements
behind them and the slices that follow, is [`../docs/M6-QSTYLE-PLAN.md`](../docs/M6-QSTYLE-PLAN.md).

**What this slice is NOT:** it does not draw a single pixel of its own. The style is a
`QProxyStyle` that chains to the base style the desktop was already using and overrides **no**
primitive. That is not an unfinished job, it is the property that makes the slice safe: M6's done
criterion asks for a style that is "selectable **without breaking applications**", and the only way
to be sure of that before the primitives exist is for selecting it to change nothing.

`tests/test-style.sh` asserts that absence, and `tests/style-probe.cpp` proves it by rendering the
same widget twice — once under the base style, once under ours — and comparing the images pixel by
pixel. Measured here: **`DIFF: 0`**.

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
base's. Today every number is zero, because this style still delegates every primitive: that zero is
the line the next slice has to move. `--render` draws the two panels side by side (our own drawing,
never a screenshot) and `--baseline` writes the "before" table.

A difference that is not zero makes the tool **exit non-zero on purpose**: it means a primitive
changed, and a primitive changes only with its measurement in the test that goes with it.

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

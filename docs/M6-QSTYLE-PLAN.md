# M6 — the QStyle: the plan, the decisions, and the slices that follow

`docs/ROADMAP.md` defines M6 as *"a QStyle of our own in C++ so that native Qt applications are
drawn like macOS, without depending on Kvantum. Done when: it exists, is installed, and is
selectable without breaking applications."* It also warns that it is **the only milestone that is
not on top of anything already done**, and that it is one to three months of work.

This document is the PLAN for that work, and it is the deliverable of the first slice — together
with the skeleton it describes ([`../style-kde-macos/`](../style-kde-macos/README.md)) and the test
that proves the skeleton is safe ([`../tests/test-style.sh`](../tests/test-style.sh)).

## What the first slice ships, and what it deliberately does not

| | |
|---|---|
| ships | a plugin Qt can select by the key `KdeMacOS`; a style that chains to the base style and overrides **nothing**; the installer step that puts it where Qt finds it, with its rollback; the test that compiles it, validates its metadata and renders with it |
| does NOT ship | **any** drawing primitive. Not one button, not one checkbox. |

That is the whole design of the slice: M6's done criterion asks for a style that is selectable
**without breaking applications**, and the one way to be certain of that *before* the primitives
exist is for selecting the skeleton to change nothing at all. Measured:
`DIFF: 0 of 19800` — the same widget rendered under the base style and under ours, compared pixel by
pixel, is identical. The day a slice implements a primitive, **that** is where its measurement goes.

## The measurements this plan rests on

All taken with a throwaway probe plugin on this machine (Qt 6.12, Plasma 6, Wayland) before any of
the component was written. They are repeated here because each one decided something.

1. **`QStyleFactory` scans a `styles/` SUBDIRECTORY, not the plugin path itself.** A plugin at
   `<path>/kdemacosstyle.so` is invisible; at `<path>/styles/kdemacosstyle.so` it appears in
   `QStyleFactory::keys()`. Hence `CMAKE_LIBRARY_OUTPUT_DIRECTORY` pointing at `styles`.
2. **The keys Qt reports here are** `Breeze`, `kvantum-dark`, `kvantum`, `Windows`, `Fusion`.
3. **Qt does NOT search `$HOME/.local/lib/qt6/plugins` by itself.** The library paths are
   `QT_PLUGIN_PATH`, then `/usr/lib/qt6/plugins`, then the application's directory. This is why the
   install needs the environment file and not just the copy.
4. **Qt 6.12's `qt_add_plugin` has no `SOURCES` keyword** (its keywords are `STATIC`/`SHARED` and
   `CLASS_NAME`/`OUTPUT_NAME`/`PLUGIN_TYPE`/`OUTPUT_TARGETS`). `SOURCES x.cpp` is read as a source
   file named `SOURCES` and the configure step fails. The sources go as plain arguments.
5. **The plugin metadata is the same shape Breeze's is**: `Q_PLUGIN_METADATA` with the IID
   `QStyleFactoryInterface_iid` (from Qt's own QStylePlugin header) and a `metadata.json` carrying
   `{"Keys": [...]}`. Read back with `QPluginLoader::metaData()`, Breeze's is
   `{"Keys":["Breeze"]}` — ours is `{"Keys":["KdeMacOS"]}` and nothing more, because that is what
   the working example has.
6. **The offscreen platform is enough to test it**: `QT_QPA_PLATFORM=offscreen` runs a real
   `QApplication`, creates the style through the factory and renders widgets into a pixmap, with no
   screen and no session.
7. **systemd's `environment.d` is the mechanism this session has** (`/usr/lib/environment.d/` is
   populated, `systemctl --user` responds, `~/.config/environment.d/` did not exist yet). The
   installer writes `$XDG_CONFIG_HOME/environment.d/50-kde-macos-style.conf`; the alternative, the
   KDE-specific `~/.config/plasma-workspace/env/`, exists on this machine but was not measured to be
   read on a systemd-managed Wayland session, so it is not the one used.

## The decisions

### DECIDED — the base style is resolved at construction: Breeze, else Fusion

`MacosStyle::baseStyleKey()` asks `QStyleFactory::keys()` and picks **Breeze** if it is there, else
**Fusion**. Breeze first because chaining to the style the user already had is what makes "does not
break applications" true: every primitive the skeleton does not implement comes out of the style the
desktop was already using. Fusion as the fallback because it is the one style Qt always builds in,
so the chain can never be empty — and an **empty** base is not a neutral default: `QProxyStyle` then
falls back to the *application's* style, which may be this very style, and that is recursion.

### DECIDED — the install is user-level, and the environment file is part of it

`$HOME/.local/lib/qt6/plugins/styles/kdemacosstyle.so` plus
`$XDG_CONFIG_HOME/environment.d/50-kde-macos-style.conf` setting `QT_PLUGIN_PATH`. Measured: without
the environment file the plugin is installed and invisible. The alternative — copying to
`/usr/lib/qt6/plugins/styles`, which needs no environment file at all — is rejected because it needs
`sudo`, and `install.sh`'s golden rule is that it never escalates and never writes outside `$HOME`,
which is exactly what makes `rollback` able to undo everything.

### DECIDED — installing and selecting are two different acts

`./install.sh aplicar --si` installs the plugin and the environment file. It does **not** set the
widget style: changing how every application on the desktop is drawn is the user's decision, not an
installer's side effect. Selecting is:

```bash
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle KdeMacOS      # then log out and back in
```

or the same thing through *System Settings → Application Style*. And for ONE application, with no
config, no relogin and no trace:

```bash
QT_PLUGIN_PATH="$HOME/.local/lib/qt6/plugins" QT_STYLE_OVERRIDE=KdeMacOS dolphin
```

Undoing is `./install.sh rollback`, which restores the previous `widgetStyle` from the same manifest
that every other write in this project goes through.

### DECIDED — a primitive is only changed with its measurement in front

This is the rule the project already paid for with the shader ("do not trade the look for speed
without measuring", `docs/NEXT.md`), and M6 is where it matters most: a style plugin is loaded by
**every** application, so a half-finished primitive is a desktop-wide change. The skeleton therefore
carries an assertion that counts the primitives it overrides and expects **zero**.

## The slices that follow, in order

Each one is a separate, reviewable step. "Measurable" means: the instrument exists *before* the
primitive changes, and the change is a number.

| # | slice | what it makes measurable |
|---|---|---|
| 1 | **The primitive instrument.** A gallery of widgets (buttons, checkboxes, radios, sliders, scrollbars, comboboxes, tabs, menus, headers, focus rings) rendered under our style and under the base, with a **per-widget** pixel difference and the metrics Qt reports (`pixelMetric`, `sizeFromContents`). Today the probe reports ONE number for one widget; this is the same idea generalised, and it is the thing that must exist before anything is redrawn. | the difference per widget, in pixels, and the metrics each control asks for |
| 2 | **Push buttons.** The most visible control, and the first place the macOS look has a figure: the corner radius measured in [`../tokens/tokens-icon-geometry.toml`](../tokens/tokens-icon-geometry.toml) is an ICON radius (R/S = 0.215) and is **not** automatically a button radius. The button's own radius comes from the control radii the kit does have. | the button's radius, its padding and its metrics against the kit's control radii |
| 3 | **Checkboxes and radio buttons.** Shape, size, the accent colour on, the tick's geometry. | the control's box size, the tick's stroke, and the accent from the colour scheme |
| 4 | **Sliders and scrollbars.** The thinnest controls, and the ones where macOS differs most from Breeze in *thickness*. | the track thickness, the handle size, the metrics |
| 5 | **Comboboxes, tabs and menus.** The tallest controls: their padding is what makes a whole dialog look macOS or not. | the item height, the popup padding, the arrow metrics |
| 6 | **Focus rings, selection and disabled states.** The states, not the shapes: these are what make a style look unfinished when they are missing. | the focus ring's width and colour, the selection and disabled palettes |
| 7 | **The type tracking, as QSS or per-widget font work.** `docs/NEXT.md` point 7 records that **64 of the 80 typography tokens are tracking** (letter-spacing), and that `kdeglobals` has no destination for them — applying them belongs to the style layer. | the tracking per text style, against the tokens |

The dark scheme (`KdeMacosDark`, already generated) has to be honoured by every slice above, and
the style must read its colours from the active palette rather than hard-coding the light ones.

## OPEN — decided by measurement later, not invented now

* **Whether the base should stay `QProxyStyle`-over-Breeze, or eventually become a
  `QCommonStyle` of our own.** Chaining to Breeze is right while the style is a skeleton: it makes
  the no-op property true. But a style that inherits Breeze's metrics inherits Breeze's *sizes*, and
  a macOS look is largely a set of sizes. The measurement that settles it is slice 1's gallery: how
  much of the final look is primitives (our job) versus metrics (the base's). Not decided, and it
  should not be decided before that number exists.
* **How the style is described to the KCM.** Breeze's own metadata carries only `Keys`, and the
  Application Style page takes the display name from elsewhere. Whether our package needs a name and
  description in a `.json`, and in which file, is unmeasured.
* **Whether `QT_PLUGIN_PATH` should be appended to rather than set.** The environment file sets it to
  `$HOME/.local/lib/qt6/plugins`. Measured, Qt still searches `/usr/lib/qt6/plugins` afterwards, so
  nothing is lost — but a user with a `QT_PLUGIN_PATH` of their own would have it overwritten by this
  file, and that case has not been measured.
* **The style's behaviour under a scale factor other than 1**, and on an X11 session. Both are
  unmeasured here.
* **Whether the KWin decoration and the widget style should share the corner construction** (the
  clothoid of `effect-kwin/`, G2) or whether a control's corner is a plain arc. Measured for the
  WINDOW's corner, never for a control's — the M5 measurement showed exactly how easily a corner
  family is asserted from too few pixels.

## Risks

* **A style plugin is loaded by every Qt application.** A crash or a wrong metric is desktop-wide,
  and it can look like "KDE is broken" rather than "this plugin is". The skeleton's answer is to
  override nothing; every slice's answer is its measurement, plus the `QT_STYLE_OVERRIDE` escape
  hatch that tests one application without touching the configuration.
* **The base style may not be there.** Handled by resolution, not assumption: Breeze, else Fusion.
* **The environment file needs a relogin** to be read, and a user who selects the style before
  logging out will see nothing happen. That is why the `QT_PLUGIN_PATH` + `QT_STYLE_OVERRIDE`
  one-application way of trying it is the documented first step, before anything is selected.

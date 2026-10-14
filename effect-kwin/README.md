# KWin effect: macOS-style material

Compositor effect that draws the material on the window chrome. The band covers the
**title bar only**, and the content stays sharp: the first full-window version was
verified working and unusable, because it blurred the text you were reading.

## Status

| | |
|---|---|
| Loads without breaking rendering | ✅ verified with screenshots (`negro=0.0%`) |
| Hooks into the paint chain | ✅ `OffscreenEffect` continues it; our own `drawWindow` override continues it explicitly |
| **Diffusion** — the band is blurred | ✅ M1.2, `frost 6` as a 3x3 kernel |
| **The band covers the title bar only** | ✅ M1.2b, verified by the user, survives window switching |
| **Real glass** — the band shows the desktop behind it | ✅ **verified on screen** (M1.3a, 2026-10-14): the band moves with the background, 73.8 against a threshold of 12, where the alpha-only attempt scored 3.2 |
| **Frost over the capture** | ✅ seen on screen (2026-10-14): the backdrop is blurred in two scales from the kit's `frost 6/16/16` (`BackgroundRadius`, default 16; 0 = sharp) |
| **Chrome readable** | ✅ the title and the traffic lights are drawn crisp over the glass: the bar's blur is the blank that isolates them, and a tight baseline of its own keeps the halo off them |
| **Rounded corners** | ✅ drawn by the effect (`CornerRadius`, default 16; only for normal, decorated, non-fullscreen windows -- a fullscreen window IS the screen). This theme's SVG has a 12 px arc, but aurorae clips the corner piece into a 1 px cell, so the frame arrives as a rectangle |
| Refraction (70), dispersion (20), specular highlight | ❌ not started |

An alpha alone was measured **OPAQUE**: the shader's only input is the window's own
texture, and no alpha puts the desktop into a texture that does not contain it. The
next step is therefore the capture, not a bigger shader; see
[`../docs/HANDOFF.md`](../docs/HANDOFF.md).

## The commands

```bash
./build.sh              # compiles and verifies the paint chain
./install.sh            # installs and activates (asks for your password)
./test-glass.sh         # live: does the band show the desktop behind it? (M1.3a)
./test-titlebar.sh      # live: is the band blurred while the content stays sharp? (M1.2b)
```

`test-installed.sh` is still here and still runs, but it is an **M1.1-era instrument**:
it looks for the flat marker patch that M1.1 drew, which M1.2 replaced with the
material band. Its "not drawn" verdict says nothing about the current effect — the two
scripts above are the live tests now. [`../docs/HANDOFF.md`](../docs/HANDOFF.md)
section 7 is the procedure.

`test-installed.sh` is the test bench: it **does not log you out**, it
reinstalls nothing, and it always unloads the effect with `trap EXIT` even if
rendering fails. It takes about 15 seconds.

For the effect to stay loaded **permanently**, log out.

> ⚠️ **NEVER `kwin_wayland --replace`.** On Wayland it starts a second compositor
> that competes for the DRM/GL, kills the OpenGL context of the live KWin and leaves
> the screen **black with the cursor visible**. It happened twice; see `../INCIDENT.md`.

## Recovery

If anything left the screen black:

```bash
bash ~/RECOVER-KDE.sh reanimar     # on the fly, without logging out
```

## The four things that must be respected

All four cost hours. `verify-chain.sh` and the test harness watch over them.

**1. The path.** KWin looks in `<plugins Qt>/kwin/effects/plugins/`, **not** in
`kwin/effects/`. One level higher and KWin does not see it, and **silently**.
*(Source: `PluginEffectLoader`, `m_pluginSubDirectory = "kwin/effects/plugins"`.)*

**2. The file name is the pluginId.** `macosglass.so` → id `macosglass`.
CMake's `lib` prefix breaks it (`PREFIX ""` avoids it).

**3. The paint chain.** `EffectsHandler::paintWindow()` calls **a single**
effect per invocation, and the chain advances because `Effect::paintWindow()` —the
base— re-enters. If an effect overrides it and **does not call the base**, the chain is
cut, `finalPaintWindow()` does not run and **no window is drawn**: the
Plasma desktop background is one more window, so all that is left is black.

Every path through `paintWindow()` has to end like this:

```cpp
effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
```

The same rule applies to `drawWindow()`, which M1.3a overrides in order to capture the
desktop before the window is painted over it. There, the call that continues the chain
is `OffscreenEffect::drawWindow(...)` (the base class: it redirects, runs `apply()` and
re-enters the chain) or `effects->drawWindow(...)`. `verify-chain.sh` no longer bans the
override; it checks the property — **every path must continue the chain** — and it is
shown to fail on a source with an early `return`.

**4. `supported()`.** It has to genuinely return `true`. If it returns `false`, KWin
discards the effect **without any message**. (The version that used
`effects != nullptr`, the example from the KDE docs, returned `false`.)

## The `macosglass` identifier (why the plugin is called `macosglass2`)

The same code, byte for byte, **works with one id and breaks with another**:

| id | black on screen |
|---|---|
| `bisect` (minimal code) | 0 % ✅ |
| `testglass2` (minimal code) | 0 % ✅ |
| `macosglass` (full code) | **100 %** ❌ |
| `macosglass` (minimal code) | **100 %** ❌ |
| `macosglass2` (full code) | 0 % ✅ |

**I cannot explain why.** The observable state was identical (same metadata, same
`isSupported()`, same path). It is a reproducible observation, not a diagnosis.
Noted for the KWin team in `../INCIDENT.md`.

## Diagnostic tools

```bash
./verify-chain.sh    # is the paint chain intact? (source + binary)
```

They can be compiled by hand if needed (they use the already-installed KWin and KF6
headers; `_stub/vulkan` avoids the 42 MiB of `vulkan-headers`):

| File | What for |
|---|---|
| `src/diagnose.cpp` | reproduces KWin's plugin discovery |
| `src/probe-factory.cpp` | instantiates the factory and asks `isSupported()` |
| `src/verify-load.cpp` | does the same as KWin at startup |

These three answer «why does KWin not load my effect?» in seconds, which is what
would have saved me half the incident.

## What it draws now, and what is next

Parameters measured in `../tokens.toml` (from the Figma kit):

| Parameter | Value |
|---|---|
| refraction | 70 |
| dispersion | 20 |
| diffusion (frost) | 6 / 16 / 16 |
| light angle | 0 |
| opacity | 25 |
| depth | 30 |
| darkened edge | alpha 20 (black at 8 %) |

Drawn today: the diffusion of M1.2 (`frost 6` as a single radius), confined to the
title-bar band, and — since M1.3a — the desktop captured with
`GLFramebuffer::blitFromRenderTarget` in `drawWindow()` and composited in the
fragment shader. The capture is the same primitive KWin's own blur effect uses; this
effect does not depend on that effect and does not reimplement its internals.

Next: verify the capture on screen (it needs a relogin, because KWin never re-reads a
`.so`), then switch on the frost over the captured desktop — `BackgroundRadius` in the
effect's config, **0 by default** precisely so that the first relogin verifies one
variable (is the desktop there?) before a second one changes how it looks:

```bash
kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundRadius 16
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
```

`/KWin reconfigure` looks like the obvious command and is the wrong one: it re-parses
`kwinrc` but never calls the effects' `reconfigure()`, so the effect keeps its old
values while the command reports success.

Each step is measured with `test-glass.sh` / `measure-glass.py` before the next one
starts — one variable at a time, because a test that changed two things at once once
reported "GLASS" for a window that had merely moved.

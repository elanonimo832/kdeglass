# KWin effect: macOS-style material

**Starting cold? Read [`docs/NEXT.md`](../docs/NEXT.md) first**: where the work is, what
to do next in order, the toolbox, and the three rules this repository learned the hard way.

Compositor effect that draws the material on the window chrome. The band covers the
**title bar only**, and the content stays sharp: the first full-window version was
verified working and unusable, because it blurred the text you were reading.

## Status

| | |
|---|---|
| Loads without breaking rendering | ✅ verified with screenshots (`negro=0.0%`) |
| Hooks into the paint chain | ✅ `OffscreenEffect` continues it; our own `drawWindow` override continues it explicitly |
| **Diffusion** | ✅ M1.2 wrote the 3x3 kernel; since M1.3a the frost is on the BACKDROP and the kernel's role is the band's tone and the chrome's baseline (a flat colour blurs to itself, so blurring the bar was never what made it look frosted) |
| **The band covers the title bar only** | ✅ M1.2b, verified by the user, survives window switching |
| **Real glass** — the band shows the desktop behind it | ✅ **verified on screen** (M1.3a, 2026-10-14): the band moves with the background, 73.8 against a threshold of 12, where the alpha-only attempt scored 3.2 |
| **Frost over the capture** | ✅ seen on screen (2026-10-14): the backdrop is blurred in two scales from the kit's `frost 6/16/16` (`BackgroundRadius`, default 16; 0 = sharp) |
| **No dark strip at the bar's bottom** | ✅ the bar's tone and chrome kernels clamp their samples to the bar, after a 14-row strip appeared on the user's screen when the tone kernel reached into the client below |
| **No ghost copies of the chrome** | ✅ the bar's tone is a MEDIAN of five samples, not a blur: a blur of the bar contains the chrome displaced by its radius, which read on screen as ghost buttons one radius above the real ones |
| **Chrome readable** | ✅ the title and the traffic lights are drawn crisp over the glass: the bar's blur is the blank that isolates them, and a tight baseline of its own keeps the halo off them |
| **Vibrancy** (chrome adapts to the glass) | 🟡 in the built plugin, **off by default** (`Vibrancy`, the minimum contrast; 0 disables). For dark backdrops, where the theme's dark title would otherwise disappear |
| **Rounded corners** | ✅ drawn by the effect (`CornerRadius`, default 20; only for normal, decorated, non-fullscreen windows -- a fullscreen window IS the screen). This theme's SVG has a 12 px arc, but aurorae clips the corner piece into a 1 px cell, so the frame arrives as a rectangle |
| **Refraction (70)** | ✅ implemented and **approved on screen** (2026-10-14): the band's frost is displaced toward the interior near the edges, so the rim is the same material as the centre, only bent. `Refraction` 20 px, chosen from a measurement (a 6 px bend against a 16 px frost moves the rim 5.4 levels, which is invisible) |
| **Dispersion (20)** | 🟡 modelled and measured, and **two verdicts were wrong before the metric was**. The first (9l) read a 0.5-level fringe at the 6 px bend of the time and called it below the perceptible level; the second (9p) read 13.1 and 30.7 with `|R - B|` in the band, called it colour you can see, and overturned the first. That metric measures the BACKDROP -- its own control read 135.7 with nothing bent -- so the third reading (§9w of `../docs/HANDOFF.md`) used the honest one, how far RED moves minus how far BLUE moves, which reads exactly 0.0 with the bend off: **2.0 levels at a 6 px bend and 5.7 at 20**. Subtle. The first verdict was right and 9p was wrong, and 9p's error came from a simulator that had drifted from the shader. Building it the expensive way costs three frosts; a cheap hybrid (three fetches of the already-reduced capture, per channel) is the candidate, and nothing gets built until the numbers ask for it |
| **Specular highlight (M1.5)** | 🔴 **built, measured, and turned OFF: it is not what Apple's edge is.** The user corrected it from the samples -- "en apple no es color fijo, toma del entorno los colores": the edge carries the ENVIRONMENT (their sample shows clear blue, 129/150/186, against the dock's edge), and a fixed white line destroys exactly that. The refraction is the term that carries it. Kept as a knob because the measurement was sound, but Apple's edge does not have it |

## The knobs, and which of them are live

Every one of these is read from `[Effect-macosglass2]` in `kwinrc`, and every one can be
changed WITHOUT a relogin:

```bash
./tune.sh GlassAlpha=0.25 BackgroundRadius=16 Vibrancy=0.35   # writes them and applies ONCE
./tune.sh --preset apple                                      # the numbers in tokens-kit.toml
./tune.sh --reset                                             # back to the defaults
./tune.sh                                                     # what is set right now
```

`tune.sh` is the short way and the safe way: it checks every key against the ones the effect
actually reads (a typo would otherwise be written, reported as success and ignored), calls the
one D-Bus method that reaches an effect's `reconfigure()`, and reads the journal back so that
"applied" means measured. By hand it is the same two commands:

`/KWin reconfigure` looks like the obvious command and is the wrong one: it re-parses
`kwinrc` but never calls the effects' `reconfigure()`, so the effect keeps its old values
while the command reports success.

| Key | Default | What it does |
|---|---|---|
| `BackgroundRadius` | 16 | frost radius, in screen pixels (0 = the sharp composite) |
| `FrostDownsample` | 0 | factor the backdrop is captured at; 0 derives it (radius/8). Capped at **2**, because a bilinear blit minifying by 2 reads exactly the four texels of each block -- a true box -- while by 4 it reads four of sixteen and aliases into Moire over text |
| `GlassAlpha` | 0.25 | how much of the bar's own tone the glass keeps -- Apple's `[liquid_glass] opacity = 25` |
| `CornerRadius` | 20 | radius of the window's corners; 0 leaves whatever the decoration drew |
| `CornerSmoothing` | 0.0 | the squircle: Apple's corners are continuous curvature, not circular arcs. The kit's `cornerSmoothing = 0.6` builds a **CLOTHOID** (Euler spiral): its curvature rises LINEARLY from 0 at the straight edge to `1/R` at the arc (`kappa(s) = s/(R*L)`), so it is curvature-continuous (G2) by construction; the arc keeps its measure `90*(1-s)`, and the edge offset `p` falls out of the corner's symmetry (measured 30.09, not `(1+s)*R`). **0 is exactly the circular arc approved on screen**. The clothoid is ~1 px FULLER than that circle and its middle is no longer the arc -- a measured shape change, reported rather than hidden -- where the Figma G1 construction it replaced spiked +46.9% over the arc (the angle in the highlight) and kept the middle on the circle. `simulate.py --corners` prints the table; both implementations integrate the heading and search the PIECEWISE boundary in segments, with the edges as rays from `edgeQ = R - p`. A super-ellipse with an invented calibration lived here before that (HANDOFF 10c) |
| `ChromeLow` | 0.06 | luminance deviation that counts as chrome (the upper threshold is 3x this) |
| `Vibrancy` | 0.0 (off) | minimum contrast the achromatic chrome keeps against the glass; try 0.30-0.45 on dark backdrops |
| `FrostRadius` | 6 | floor for the radius the bar's tone is averaged over (the tone is averaged over half the bar's height, which is what keeps the title out of the glass) |
| `CaptureSubRect` | true (on) | the capture's EXTENT. ON captures the FRAME plus the kernels' reach on EVERY side -- the environment AROUND the window, read from the screen, not capped inside the window's own shadow margins, or the top edge has nothing to bend into and only the bottom curves -- instead of the whole expanded window (audit finding 1: a maximised window 3840x2160 becomes 3840x~126; on the Konsole measured here 933x762 becomes 993x126; ~6-17x less traffic per window per repaint). OFF captures the whole expanded geometry, the pre-audit behaviour, kept as the escape hatch. The frame-to-capture mapping is applied in BOTH modes; `measure-alignment.py` reports (0, 0) |
| `Rim` | 0.30 | the edge highlight: the AMPLIFIED backdrop over a `RimWidth`-wide falloff, not a white line. Apple's edge is refraction (it bends the background), measured as bright coloured bands 215-236 top and 206-218 bottom against a middle of 168-190 |
| `MaterialGain` | 1.60 | multiplies the frosted backdrop before the bar's tone is mixed in: the GAIN that Apple's Dock measures at 1.6 and that a plain blend cannot produce (it would need `1-a > 1`). 1.0 is off |
| `Refraction` | 20.0 | how far the edge's copy of the backdrop is bent toward the interior, in pixels: the kit's `refraction = 70`. 0 disables the bend |
| `RimColour` | 1.8 | how much the edge band's own chroma is multiplied -- the environment's colour, stronger, which is what Apple's edge does (their sample: a band at chroma 57 against surroundings at 1). 1.0 leaves it as the frost delivered it, and the boost is limited per pixel so it can NEVER turn the edge white: past the display's edge the colour simply stops growing |
| `Specular` | 0.7 | the highlight's strength as a mix toward white at the TOP edge; the kit's `light_angle = 0` puts it there, and Apple's sample measures 236 against a middle of 180. 0.55 of it at the bottom (206 in that sample: a lift of 26 against 56, and our non-linear response reaches that ratio at 0.55) |
| `SpecularWidth` | 6.0 | its spread in pixels, from the kit's `splay_regular = 20` |
| `RimWidth` | 12.0 | how wide the edge band is, in pixels: Apple's reads as a border, five pixels read as a seam |
| `MaterialBoost` | 1.20 | how much the material AMPLIFIES the backdrop's colour instead of veiling it. 1.0 is off; the value measured on Apple's Dock is **1.6** |
| `BackgroundFlipV` | false | only for a rotated output, where KWin's blit takes a different branch |


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

Five instruments live here, and the rest were retired to `tests/archive/` when their
verdict stopped meaning anything: `test-installed.sh` looked for M1.1's flat marker,
`test-hot.sh` and `calibrate.sh` waited for `CALIB` lines the effect no longer emits, and
`test-diffusion.sh` measured M1.2's band diffusion, which the design no longer claims. A
live script that cannot say anything is worse than no script, because it teaches the reader
to ignore verdicts -- the same lesson as the false `WARNING` lines below.

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

And three instruments that measure the material rather than the loading:

| File | What for |
|---|---|
| `measure-glass.py` | does the bar take colour from what is behind it |
| `measure-alignment.py` | is the backdrop sampled where it belongs (step 3d) |
| `measure-corner.py` | the SHAPE of a corner, read from pixels, and its CURVATURE: `--self-test` runs the synthetic known-value cases and `--curvature circle\|figma\|clothoid\|superellipse:N\|g2bezier` reports kappa(s), whether it overshoots the arc's 1/R (the "angle" the eye sees) and how many times |

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

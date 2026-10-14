# Roadmap

## The working order of the original brief

```
1. Collect the Golden Gate tokens into a file         <- the first step
2. The portable declarative layer                     <- 1 day, immediate value
3. The generator: tokens -> QStyle + GTK CSS + KWin   <- 1-2 weeks
4. The complete QStyle                                <- 1-3 months
5. KWin effect (material + corner clipping)           <- on top of 4
```

## Where we are

| Brief step | Status |
|---|---|
| 1. Tokens | ✅ **done** — 859 tokens, with provenance |
| 2. Portable declarative layer | 🟡 **almost** — color, GTK and decoration; the Plasma global theme is missing |
| 3. Generator | ✅ **done** — reproducible byte for byte |
| 4. QStyle | ⬜ **not started** |
| 5. KWin effect | 🟡 **in progress** — it draws the material: diffusion and the title-bar band are verified on screen, and the M1.3a desktop capture is implemented and waiting for a relogin |

## Milestones

Each milestone has a verifiable **done criterion**. A milestone is not done because
it looks like it works: it is done when a test proves it and **fails** when it is broken.

---

### M1 — The effect draws the material ⬅ **in progress**

Done in small steps, each measured before the next one starts:

| Sub-step | What it draws | Criterion | State |
|---|---|---|---|
| M1.1 | A flat colour patch at the window's top-left | visible, anchored to the window, `black=0%` | ✅ **done** |
| M1.2 | Diffusion (frost 6/16/16) | content softens, measurable as loss of local contrast | ✅ **done** |
| M1.2b | The band covers the TITLE BAR only | bar blurred, content sharp, and it STAYS across window switches | ✅ **done** |
| M1.3 | Refraction (70) | the edge bends; measurable with a grid pattern | |
| M1.4 | Dispersion (20) | the edge splits into channels; measured in the colour | |
| M1.5 | Specular highlight + darkened edge (alpha 20) | matches the kit | |

#### M1.3a — in progress, and it needs a different mechanism (2026-10-14)

A translucent band was implemented (`kGlassAlpha` 0.55 plus
`data.setTranslucent()` in `prePaintWindow`) and **measured OPAQUE** by
`test-glass.sh`: with the window held still and only the background changed, the
bar moved by 3.2 where 12 is the threshold.

That is a mechanism limit, not a defect in the translucency work. The shader's only
input is the window's own texture, so no alpha and no uniform can put the desktop
into it — an alpha of 0 would still show the window's own black. Showing the
background requires CAPTURING it with `GLFramebuffer::blitFromRenderTarget`, which
is exactly what KWin's own blur effect does for the whole window.

**Where it stands.** The capture is **verified on screen** (2026-10-14): with the
window held still and only the background changed, the band moved by **73.8** where 12
is the threshold — the alpha-only attempt scored 3.2 — and the effect's own counter
read `capture: ok=1200 refused=0`. The desktop is copied into an owned `GLTexture` over
the window's expanded geometry, clamped to the render target, and composited in the
fragment shader.

The frost over that capture is **seen on screen**: `BackgroundRadius` (the kit's outer
16 by default, 0 for the sharp composite) blurs the backdrop in two scales, because a
single 3x3 at the outer spacing samples nine isolated points and text behind the window
reads as nine ghost copies of it. It is tuned live with
`qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2` --
note that `/KWin reconfigure` does NOT reach the effects, which cost a session of
believing a value had been applied when it had not.

The chrome stays readable: the bar's own blur is the *baseline* that isolates the title
text and the buttons, which are drawn crisp on top of the glass -- the way macOS does it,
the glass behind the chrome and not over it. An earlier paragraph here said the band took
its shape from the decoration's alpha; that was tried, did nothing (the frame arrives as a
rectangle, see below) and was replaced by a clip the effect draws itself. `GlassAlpha`
(bar opacity), `ChromeRadius` and `ChromeLow` (how the chrome is told apart from the bar)
are settings, like the frost radius.

The corners are done as well, which is the first piece of **M2**: the theme's SVG has a
12 px arc for its top corners, but aurorae draws that piece in a cell as narrow as the
frame's border (1 px in this theme), so the arc is clipped away and the frame arrives as a
rectangle. Rather than patch the theme, the effect draws the rounded rectangle itself --
`CornerRadius`, default 16, 0 to disable -- and discards what falls outside it, which is
the same clipping M2 needs anyway.

The frost pre-smooths now instead of sampling: the backdrop is captured already reduced by
a scaled framebuffer blit -- the technique KWin's own blur effect uses. GL minifies with
bilinear filtering rather than a true box average, which is exactly enough to stop nine
taps from sampling text, and text behind a window dissolves into haze instead of staying
readable with ghost copies of itself.

Left for the next step: settle whether the captured
background is sampled with the right size and offset — the shader's sizes come from
`frameGeometry()` while KWin's texture is the expanded geometry, which the decoration
makes 933x765 against a 905x751 frame. The answer needs TEXT behind the window; a flat
wallpaper cannot show a 1.9% scale error. What is already measured is the band's
shape, and it is correct: 39 rows from the window's top edge to the client top, the
window's full width, nothing painted into the shadow (see the risks list in
`HANDOFF.md`).

**Done when**, so the milestone can be closed instead of drifting: the band follows what
is behind the window (`measure-glass.py` at or above the threshold, with the window held
still -- met, 73.8 against 12), the frost AVERAGES the backdrop instead of sampling it, the
chrome stays legible over it (`Vibrancy` is available for dark backdrops and off by
default), the corners are round, and `measure-alignment.py` reports either (0, 0) or a
displacement that has been fixed. The last box is the one still open.

**The full analysis, the next step in detail, and its risks are in
[`HANDOFF.md`](HANDOFF.md).** Start there, not here.

#### M1.2 and M1.2b — done (2026-10-14)

The effect derives from `OffscreenEffect` and blurs the window's own texture with a
3x3 box-blur shader whose radius is the kit's `frost 6`. The band covers the title
bar and stops there, so the content stays readable -- the first full-window version
was verified working and unusable, because it blurred the text you are reading.

The band height is MEASURED, not assumed:

    barHeight = clientGeometry().top() - frameGeometry().top()

which works for any decoration theme. A window with client-side decoration reports
those two rectangles as identical, so the difference is zero and there is nothing
to cover: such windows get no material, which is the honest outcome rather than a
guess. A configurable fallback was tried and removed -- it blurred Zen Browser,
which the user did not want.

WHAT IT COST, and every item is a variation of the same mistake:

  - `setUniform()` without binding the shader. It is glUniform1f(), so it wrote
    into another program, uRadius stayed 0, all nine taps sampled the same texel,
    and the output equalled the input. A perfect no-op with no error.
  - the band landed at the BOTTOM. The offscreen texture's v axis runs opposite to
    window coordinates, so the distance from the top is (1 - vTexCoord.y).
  - the material vanished when the window was moved or focus changed. One shader
    object is shared by every window, so uniforms set once per window at add time
    are globals that the last window overwrites. They now go in apply().
  - KWin does not re-read a plugin's .so once loaded, so a changed file needs a
    session restart. Several rounds were spent testing a build KWin had not loaded.

THREE OF THESE ARE THE SAME BUG: state belonging to one window kept somewhere that
belongs to all of them. The unbound uniform wrote to the wrong program, the global
uniform held another window's value, and the CSD fallback applied one guess to
every window. Worth naming as a class rather than as three incidents.

#### M1.1 — done (2026-10-14)

A 48x48 cyan patch drawn with `glScissor` + `glClear` into the window's
framebuffer, anchored to its top-left corner. Verified on screen **and** by
measurement: with the effect off and on, nothing moved, 5723 pixels changed
against 2304 for a single patch — the two or three windows that were open.

What it cost, recorded because **none of it was found by the automatic
measurements** — three of them gave wrong verdicts, and what found the bug was
the user describing the behaviour: *"if I moved the app up, the patch went down"*.

  - the window's GLOBAL geometry has to be scaled into device pixels
  - `frameGeometry().y()` is ALREADY measured from the top of the screen, so
    flipping Y for glScissor inverts the vertical movement
  - `mapToDeviceCoordinates()` looked like the culprit but is an identity on a
    single output at 0,0 with scale 1 — eliminated by measuring, not arguing
  - KWin does NOT re-read a plugin's `.so` once loaded: it keeps the build from
    its own start-up, so a changed file needs a fresh session
  - hot-loading only reaches `paintWindow` for windows that are DAMAGED; loading
    an effect damages nothing, which is why a plain `loadEffect` appears to do
    nothing. `test-hot.sh` damages windows on purpose
  - a screenshot diff is blind to DIRECTION: it counted the changed pixels
    correctly and still could not say the patch was anchored wrongly

Two regression tests pin the anchoring and the sign, both verified by breaking
them on purpose.

**Done when:** the five sub-steps pass, the harness is still green, and there are
screenshots in `evidence/` that prove it.

**Risk:** this is the most delicate part (OpenGL over KWin's framebuffer). A mistake
can leave a black screen. Mitigation: `test-installed.sh` always unloads,
`verify-chain.sh` aborts before installing, and `RECOVER-KDE.sh reanimar` recovers
on the fly.

---

### M2 — Corner clipping (squircle)

macOS does not use rounded corners: it uses a **squircle** (`cornerSmoothing = 0.6`,
measured across 2244 nodes of the kit). KWin has `Effect::setShape` and the shape API.

**Done when:** windows are clipped with a squircle and not with a circular arc, using
the kit's geometry, and there is a visual comparison in `evidence/`.

---

### M3 — Plasma global theme

The full declarative layer is missing: `PlasmaStyle`, `LookAndFeel` and the
collections that link everything together so it can be applied in one go.

**Done when:** there is a global theme package selectable in
*System Settings → Global Theme*, and applying it breaks nothing.

---

### M4 — Typography

The 80 typography tokens are extracted (sizes, weights, *tracking*), but
**not applied**. Inter replaces SF Pro (SIL OFL: SF Pro is not redistributable).

**Done when:** KDE's text metrics use the macOS scale and there is a comparison of
rendered text in `evidence/`.

**Note:** macOS **does not have Dynamic Type** (verified in the HIG). The scale is fixed.

---

### M5 — Icon geometry

The squircle radii of the folder icons are missing. There are iOS values in the kit,
but the macOS ones **could not be confirmed**.

**Done when:** the folder icons carry the correct squircle, or it is documented that
the value is not verifiable.

---

### M6 — Complete QStyle

The biggest step of the brief (1-3 months). A QStyle of our own in C++ so that native
Qt applications are drawn like macOS, without depending on Kvantum.

**Done when:** it exists, is installed, and is selectable without breaking applications.

**Note:** it is the only milestone that is **not** on top of anything already done: it
is independent, large work. Milestones M1-M5 provide value without it.

---

## What remains to be verified (open risks)

| Risk | Status |
|---|---|
| GTK CSS in a real application | **unverified** — it is the biggest open risk of the declarative layer |
| The `KdeMacosLight` scheme in use | only the dark one has been tested |
| The decoration with unfocused windows | the traffic lights must stay gray (`#48484A`) |
| The seven numeric values of macOS 27 | **never confirmed** independently: macOS 27 is pre-release and only the community kit was measured |

## System status (2026-10-14)

| Piece | Status |
|---|---|
| `KdeMacOS` decoration | ✅ active — traffic lights on the left, 12 px, 8 px apart |
| `macosglass2` effect | ✅ loads without breaking rendering |
| Color scheme | `BreezeDark` (switched to `KdeMacosDark` from Settings) |
| Tokens | ✅ 859, with provenance |
| Test harness | ✅ `tests/run.sh`, all green |

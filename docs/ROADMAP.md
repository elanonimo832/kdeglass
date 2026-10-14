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
| 5. KWin effect | 🟡 **halfway** — it loads and hooks in; **the shader is missing** |

## Milestones

Each milestone has a verifiable **done criterion**. A milestone is not done because
it looks like it works: it is done when a test proves it and **fails** when it is broken.

---

### M1 — The effect draws the material ⬅ **the next one**

The effect loads and hooks into the paint chain, but **draws nothing**.
It is the only big thing missing from step 5.

It will be done in small steps, each one measured with `effect-kwin/test-installed.sh`:

| Sub-step | What it draws | Criterion |
|---|---|---|
| M1.1 | A flat color over the window | the effect is visible, and `negro=0%` |
| M1.2 | Background diffusion (frost) | the background blurs, measurable by contrast |
| M1.3 | Refraction (70) | the edge bends; measurable with a grid pattern |
| M1.4 | Dispersion (20) | the edge splits into channels; measurable in the color |
| M1.5 | Specular highlight + darkened edge (alpha 20) | matches the kit |

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

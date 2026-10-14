# Design references: where the numbers come from

Document that answers a specific question: **can we start defining the visual
system without seeing macOS 27?** Short answer: **yes, and nobody needs to see it. What
is needed are the numbers, and the numbers are published.**

- Related documents: [ANALYSIS.md](ANALYSIS.md) · [INSTALLATION.md](INSTALLATION.md) · [VERIFICATION-ANNEX.md](VERIFICATION-ANNEX.md)
- Date: 13/10/2025

---

## 1. The honest answer about "seeing" macOS 27

It helps to separate two things that get confused:

| | Do I have it? |
|---|---|
| **The visual language** of macOS (restraint, 1 px bezel, blue accent, material glass, type scale, hierarchy) | **Yes**, in detail |
| **The exact numeric values of macOS 27 Golden Gate** (radii, alphas, colors, opacities) | **No** — and **nobody** has them from memory |

And here is the point that matters: **for this project, the second row is the only one that
counts, and it does not require me to see anything.** A QStyle is not built by looking at a
photo: it is built by writing `6` in a `Tokens.h`. The design *is* the number.

> Conclusion: I do not need to see macOS 27. I need the repository to **cite the source of
> every number**, just like any other piece of project data.

---

## 2. The authorized source exists

Apple publishes the official design kits. Verified at
[developer.apple.com/design/resources](https://developer.apple.com/design/resources/):

| Resource | Link |
|---|---|
| **macOS 27 UI Kit — Figma (official)** | https://www.figma.com/community/file/1651309434229735362/macos-27 |
| **macOS 27 UI Kit — Sketch (official)** | https://sketch.com/s/57153a31-3379-4737-8ac6-dbfd6525f052 |
| iOS/iPadOS 27 UI Kit | https://www.figma.com/community/file/1651309003795292092/ios-and-ipados-27 |
| Icon template 27 (Figma/Sketch/PS/AI) | In the same index |

This is exactly what the project needs: **Apple's source of truth, with the real
values, published and citable.** Also, being the official kit, it resolves the legal
notice: **numbers** are extracted, Apple assets are not redistributed.

**Known risk:** the kits are updated between betas. Every extracted token must carry a
capture date and version (already planned in [ANALYSIS.md](ANALYSIS.md) §4.4).

---

## 3. Finding that improves the brief: there are three "radii", not one

Looking for measurable material, I found a specification from a community kit for
macOS 27 that **contradicts a simplification in the brief**. The brief says:

```
WINDOWS ..... a SINGLE corner radius for all
ICONS ....... mandatory squircle, plus glass layers
```

Correct in intention, but **it mixes three metrics that are distinct in macOS**:

| Metric | What it is | Order of magnitude |
|---|---|---|
| **Control radius** | Buttons, text fields, checkbox, combo | **Small**: ~4 to 10 pt depending on control size |
| **Window radius** | The corner of the whole window | Another value, different from the control one |
| **Icon squircle** | The superellipse of app icons | It is not a radius: it is a continuous curve |

And the practical consequence, which is money: **if `tokens.toml` has a single
`radio` key, the QStyle will apply the same one to controls and windows and it will look wrong.** The
token system needs three shape families from day one:

```toml
[forma.control]
radio_mini     = 4      # provisional
radio_pequeno  = 5      # provisional
radio_regular  = 6      # provisional  <- the standard control (13 pt text)
radio_grande   = 8      # provisional

[forma.ventana]
radio          = ?      # PENDING MEASUREMENT in the official kit

[forma.icono]
superelipse    = true   # "squircle": continuous curve, not a circular radius
exponente      = ?      # PENDING MEASUREMENT
```

The values marked as *provisional* come from a measurement of a **community** kit,
not the official one: they serve to get started, **not as a specification**. See §5.

### 3.1 The corner inconsistency in Tahoe

The brief says that Golden Gate unifies the window radius. There is independent
evidence that in Tahoe (macOS 26) **windows had different radii from each other**
— it is literally one of the complaints collected in a Hacker News thread titled
[*"macOS Tahoe windows have different corner radiuses"*](https://hn.nuxt.dev/item/47279761).

This **reinforces** the brief's thesis: Golden Gate is the correction, and the list of
"corrections" that the brief uses as a token list makes sense. The brief is right here
and now there is a source that backs it up.

---

## 4. Measured values (VERIFIED against your own export)

> **Update:** the values in this section, which were provisional and came from
> a community kit, have been **verified** on receiving the kit's Variables
> export: they match exactly (dark blue `#0091FF`, accents, and the alpha
> scales of `Fills` and `Labels`). The final values, with light and dark, are in
> [`tokens/tokens-colors.toml`](tokens/tokens-colors.toml) and the detail in
> [`FIGMA-INVENTORY.md`](FIGMA-INVENTORY.md). The classic `#007AFF` does **not** appear: the
> accent of macOS 27 is `#0088FF` in light and `#0091FF` in dark.

Extracted from [Fluent-Qt's `macos.md`](https://raw.githubusercontent.com/calvinhxx/Fluent-Qt/6f0ef75996f0b2fcba92fdd276eff61dc2a6b0f0/docs/design-languages/macos.md),
which documents its method and the Figma `nodeId`s in
[`figma-sources.md`](https://raw.githubusercontent.com/calvinhxx/Fluent-Qt/6f0ef75996f0b2fcba92fdd276eff61dc2a6b0f0/docs/design-languages/figma-sources.md).
**Reproducible and auditable method**, which is the valuable part.

### Accent colors

| Tint | Opaque | Vibrant |
|---|---|---|
| **Blue** (default accent) | `#0091FF` | `#0A99FF` |
| Green | `#30D158` | `#3BDB63` |
| Red | `#FF4245` | `#FF4747` |
| Orange | `#FF9230` | `#FF9E33` |
| Yellow | `#FFD600` | `#FFE014` |
| Pink | `#FF375F` | `#FF4169` |
| Teal | `#00DAC3` | `#2DE0CD` |
| Indigo | `#6D7CFF` | `#7163FF` |
| Purple | `#DB34F2` | `#E647FC` |
| Brown | `#B78A66` | `#C29672` |
| Gray | `#98989F` | — |

### Labels and fills: the "veil" pattern

Apple does not define grays for text: it defines **white with decreasing alpha** (and black on
light). This pattern is the architectural key of the material:

| | Label | Fill |
|---|---|---|
| Primary | `#FFFFFF` @ 85 % | `#FFFFFF` @ 10 % |
| Secondary | @ 55 % | @ 8 % |
| Tertiary | @ 25 % | @ 5 % |
| Quaternary | @ 10 % | @ 3 % |

This translates **directly** to a QStyle and to GTK CSS without ambiguity, and it is more
important than any radius: it is what makes a control look "macOS" on
any background.

### Typography

- System font: **SF Pro** (Text/Display). **Not redistributable** → it is replaced by
  Inter or another one with calibrated metrics (§9 of [INSTALLATION.md](INSTALLATION.md)).
- Standard control text: **13 pt**. (Confirmed by the official HIG: macOS, by
  default 13 pt, minimum 10 pt.)
- Scale: large title 26, title-1 22, **headline 13 in Bold** (not semibold), title-3 15,
  body 13, callout 12, subheadline 11, footnote and captions 10.

> **RESOLVED.** This section was closed with the official Human Interface Guidelines:
> the full table of "macOS built-in text styles" and the tracking values are in
> [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml), extracted
> from the authorized source with `tools/figma/hig-typography.py`. See §8.
- **Text color by alpha**, not by absolute value (see the veil table).

### Controls (shapes and measurements mentioned)

| Control | Measurement |
|---|---|
| Checkbox | square ~14, radius ~3.5 |
| Radio button | circle ~16 |
| Switch (track) | full pill; **ON = blue accent, not green** (difference from iOS) |
| Slider: track | ~3–4 px |
| Slider: thumb | white circle ~16–20 |
| Progress bar | ~6 pt, fully rounded |
| Progress ring | ~3 pt |
| Text field | radius ~5–6 + 1 px border; **focus = accent ring**, not a thicker border |
| Window traffic lights | ~12 px: close `#FF5F57`, minimize `#FFBD2E`, zoom `#28C840`; the glyphs **only on mouse hover**; inactive = gray |

### The two golden rules of the macOS idiom

1. **Restraint, not spectacle.** Subtle fill + **1 px hairline border** + very
   soft shadow (the *bezel*). Never thick outlines or large radii.
2. **The accent is the only color with a voice.** Everything else is neutral with a veil. Text on
   accent is **white**.

---

## 5. Warnings about these values (important)

1. **The source is not Apple.** They are measurements of a **community** Figma kit. The
   verification in §2 revealed that the **official macOS 27 kit has a different `fileKey`**
   (`1651309434229735362`) than the one that project measured. Therefore these values
   may correspond to a different revision of the kit. **Treat as provisional.**
2. **They were captured in dark appearance.** The extraction method resolves **a single
   appearance** per query; the label alphas and the fills above are from
   **dark mode**. The light one must be extracted separately.
3. **The typography has a useful point of doubt**: on the same page it is said that the control
   text is "13 pt" and, a little earlier, that in macOS the body is "13" in a context
   where the 13 appears next to a line height. **The size will be fine; the
   line height is what has to be confirmed** — and it is precisely the token the brief did not have.
4. **The blue `#0091FF` does not match the classic `systemBlue`** (`#007AFF` light /
   `#0A84FF` dark). It may be the beta 27 refresh or the effect of the dark
   appearance. Do not fix the accent without checking it in the official kit.

---

## 6. Two paths to get the good numbers

### Path A · The official Figma kit (recommended)

The official kit is a **public and free** file from the Figma community. With a
free account you can:

1. Open the kit: https://www.figma.com/community/file/1651309434229735362/macos-27
2. "Duplicate" it to your own draft (free, no paid team).
3. Export the values. The most productive path found in the research is
   **extracting the file's variables** instead of reading them by eye — that way the result is
   a table, not an impression.

Expected output: a `tokens-captura-<fecha>.toml` with **values and provenance**, ready to
be the source of `tokens.toml`. And since it is extracted from the official kit, the legal
notice in the brief is covered: numbers yes, Apple assets no.

### Path B · Measure screenshots (complementary, and automatable)

It serves to **verify** what path A gives and to capture things a kit does not show: the
real material composited over a real background, HDR, animations.

**This machine already has the tools** (verified):

```
magick / convert / identify        -> ImageMagick, present
python3 + PIL 12.3.0 + numpy 2.5.4 -> present
spectacle                          -> present (screenshots on Wayland/KDE)
```

What can be measured automatically with that:

| Token | How it is measured |
|---|---|
| Corner radius | By alpha channel: count of transparent pixels in the corner, fit to a quarter circle |
| Exact colors | Point sampling and dominant histogram calculation |
| Material alpha / translucency | **Inverse compositing math**: with the same material over two known backgrounds, the alpha is solved for |
| Hairline border thickness | Intensity profile in a cross-section |
| Contrast / legibility | WCAG contrast ratio calculation (useful against the Tahoe criticism) |
| Spacing | Edge detection and measurement of separations between controls |

**Requirement for it to work:** screenshots at **one logical pixel per physical pixel**
(1× scale). At 2× scale you have to divide, and there the odd values are lost.

This machine has a monitor at **1× scale**, which is the right thing for measuring, but **there is no
macOS**: the screenshots have to come from outside.

### What CANNOT be measured from a screenshot

- **HDR** (needs metadata and a compatible monitor) — another reason to leave it for v3.
- **Behavior**: animations, gestures, timing curves. That can only be described.

---

## 7. What I need, specifically

If you choose **path A**: nothing from me. You or I with a Figma account, extraction of
variables, and I turn the output into `tokens.toml` with the three shape axes and the typographic
axis.

If you choose **path B**, I need screenshots with these names. The name matters because
the measurement script automates batch processing:

```
capturas/
├── 01-ventana-activa-claro.png      <- window corner over a flat background
├── 02-ventana-activa-oscuro.png
├── 03-ventana-inactiva-oscuro.png
├── 04-botones-claro.png             <- normal, prominent, disabled button
├── 05-botones-oscuro.png
├── 06-campo-texto-foco-oscuro.png   <- the focus ring
├── 07-controles-claro.png           <- checkbox, radio, switch ON/OFF, slider
├── 08-segmentado-oscuro.png
├── 09-menu-abierto-oscuro.png       <- the accent highlight
├── 10-barralateral-oscuro.png       <- flush, not floating (brief token)
├── 11-material-sobre-fondo-1.png    <- SAME material over a light background
├── 12-material-sobre-fondo-2.png    <- SAME material over a dark background
│                                       (the 11+12 pair allows solving for the alpha)
└── 13-iconos.png                    <- to measure the squircle
```

Capture rules: **1×** scale, lossless PNG, **one window per
screenshot** with a flat background behind, and the two material screenshots (11 and 12) with **the same
content** behind so that solving for the alpha is valid.

**Legal note:** these screenshots are Apple material. They go **outside the public
repository** (already planned in [ANALYSIS.md](ANALYSIS.md) §6). The repository keeps the
**numbers** and the **measurement script**, not the images.

---

## 8. Proposed startup plan

> **Update:** steps 1 and 3 are no longer necessary for typography. Apple's official
> HIG publishes the full table of macOS styles (sizes, line heights,
> weights and tracking), so the typographic axis is **closed without measuring screenshots**. See
> [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml).

```
STEP 1 · Get the official kit (path A)             <- unblocks everything else
         and/or 1x screenshots (path B)

STEP 2 · tokens.toml with the THREE shape axes     <- fixes the mix-up of §3
         + typographic axis (family, sizes, line height, spacing)
         + the veil pattern (white @ alpha) as the material base

STEP 3 · Measurement script                        <- turns screenshots into TOML
         (tested with the real screenshots, not with examples)

STEP 4 · Scheme generator + GTK CSS                <- visible deliverable without QStyle
         (step 2 of the ANALYSIS.md plan)

STEP 5 · With verified numbers: start the QStyle
```

Step 3 is optional if path A gives everything needed — and it probably will for
controls and colors. It is kept for the material and for verification, because **a screenshot
measures the real result**, whereas a kit measures Apple's intention.

---

## 9. Summary

- **I do not need to see macOS 27.** A QStyle is defined with numbers, and the numbers
  are the design.
- **Apple publishes the official macOS 27 kit** (Figma and Sketch). That is the source of
  truth, it is public and it is what solves the problem. Verified today in Apple's official
  Design Resources index.
- **The provisional values in §4 are usable but from a community kit**, with a
  `fileKey` different from the official one. They serve to bootstrap `tokens.toml`; not as
  a final specification.
- **The brief has a simplification to correct:** there are **three** shape families
  (control, window, icon), not a single radius. A single `radio` in the tokens will produce an
  incorrect QStyle.
- **What I do know solidly is the language, not the figures**: restraint, 1 px hairline bezel,
  single accent, alpha veil, 13 pt type scale. That is enough to design
  the token architecture; the figures are extracted.

# Inventory of the Figma exports

What has been received, what has been extracted and **what is missing**. With the provenance
notices, which here turned out to be the most important thing.

- Provenance and method: [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md)
- Tool: [tools/figma/](tools/figma/)
- Export date: 13/10/2026

## Result

```
16 collections received   ·   629 tokens converted   ·   16/16 valid TOML

  APPLICABLE TO macOS ...  146 tokens in  3 collections  ->  tokens/
  FROM OTHER SYSTEMS ....  483 tokens in 13 collections  ->  tokens/reference/
```

---

## 1. MAIN NOTICE: the file is multi-design-system

The Figma file from which these exports came **does not contain only the macOS
variables**. It also contains collections of **Material 3 (Google)**, of **Salesforce (SDS)**
and a generic color scale. Extracting everything and applying it would have put into the macOS
theme colors and metrics that are not Apple's — a silent error and hard to detect
afterwards.

Concrete proofs:

| Signal | What it means |
|---|---|
| `Schemes/Primary = #6750A4` | That violet is Material 3's **default Primary**. Apple does not use that |
| `Static/Display Large 57 / Line Height 64` | The Material 3 type scale |
| `Corner/Extra-small 4 · Small 8 · Medium 12 · Large 28` | The Material 3 shape scale |
| `Family Sans = Inter`, `Family Mono = Roboto Mono` | Families from another system |
| `Background/Utilities/Scrim`, `Blanket` | **Salesforce Lightning Design System** naming |

That is why the converter **classifies the provenance from the data itself**, not from the
file name: each generated TOML carries in `[_meta]` its `sistema` and its
`aplicable_macos`. The 13 foreign collections are in
[`tokens/reference/`](tokens/reference/README.md), with the reason for each one.

---

## 2. Collections applicable to macOS (146 tokens)

| ZIP | Modes | Tokens | Content |
|---|---|---|---|
| `Colors.zip` | Light, Dark | 63 | Accents, fills, labels, grays, misc |
| `Kit.zip` | Mode 1 | 18 | Component fills/borders + **Liquid Glass material** |
| `Sizes.zip` | Mini→XL | 65 | **Metrics of all controls** |

These three are the core of the theme, and among the three they cover **full color in light and
dark** and **control metrics**. That is exactly what was missing from the brief.

---

## 3. The Liquid Glass material, as numbers

`Kit.zip` brings the brief's material parameterized:

```
[kit.liquid_glass]
light_angle             = 0
opacity                 = 25
refraction              = 70
depth_regular           = 30
depth_medium_and_large  = 30
dispersion              = 20
frost_regular           = 6
frost_medium            = 16
frost_large             = 16
splay_regular           = 20
splay_medium_and_large  = 20
```

This **corrects the brief**. The brief described the material with three concepts ("diffusion,
darkened border, specular reflections"). The kit declares **seven parameters**, and two of
them do not appear in the brief at all:

- **`refraction` (70)** — the material *bends* what is behind it, it does not merely blur it. It is
  the difference between frosted glass and glass.
- **`dispersion` (20)** — chromatic separation at the edges. It is what gives a sense of
  physical thickness and what keeps Liquid Glass from looking like an ordinary blur.
- **`frost` with two values** (6 in Regular, 16 in Medium/Large) and `splay` separately: the
  material **is not the same at all control sizes**. They are two different diffusion axes,
  not a single "translucency slider" as the brief said.

**Architecture consequence:** the KWin effect will need the **control size** to
choose parameters. It is not a single value. The brief's model is poorer than the real one;
now there are numbers, and a shader with seven parameters is still a shader.

---

## 4. The control metrics (Sizes)

It solves the brief's shape hole, and confirms the correction I pointed out: **there is no single
radius, it scales with the control size**.

```
[global]     font_size = 13 (Mini 11) · height = 24
             radius = Mini 4 · Small 5 · Medium 6 · Large 7 · XL 9
[button]     padding_horizontal = Mini 7 · Small 10 · Medium 16 · Large 16 · XL 16
             radius = Medium 6 · Large 1000 · XL 1000
[checkbox]   radius = Mini 3.5 · Small 4.5 · Medium 5.5 · Large 6.5
[radio]      width  = Mini 12 · Small 14 · Medium 16 · Large 18
[toggle]     track_width = Mini 36 · Small 44 · Medium 54 · Large 64 · XL 80
             knob_width  = 32 (Medium), 50 when pressed
[segmented]  margins 10 · separator_height 14
[fields]     inset 8 · font_size 13
[menu]       height 24 · font_size 13
[slider]     knob 20×16 (25×20 when pressed) · track_inset 1
[stepper]    width 20 · radius 6
```

**`Button/Radius = 1000` in Large and XL** is Figma's way of saying "pill"
(radius = height/2). The macOS button **changes from rounded rectangle to pill depending on
the size**: a `tokens.toml` with a single button radius would be incorrect.

**And they verify the provisional values** of [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md) §4:
`Global/Radius` Medium = **6**, exactly what was cited from the community
specification. The chain is confirmed end to end.

The aliases (`Button/Radius = {Global.Radius}`) are **resolved** in the TOML, noting the
original target on the previous line so the chain can be audited.

---

## 5. What was received that is NOT applicable, and why

| ZIP | System | Reason |
|---|---|---|
| `M3.zip` | Material 3 | The complete Google system (196 tokens, 6 contrast variants) |
| `Typescale.zip` | Material 3 | Display/Headline/Title/Label/Body scale |
| `Typography Primitives.zip` | Material 3 | Weights 100-900, `Inter`/`Roboto Mono` families |
| `Shape.zip` | Material 3 | `Corner/None 0 · XS 4 · S 8 · M 12 · L 16 · XL 28 · Full 1000` |
| `Color.zip` | Salesforce (SDS) | `Utilities/Scrim`, `Blanket`, `Border` |
| `Color Primitives.zip` | Generic scale | 100-1000 palette |
| `Dimensions.zip` | **Apple iOS** | Sheet radii, status bar, home indicator |
| `Dynamic Type.zip` | **Apple iOS** | iOS's `Body` is 17 pt; macOS's is **13 pt** |
| `Text Leading.zip` | **Apple iOS** | iOS line heights |
| `Font theme.zip` | generic | `Roboto` font |
| `Typography.zip` | generic | References to the Material 3 scale |
| `Context.zip`, `Icons.zip` | — | Only the context name, without values |

**The error this avoids:** `Dynamic Type` brings an attractive and complete type scale
(12 sizes, with accessibility variants). Applying it to the desktop would be the
easiest mistake to make in the whole project, because it *looks* exactly like what is missing.
But it is the **iOS** scale: in macOS the control text is **13 pt**, not 17.

**The only usable thing in `Text Leading`:** the *ratio* line height/size. In
`Large (Default)`: Body 17/22 = **1.29**, Footnote 13/18 = 1.38, Caption 1 12/16 = 1.33.
That makes it possible to parameterize the `interlineado_escala` token I proposed in
[INSTALLATION.md](INSTALLATION.md) §9 — now with a measured proportion, not an invented one.

---

## 6. What is still missing

| Missing | Why | How it is obtained |
|---|---|---|
| ~~**macOS type scale**~~ | **RESOLVED by another route**: the official HIG publishes it in full | [`tokens/tokens-typography_macos.toml`](tokens/tokens-typography_macos.toml) |
| **Font size per control** | **RESOLVED** the same way: the 11 macOS styles include tracking | Same as the previous one |
| **macOS window, sheet and popover radii** | `Dimensions` is iOS; `Shape` is Material 3 | The `.fig`, in the node properties |
| **Icon squircle geometry** | It is not a variable, it is a path | The `.fig`, or the official App Icon Template |
| **Effects: shadows and hairline borders** | They are node properties | The `.fig` |
| **Layout spacings** | Mainly in nodes | The `.fig` |

None of the exports resolves the macOS typography — but **it no longer needs to**:
the official Human Interface Guidelines publish the full table of "macOS
built-in text styles", with sizes, line heights, weights and tracking. It is extracted in
[`tokens/tokens-typography_macos.toml`](tokens/tokens-typography_macos.toml), and it confirms
the `Sizes/Global/Font Size = 13` of the export. **The full `.fig` is needed** (`File → Save local copy`, only in the desktop
app). The decoder is already written and validated for that:
[tools/figma/README.md](tools/figma/README.md).

---

## 7. Reproduce

```bash
cd tools/figma
npm install
# everything, classified by provenance
python3 tokens-from-figma.py ../../tokens ../../figma-export/*.zip
# only what is applicable to macOS
python3 tokens-from-figma.py ../../tokens --solo-macos ../../figma-export/*.zip
```

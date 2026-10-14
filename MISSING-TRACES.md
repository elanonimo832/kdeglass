# Missing traces and how to get them

> **UPDATE: gap #1 and #2 are CLOSED.** Apple publishes the full table of
> "macOS built-in text styles" in the Human Interface Guidelines, with sizes, line heights,
> weights and **tracking**. It is extracted in
> [`tokens/tokens-typography_macos.toml`](tokens/tokens-typography_macos.toml) (80 tokens,
> authorized source). What is still true: **it was not in Figma** and still is not;
> what changes is that it did not need to be there.

Closing of the inventory. What is resolved, what is not, **why not** and where each
missing thing can be obtained. With the verification that the gap is not an oversight.

- Inventory of what was received: [FIGMA-INVENTORY.md](FIGMA-INVENTORY.md)
- References and method: [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md)

---

## 1. It is not that you cannot find it: it is not in the export

The important conclusion, verified against the files themselves:

> Searching more in the Figma Variables collection will not help, because
> **what is missing is not variables**. They are **node properties**, and the Variables
> export only carries what is declared as a variable.

Checked in the data:

| Check | Result |
|---|---|
| Style names in `Text Leading` | `Large Title, Title 1-3, Headline, Body, Callout, Subheadline, Footnote, Caption 1-2` → **iOS naming**, not macOS |
| Size keys in `Sizes` | Only `Global/Font Size = 13`. There is **no** `Body 13` or style scale |
| `Sizes` — variants | Mini, Small, Medium, Large, XL (5) |
| `Dynamic Type` — variants | 12 scales (xSmall→AX5) |
| `Text Leading` — variants | Default, Loose, Tight (3) |

That is: the kit **does have a complete typographic system**, but it is iOS's. The
macOS one (the one used by the menu bar, the sidebar and the desktop controls) is either
in another collection that was not exported, or lives directly in the document's text styles
— and those **do not come out in a Variables export** in any case.

The same holds for window radii, shadows and hairline borders: they are
properties of each node.

---

## 2. Final state: what there is

```
ACHIEVED (146 macOS tokens, validated)     ->  tokens/
  tokens-colors.toml    63   full color, light and dark, with exact alpha
  tokens-sizes.toml     65   metrics of all controls, by size
  tokens-kit.toml       18   Liquid Glass material + fills and borders

REFERENCE (483 tokens from other systems)       ->  tokens/reference/
  Material 3, Salesforce, iOS, generic scales
```

With this, most of the theme can already be built:

| Plan layer | Can it be done already? |
|---|---|
| KDE color schemes (light and dark) | **Yes**, with the 63 measured colors |
| Control metrics in the QStyle | **Yes**, with the 65 `Sizes` tokens |
| KWin material effect | **Yes**, with the 11 Liquid Glass parameters |
| GTK CSS | **Yes**, for color |
| Window radii | **No** — the datum is missing |
| macOS type scale | **Yes** — 11 styles, with line height, weight and tracking |
| Shadows and hairline borders | **No** — the effects are missing |

---

## 3. What is missing, one by one

| # | Missing | Why it is missing | How it is obtained |
|---|---|---|---|
| 1 | ~~**macOS type scale**~~ | **RESOLVED** with the official HIG | [`tokens/tokens-typography_macos.toml`](tokens/tokens-typography_macos.toml) |
| 2 | ~~**Font size per control**~~ | **RESOLVED**: the macOS scale includes the 11 styles and tracking | Same as the previous one |
| 3 | **Window, sheet and popover radii** | They are node properties | Screenshots of windows over a flat background |
| 4 | **Window and menu shadows** | They are node effects | Screenshots, measuring the fade |
| 5 | **1 px hairline border** (color and alpha) | It is a node stroke | Screenshots, intensity profile |
| 6 | **Icon squircle geometry** | It is a vector path | Official icon template, or measuring an icon |
| 7 | **Layout spacings** | They live in the nodes | Screenshots, measuring distances |

**Five** gaps remain, not seven: typography was resolved through the documentary route instead
of the measurement one. None of the five remaining ones blocks the start: the color schemes,
the control metrics, the material and now also the typography can be built **today**.

---

## 4. How to get each gap

### Path A · Screenshots (the most accessible)

**You do not need a Mac.** macOS screenshots at **1× scale** are enough, and this machine
already has the tools to measure them (`magick`, PIL, numpy):

| Gap | How it is measured from a screenshot |
|---|---|
| Window radii (#3) | By alpha channel: count of transparent pixels in the corner, fit to a quarter circle |
| Shadows (#4) | Intensity profile from the border outward; fit of the falloff |
| Hairline border (#5) | Cross-section: width and peak value |
| Spacings (#7) | Edge detection and measurement between them |
| ~~Typography (#1, #2)~~ | **No longer needs measuring**: it is published in the HIG |

If you have access to a Mac —your own, someone else's, or even a virtual machine— with the list
of screenshots in [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md) §7 it is enough.

### Path B · The full `.fig`

`File → Save local copy` in the **desktop app** (it does not exist in the browser). It brings the text
styles and the node properties, which is exactly what is missing. The
decoder is written and validated: [tools/figma/README.md](tools/figma/README.md).

### Path C · Documentation and convention, for point 1

The base size is already measured: **13 pt** for standard control text. The rest of the
macOS scale can be taken from the documented convention (window title 13
semibold, large titles 22 and 26, small text 10-11) **marking each value as not
measured**, to replace it when there are screenshots. It is acceptable because the type scale
is the most tolerant part: it is corrected later without touching the QStyle.

---

## 5. Warning about inventing the typography

There is a real risk in filling the typography gap "by eye" and presenting it as measured.

The base size **is** measured: `Sizes/Global/Font Size = 13`. But the line height, the
letter spacing and the sizes of the upper levels **are not**. If they are
invented and taken as good, the result is a theme that looks right in a screenshot
and is not in real use — and worse, nobody will know why.

**Rule for `tokens.toml`:** each token carries its provenance, and the unmeasured ones are
marked as `procedencia = "convencion"` instead of `"medido"` or `"export"`. It is the
same discipline that is already applied to colors, and it is what makes the file
auditable six months from now.

---

## 6. Recommendation

**Start now with what is measured**, which is quite a bit more than it seems:

```
STEP 2a · KDE color schemes (.colors), light and dark
          they come from tokens-colors.toml, which is complete and measured

STEP 2b · consolidated tokens.toml
          color (measured) + metrics (measured) + material (measured)
          + typography (only the 13 measured, the rest marked as convention)

STEP 3  · KWin material effect
          it has the 11 parameters; it is the biggest visual impact per line of code

PENDING · window radii and full typography
          they come in when there are screenshots, without blocking anything above
```

The key is that **nothing missing blocks what can already be done**. The gaps
affect the window shape and the text; color, control metrics and
material are complete.

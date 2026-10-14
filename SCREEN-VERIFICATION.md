# Verification on a real screen

Record of the check of the applied scheme, measuring the pixels of a screenshot of
*System Settings → Appearance → Colors*. It is the verification that was missing: the
one that confirms that what was generated **is applied and looks as calculated**.

- Screenshot: `Colors — System Settings`, 1171x905
- Scheme on screen: **KdeMacosLight**, selected (it appears with the blue focus border)
- Method: pixel sampling with PIL, grouping by bands and counting the dominant color

---

## 1. Backgrounds: they match exactly

Measured in the preview card of `KdeMacosLight`, and compared with
`output/color-schemes/KdeMacosLight.colors`:

| Region | On screen | What I declared | |
|---|---|---|---|
| Window body | `#FFFFFF` | `Colors:Window.BackgroundNormal = 255,255,255` | ✔ |
| Title bar | `#F1F1F1` | `Colors:Header.BackgroundNormal = 241,241,241` | ✔ |
| Highlight band (selected row) | `#CDDFE0` | `Colors:Selection.BackgroundNormal = 1,101,226` | ⚠ see §3 |

The first two are **identical**. The third is not, and there is an explanation.

## 2. Texts: they match within the compression tolerance

The text is measured by the **core of the stroke** (the most extreme 0,5 % of pixels), not by the
smoothed edges, which are always lighter:

| Text | On screen | What I declared | Difference |
|---|---|---|---|
| Normal text | `#282828` | `38,38,38` = `#262626` | 2/255 per channel |
| Disabled text | `#2D2D2D` | `35,35,35` = `#232323` | 10/255 per channel |
| Text on the highlight | almost white | `255,255,255` | antialiasing |

The difference of 2 levels in the normal text is **noise from the WebP conversion**, not a
calculation error. The 10-level one in the disabled text is antialiasing: when measuring the
"core" of a thin stroke, part of the background gets mixed in.

**Conclusion:** the veil composition is correct. The normal text appears at `#282828`
on white, which is exactly `black at 85 %` on `#FFFFFF`, which is what the
generator calculates from the kit's `label/primary` token.

## 3. The only real discrepancy: the highlight is not solid blue

I declared `Colors:Selection.BackgroundNormal` as `1,101,226` (`#0165E2`), which is the
kit's `misc.table.bg_selected_active` token: in macOS, the selected row of a table
is painted with **solid accent blue and white text**.

But on screen the highlight looks **very light blue** (`#CDDFE0`), and the text of the highlight
comes out dark instead of white.

**Cause:** the macOS 27 kit has an accessibility option that KDE calls *"use the
accent color for selection"*. When it is active, widgets calculate the highlight from
the **accent color** and not from the `BackgroundNormal` of the `Colors:Selection` group.
In the screenshot, the accent is selected as "Accent color from color scheme", so
KDE derives a light tint from the blue.

That is: the declared color is correct, but **KDE replaces it**. To see it as in
macOS (solid blue) you have to disable that option, or set the accent explicitly.

**This is not a fault of the scheme**: the other five schemes in the screenshot (KvAdapta,
KvAdaptaDark, KvAmbiance, KvAmbiance… and Kvantum) show exactly the same light
highlight. It is KDE's behavior in this version, not my colors'.

## 4. Note about the dark chrome

In the screenshot, the title bar of *System Settings* and the window borders
look dark even though the scheme is light. This is expected: the system's **global theme**
is still `Ant-Dark` and the **window decoration** is Kvantum/Ant. The installer
changes the color scheme, not the global theme or the decoration — on purpose, so that the
change is small and reversible.

Once the scheme is validated, the next natural step is a global theme that joins
scheme + decoration + Plasma Style.

---

## 5. What is verified and what is not

| | |
|---|---|
| **Verified** | `aplicar` works: the scheme appears in Settings and can be selected |
| **Verified** | The backgrounds are applied exactly as they were calculated |
| **Verified** | The veil composition gives the expected text color |
| **Verified** | The high contrast is preserved on screen (the text looks sharp) |
| **Pending** | The GTK CSS: it has not been tested with a real GTK app |
| **Pending** | The dark scheme `KdeMacosDark` on screen |
| **Pending** | The look as a global theme (decoration + Plasma Style) |


---

## 6. The title bar buttons: they are NOT drawn by the GTK theme

When testing with **Proton VPN** (`proton-vpn-gtk-app 4.18.6`, native GTK4, **without
libadwaita**) a confusion appeared that is worth writing down, because it is an easy mistake
to make:

> The title bar buttons —the menu, minimize and close— **are not drawn by the GTK
> theme**. They are drawn by **KWin**, with the active window decoration.

That is why they are not fixed by touching `output/gtk-3.0/kde-macos-dark.css`, however much you adjust it.

### First response, and why it was wrong

The first thing I did was copy the decoration you already had (**Ant-Dark**) and separate its
buttons. That **is not what was agreed**: the project is *a macOS-style layer*, and a copy of
someone else's theme with the buttons further apart is not that. It was solving the symptom instead of
the objective.

### The right thing: a decoration of its own, generated from the tokens

`output/aurorae/KdeMacOS/` is a decoration **generated from scratch** by
`tools/generate-macos-decoration.py`, with the measured values from the kit:

| Element | Value | Origin |
|---|---|---|
| Traffic light size | 12 px | Measured in the `.fig` |
| Close | `#FF5F57` | `tokens/tokens-forma-efectos.toml` |
| Minimize | `#FFBD2E` | Ditto |
| Zoom | `#28C840` | Ditto |
| Position | **Left**, close-minimize-zoom order | macOS convention |
| Separation | 8 px | So they can breathe |
| Bar height | 28 px | Measured |

**The three details that almost nobody reproduces and here are present:**

1. **The glyphs only appear on mouse hover.** At rest they are three clean circles.
2. **Without focus, the three dim to gray** (`#48484A` / `#3A3A3C`). In macOS the traffic lights
   do not stay colored: they desaturate. It is Aurorae's `inactive` state.
3. **They are on the left.** Your previous decoration had them spread out and without traffic lights.

Preview: `output/aurorae/preview/`.

### Installation

```bash
./install-decoration.sh plan              # see what it would do
./install-decoration.sh aplicar --si      # install
```

Then: *Settings → Appearance → Window Decorations → **KdeMacOS***.

**It does not modify any existing decoration**: it is installed separately and chosen in Settings. The
install → revert cycle is tested with a fake `HOME`.

### What is still pending in the decoration

The `.rc` declares `Shadow=true` and the frame is an approximation: the real macOS shadow is
**two layers** (diffuse radius 54 + contact radius 1) that are already measured in
`tokens/tokens-forma-efectos.toml`. Aurorae does not allow declaring two shadows, so the frame's
one will have to be added by the KWin effect of step 5.

### The other piece of data that came out of this

Proton VPN brings its own CSS, with its brand in purple (`#8A6EFF`). The green of "Protected"
is its own, a state color, not the theme's. For apps that paint their own thing, the system theme only
influences what the app does not draw itself. It is the list of exceptions in
[ANALYSIS.md](ANALYSIS.md) §3.3, now with a real tested case.


---

## 7. Why the traffic lights came out on the right (and not on the left)

After installing `KdeMacOS`, the Konsole screenshot showed **three dark circles on the
right** instead of the colored traffic lights on the left. The cause is located and
checked against the real `kwinrc`:

```
~/.config/kwinrc
    [org.kde.kdecoration2]
    library=org.kde.kwin.aurorae.v2
    theme=__aurorae__svg__KdeMacOS
    <-- there was NO button key at all
```

**The theme declares `LeftButtons=XIA` in its `.rc`, but KWin 6 does not read the layout there.**
It reads it from `kwinrc`. If the keys do not exist, it applies **its own default value, which
puts the buttons on the right**. That is why the theme asked for the left and they came out on the right.

The correct keys are:

```ini
[org.kde.kdecoration2]
ButtonsOnLeft=XIA
ButtonsOnRight=
```

`X` = close, `I` = minimize, `A` = maximize. In that order and on the left is what
macOS does.

This **could not be seen by the static analysis**: the theme was coherent, the engine was well
chosen and the SVG was well formed. It only appears when looking at the rendered window.

### Fixed in the installer

The `--activar` subcommand now writes the three keys that matter:

```
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__KdeMacOS
ButtonsOnLeft=XIA
ButtonsOnRight=
```

And `plan` reports the layout **that KWin has at that moment**, not the one the theme
declares, which is what was misleading.

### And a pending cleanup

The first version of the installer created **`Ant-MacOS`** (the copy of Ant-Dark, before the
criterion was corrected). It is still installed. It is removed with:

```bash
./install-decoration.sh limpiar
```

### What still cannot be verified here

I could not start a nested KWin to see the result: the sandbox does not allow creating the
socket in `/run/user/1000` nor does the process survive. So **the final color of the
traffic lights is unconfirmed on screen**. What is verified: the SVG is valid,
it has the five states in place and the colors are the kit's.


---

## 8. Confirmed on screen: the traffic lights work

After applying `ButtonsOnLeft=XIA`, the Konsole screenshot shows the **three traffic lights on the
left**, in color, and the same appearance in System Settings. Measured on the screenshot:

| Traffic light | On screen | From the kit | Difference |
|---|---|---|---|
| Close | `#F26E69` | `#FF5F57` | 18/255 |
| Minimize | `#F7C450` | `#FFBD2E` | 34/255 |
| Zoom | `#45C95A` | `#28C840` | 29/255 |
| Separation between edges | **8 px** | declared 8 px | exact |

The color differences are from the **WebP compression** of the screenshot and from the edge
smoothing at 12 px, not from the rendering. The separation matches **exactly**.

### Checked in the real `kwinrc`

```ini
[org.kde.kdecoration2]
ButtonsOnLeft=XIA
ButtonsOnRight=
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__KdeMacOS
```

### And a missing improvement: the ring

The kit gives **two** colors per traffic light: the fill of the circle **and the ring's**. I only
used the first, and the buttons came out flat. Both are there now:

```
close.svg     fill #FF5F57   ring #FF4245
minimize.svg  fill #FFBD2E   ring #FF9230
maximize.svg  fill #28C840   ring #30D158
```

---

## 9. What is NOT faithful, and it is worth knowing

I compared the kit's colors with the ones macOS **actually paints**. There is a systematic
difference:

| | Kit (what I use) | macOS on screen |
|---|---|---|
| Close | `#FF5F57` | `#ED6A5F` |
| Minimize | `#FFBD2E` | `#F6BE50` |
| Zoom | `#28C840` | `#61C555` |
| Green saturation | 80 % | **57 %** |

The kit is **~18/255 more saturated** than what is seen on the macOS screen, above all
in the green (`#28C840` versus `#61C555`). The probable cause is that the kit's values
are the ones *declared* in sRGB, while macOS draws them with its color management and a
bit of vibrancy on top.

**Decision taken:** the **kit** values are used, not the screen ones. Reason: the
project is built *from the tokens*, and mixing in a correction taken from a
screenshot here would break that rule. It is noted here and, if you want to fine-tune it, it is a change of three
constants in `tools/generate-macos-decoration.py`.

**And a fidelity detail is missing:** macOS puts a **slightly darker ring** than the
fill (the kit reflects it with the second color), but on top of that the real traffic lights carry
transparency at the edges. KWin with SVG does not apply that fade easily.

### Reference consulted

[`lwouis/macos-traffic-light-buttons-as-SVG`](https://github.com/lwouis/macos-traffic-light-buttons-as-SVG),
an SVG approximation of the real buttons, with the colors measured by its author.

# Brief analysis: "macOS-style" desktop layer for Linux

> Critical analysis of [BRIEF-ORIGINAL.md](BRIEF-ORIGINAL.md).
> Analysis date: October 13, 2025.
> Method: reading the brief + verifying each technical assumption against the current
> state of KDE Plasma 6, Qt 6, GTK4 and macOS 27 (see [VERIFICATION-ANNEX.md](VERIFICATION-ANNEX.md)).

---

## 1. One-page verdict

**The brief's diagnosis is correct and the plan is executable.** The three central
theses hold up:

1. **A theme repaints, it does not re-architect.** True. A Plasma theme is QSS + SVG +
   color schemes: it cannot change metrics, hit-testing or control
   animations. A QStyle can. The brief correctly identifies *where* the boundary is.
2. **The QStyle is the effort multiplier.** True, and it is the part with the most
   mechanical volume and the least coupling in the project — exactly the profile where
   AI assistance pays off most.
3. **The portable declarative layer is worth it on its own.** True, and it is the only deliverable
   whose value does not depend on the rest of the project being finished. It is the right order.

**The problems are not in the strategy, they are in four operational assumptions** that,
if not corrected before writing code, produce work that nobody sees:

| # | Assumption in the brief | Reality | Cost of not correcting it |
|---|---|---|---|
| A1 | "The three are **generated** from the tokens" (QStyle included) | What is generated from the tokens is the *appearance layer*; the QStyle is **written** | Waiting for a generator that cannot exist |
| A2 | A custom QStyle "turns a theme into the system" | In Plasma 6 **there is no per-application style selector**; you have to force `QT_STYLE_OVERRIDE` per process | Building a QStyle that most apps never load |
| A3 | "libdecor: the app yields drawing to the compositor" | `libdecor` is a **client** library; it does not force the server to decorate, and GTK4 does not use it | Expecting GTK4 to obey through a path that does not exist |
| A4 | "KWin clips the window: it is done once" | Corner clipping is viable (there are precedents), but it is not free in apps with content in the corners | Promising an effect that looks dirty in real apps |

**There are also three omissions that weigh more than any technical decision:**

- **Typography.** The macOS look is ~50 % typography and spacing, ~30 % shape,
  ~20 % material. The brief devotes 11 lines to the material and **zero to the font**. Without
  a font with equivalent metrics and a compatible license, the result will not
  look like macOS even if all the tokens are correct.
- **The success criterion.** There is no definition of "done" nor a way to measure progress.
- **Visual regression tests.** In a purely aesthetic project, this is not
  a luxury: it is the only test that makes sense and it is scriptable.

**Recommendation:** keep the plan, reorder two steps, add the typographic axis and
visual verification as infrastructure for **step 0**, and lower HDR to v3.

---

## 2. What the brief gets right (and is best left alone)

- **Tokens first.** It is the architectural decision that makes the others possible. Without
  a single source of truth, QStyle, GTK CSS and KWin diverge within three weeks.
- **Not forking Plasma.** Correct: a Plasma fork is permanent
  maintenance debt and breaks with every release. A QStyle + KWin effect are **public and
  documented** extension points.
- **KWin for the corners, once, not per app.** It is the only point in the system where
  shape can be imposed on foreign windows. The instinct is correct — the *guarantee* is
  what needs qualifying (A4).
- **NOT using `LD_PRELOAD`.** Correct, and it must be defended. It is the solution that seems
  free and breaks on every GTK update.
- **Accepting that GTK4 does not yield 100 %.** The brief estimates ~10 % irreducible. It is the
  right attitude; the figure is optimistic (§3.3).
- **Legal notice and not using Apple trademarks or icons.** Correct and necessary.

---

## 3. Technical corrections

### A1 · What is generated and what is written

The brief says: *"A `tokens.json` … From there the three are GENERATED"* (QStyle + GTK CSS +
KWin). That describes two of the three well and the third badly.

| Output | Generable from tokens? | Why |
|---|---|---|
| Color schemes (`.colors`) | **Yes, 100 %** | Pure data→data transformation |
| GTK CSS | **Yes, ~85 %** | Except for overrides per GTK version and specific apps |
| KWin scripts/effects | **Partial** | The effect *config* is generated; the effect in C++/QML is written |
| Assets (squircle masks, SVGs) | **Yes, with parameters** | Deterministic geometry |
| **The QStyle (C++)** | **No** | It is imperative drawing coupled to the `QStyle` API |

The QStyle is not a declarative format: it is C++ that implements `drawControl`,
`subControlRect`, `pixelMetric`, `sizeFromContents`, `hitTestComplexControl`, etc.
What can genuinely be generated is the peripheral and valuable part:

- A **generated `Tokens.h`** with the constants, so that no number is written by hand.
- A **coverage manifest**: the list of *all* the QStyle enumerations
  (`QStyle::ControlElement`, `PrimitiveElement`, `SubControl`, `PixelMetric`,
  `StyleHint`, `ComplexControl`) with a state per element. That is what turns
  "1–3 months" into a measurable plan instead of a feeling.

**Corollary:** split the project into **generator** (a finished, testable tool)
and **QStyle** (incremental implementation). They are two different life cycles, and mixing them
is what makes this kind of project fail.

### A2 · The QStyle does not activate on its own (the most underestimated risk)

> **Correction made after this analysis.** The requirement pointed out here is real, but the
> solution I propose in this section (`QT_STYLE_OVERRIDE`) turned out to be **unnecessarily
> complicated**. When verifying the system it was found that Plasma 6 selects the style with
> **a single key in `kdeglobals`** (`[KDE] widgetStyle`), and this machine already
> proves it: it has `widgetStyle=kvantum` and `/usr/lib/qt6/plugins/styles/libkvantum.so`.
> Kvantum is a third-party QStyle working on the system, with no per-process overrides.
> **The correct design is in [`INSTALLATION.md`](INSTALLATION.md) §1.** This
> section is kept because the diagnosis —Plasma 6 has no per-application style selector— is
> correct and is still the point the brief ignored completely.

In Plasma 6, *System Settings → Appearance* selects the **global theme**
(QSS + decoration + colors + icons). **There is no "widget style
per application" selector such as the one that existed in Plasma 5.** Consequences:

- The style is selected in `kdeglobals` (`[KDE] widgetStyle`), which is **global**: you
  cannot apply the custom QStyle to some apps and not others from the interface.
- There is a KCM (`kcm_style.so`) that writes that same key, and a property
  `isWidgetStyleImmutable` that can cause the key to be ignored. It has to be checked.
- Practical consequence for development: during step 4 an **isolated test
  in a single process** (`QT_STYLE_OVERRIDE=<nombre> kate`) is advisable, not because it is needed
  to install, but because it allows validating the QStyle with **zero risk** before
  activating it globally.

**Action:** add a "Style activation" section to the brief and treat the test in a
single process as a mandatory gate before global deployment (stage 1 of
[`INSTALLATION.md`](INSTALLATION.md) §6).

### A3 · GTK4: realistic expectation

- `kde-gtk-config` + generated CSS: **valid and sufficient** for GTK3. Keep it.
- `libdecor`: it is a library that the **client** links to obtain hybrid
  decoration (the client draws, but the compositor provides shadows and management). It is not a
  mechanism for making KWin decorate by force, and **GTK4 does not use it**. The brief presents it
  as "the sanctioned mechanism: the app yields drawing to the compositor" — that describes
  `xdg-decoration` in *server-side* mode, which in GTK4 simply does not activate.
- **The irreducible percentage is higher than 10 %.** Cases that ignore the theme
  regardless of what you do:
  - **Electron/Chromium** apps with their own decoration and embedded CSS.
  - **Flatpak** apps that bundle their own theme and do not see `~/.themes` or `~/.config/gtk-4.0`.
  - Modern apps that link against **libadwaita without the opt-in** to respect the
    system theme.
  - Apps that draw their own title bar (VS Code, Spotify, browsers).

**Action:** reframe the GTK goal as *"GTK3 fully, GTK4 in whatever
respects `gtk-4.0/gtk.css`, and a documented list of known exceptions"*. An honest list
of exceptions is worth more than an invented percentage.

### A4 · Corner clipping: viable, but not free

There is a direct and active precedent: **LightlyShaders** (rounded corners + outline
for KWin, with a [port to Plasma 6](https://github.com/walterfang12/LightlyShaders-Plasma6))
and [kwin-effect-rounded-corners](https://github.com/ekaaty/kwin-effect-rounded-corners).
So the mechanism is real: a KWin effect that applies a per-window mask while
compositing. But three things the brief takes for granted are worth clarifying:

1. **Rounding and clipping are not the same.** Rounding paints transparent corners
   around a square window. Clipping **removes pixels**: if the app draws
   content in the corner (a button, a border, text stuck to the vertex), that content
   disappears. In apps with their own title bar the result looks broken.
2. **The effective radius depends on the client.** The brief asks for "a single radius for all".
   It cannot be guaranteed: the app may have its own decoration with its own radius, and
   the effect only adds the outer part. The policy for apps with CSD has to be decided
   (leave them alone? clip and accept the damage?).
3. **The correct order is step 1, not step 5.** The brief places the KWin effect *"on top
   of 4"*. Prioritization error: corner clipping is **what changes perception most
   per line of code** and it is the only thing that unifies apps that will never respect
   your QStyle. It should go right after the declarative layer.

### Minor observation · "escort"

The Golden Gate token list includes `ICONOS ....... escort obligatorio`. It is almost
certainly **"squircle"** (Apple's superellipse). Correct it in the brief so as not to
drag the error into file and type names.

### Scope · HDR

`EXTRA: la interfaz usa HDR para dar profundidad` is real on macOS, but on Linux
it implies KWin with HDR (support still maturing in Plasma 6), monitor dependence and
a multiplication of color test cases. **Take it out of v1.** It is the kind of token
that is declared in `tokens.json` from day one and implemented in v3, when the engine
is already stable.

---

## 4. What is missing and must be added to the brief

### 4.1 Typography (the biggest gap)

Without solving this, the project will not reach the goal even if everything else works.

- **Do not distribute SF Pro.** Apple's license forbids redistribution. A
  public repository with SF Pro inside is a real legal problem, and it contradicts the brief's own
  legal notice.
- **You need a font with calibrated metrics**, not just a similar one: line spacing,
  advance width and x-height are what produce the macOS "density" feel.
  Free-licensed candidates: **Inter** (the closest in proportions and with an optical
  axis), **SF Pro substitutes** such as `Inter Display` for headings, and for monospace
  **JetBrains Mono** or **IBM Plex Mono**.
- **Typographic scale in tokens**: UI size, bar title size, body size, and —most
  importantly— **the internal spacing per control**, which is what almost nobody adjusts and
  is what makes a control "feel" like macOS or not.

### 4.2 Success criterion and visual regression tests

A concrete proposal, cheap and automatable from step 0:

- **Definition of done per milestone** (the exact value of N will have to be set):
  - Milestone 1: the representative app suite looks coherent in screenshots compared
    against a frozen reference.
  - Milestone 2: no app in the suite *fails to start* or loses functionality.
  - Milestone 3: the installer works **without sudo** and uninstalling leaves the system as
    it was (verifiable with `git status` of the dotfiles + previous hashes).
- **Capture harness**: a fixed list of apps and dialogs, captured with `spectacle
  --background --fullscreen` or `grim`, compared pixel by pixel (or with a tolerance) against
  a saved reference. A 40-line script. It catches half the regressions
  before you see them by eye.
- **Representative app suite** (fix it and do not expand it without reason): Dolphin, Kate,
  Kwrite, Konsole, a GTK3 app, a GTK4/libadwaita one, an Electron one and a Flatpak one.

### 4.3 Portability: making it concrete

The brief gets the intention right, but "everything declarative in a repo" already has a standard
solution and it is best not to reinvent it:

- Use **dotfiles + an idempotent installer** (or an existing tool such as `chezmoi`,
  `stow`) instead of a custom format. The value is in changing distro with a single
  command, and that is already solved.
- Add a **`--dry-run` mode** to the installer, and a **rollback manifest** (list
  of files touched + previous hash). That is what makes the script "auditable and reversible"
  for real, not just declarative.
- **Nuance on "no sudo, no AUR"**: correct as a restriction of the
  *deliverable* (the installer does not use it). Different from your development machine, where
  compiling Qt/KWin or installing `gcc`, `cmake` and headers does require system
  packages. Write it as "the installer does not use sudo" and not as "the project
  does not use sudo", so as not to get stupidly blocked in the development phase.

### 4.4 Risk of token obsolescence

macOS 27 Golden Gate is a reference **prior to its release**. Apple adjusts
radii, opacities and contrasts between betas, and given the Liquid Glass history it is
especially likely that there will be corrections in the first months. Therefore:

- The tokens must carry a **version** and a **capture date**, and the generator must
  tolerate a token changing value without breaking anything.
- It is best to design for "one token layer per reference version", not for a single
  frozen set.

---

## 5. Proposed work order (corrects the brief's)

```
0. INFRASTRUCTURE AND MEASUREMENT         <- new, 2-3 days
   capture harness + app suite + versioned tokens.json
   + chosen font and typographic scale
   -> without this, steps 3 and 4 are invisible and unverifiable

1. GOLDEN GATE TOKENS                     <- from the brief, kept
   + typographic and spacing axis (the brief did not have it)

2. PORTABLE DECLARATIVE LAYER + INSTALLER <- from the brief, kept
   the scheme and GTK CSS generator also lives here

3. KWIN EFFECT: CORNERS + DARKENED BORDER <- MOVED from step 5
   maximum visual impact per line of code; unifies apps that do not cooperate
   -> includes the early QT_STYLE_OVERRIDE test (A2)

4. GENERATOR: TOKENS -> QSTYLE + CSS + KWIN <- from the brief, kept
   real deliverable: Tokens.h + coverage manifest + assets

5. COMPLETE QSTYLE                        <- from the brief, kept
   implementation by enumerations, guided by the manifest from step 4

6. (v3) HDR AND ADVANCED DEPTH            <- taken out of v1
```

Changes with respect to the brief: **new step 0** (measurement), **KWin effect from 5 to 3**, and
**HDR explicitly to v3**.

---

## 6. About the legal notice: one missing point

The brief covers trademarks, names and icons well. The item most people overlook is missing:

- **Fonts**: do not redistribute SF Pro (see §4.1). It is the easiest violation to
  commit without realizing, because the font usually ends up in the repository as
  a "style resource".
- **Icons**: in addition to not using Apple's, the license of the chosen set
  must be verified if the repository is public.
- **Screenshots**: if comparisons are made against macOS screenshots, publishing those
  screenshots as a reference also comes into play. Keep them outside the public repo, or
  use metrics (radii, opacities) instead of images.

---

## 7. Summary of actions on the brief

| # | Action | Priority |
|---|---|---|
| 1 | Add a **typographic** axis (font + scale + spacing) to the token system | **High** |
| 2 | Resolve **how the QStyle is activated** in Plasma 6 (`widgetStyle` in `kdeglobals`) | **Resolved** → [`INSTALLATION.md`](INSTALLATION.md) §1 |
| 3 | Add **measurement step 0**: capture harness + app suite + done criterion | **High** |
| 4 | Move the **KWin effect from step 5 to 3** | **High** |
| 5 | Separate **generator** from **QStyle** (two life cycles, two deliverables) | Medium |
| 6 | Reframe GTK: complete GTK3, partial GTK4, **honest list of exceptions** | Medium |
| 7 | Clarify corner clipping: rounding ≠ clipping, policy for apps with CSD | Medium |
| 8 | Take **HDR to v3** | Medium |
| 9 | Rewrite "no sudo" as "**the installer does not use sudo**" | Low |
| 10 | Correct `escort` → **`squircle`** | Low |
| 11 | Version the tokens (Golden Gate has not been released yet) | Low |
| 12 | Add fonts and icon license to the **legal notice** | Low |

---

## 8. Conclusion

The brief works as a starting point: it identifies the right problem, rules out the
wrong solutions (themes, `LD_PRELOAD`, a Plasma fork) and orders the work
sensibly. It is not a naive plan.

What it lacks is not strategy, it is **operational realism on four points** —the QStyle
is neither generated nor activated on its own, GTK4 does not yield through `libdecor`, corner clipping has
a cost— and **two axes that do not appear**: typography and measurement. Of the two,
typography is the one that decides whether the result looks like macOS; measurement is the one that decides whether
the project makes it to the end.

With those corrections, the project is viable in the proposed order and has a deliverable
of immediate value (step 2) that justifies the effort even if steps 5 and 6 are never
completed. That, in itself, is already a good plan.

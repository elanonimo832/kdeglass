# NEXT.md — start here

One page for whoever opens this repository cold, human or agent. It says where the work is, what to do
next and in which order, and the three mistakes this project has paid for often enough to be rules.

**Starting a new session? Paste [`docs/PROMPT.md`](PROMPT.md) into it.** That prompt fixes the
working directory, forbids creating any other folder, and lists what to read and verify first.

## What this is

A KWin 6 effect (`effect-kwin/`, C++/Qt6/GLSL) that draws Apple's "liquid glass" title bar over every
window, plus the Python tools used to measure it against Apple's own samples and against the user's
kit in `tokens/`. The effect is **finished and approved on screen**, and the work left is performance
and the wider desktop shell.

## Where it is right now

| | |
|---|---|
| installed plugin | `md5sum /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so` |
| this tree's build | `md5sum effect-kwin/build/plugins/kwin/effects/macosglass2.so` |
| suite | `bash tests/run.sh`, about 5 seconds (the doc names the harness, never its size) |

If those two hashes differ, an install is pending: `cd effect-kwin && ./install.sh` and then a relogin,
**or** try the hot path first — `unloadEffect` + `loadEffect` over D-Bus has picked up a new library
without a relogin twice (see the runbook below).

The defaults in `src/glass.h` are the user's own choices, each with its measurement beside it:
`CornerRadius` 20, `Refraction` 20, `Rim` 0.30, `RimColour` 1.8, `Specular` 0.7 at `SpecularWidth` 6,
`MaterialGain` 1.6, `GlassAlpha` 0.25, `BackgroundRadius` 16, `CaptureSubRect` true.

## What to do next, in order

1. **M2 — squircle corners: the CLOTHOID is implemented, and it wants a screen.** Read `HANDOFF.md`
   §10c first. `CornerSmoothing` (default 0, range 0..1, in `tune.sh`, the README table, the suite and
   the shader) selects it. Two wrong curves are behind it: the superellipse with the invented
   calibration (a nearly square corner), then the Figma G1 construction, whose curvature SPIKED +46.9%
   over the arc -- measured by `effect-kwin/measure-corner.py --curvature`, which turns curvature
   continuity into a check. It is now the EULER SPIRAL (clothoid), the only G2 candidate the
   instrument accepted: +0.0% overshoot, 0 maxima above the arc, in `simulate.py` AND the shader,
   searched in segments. NOTE: at `0.6` the corner is ~1 px FULLER than the circle (its arc centre
   sits at 20.78, not 20), the arc measure is still `90*(1-s)`, and a HIGH `s` makes the corner look
   SMALLER because the curvature is spread over a longer transition -- `CornerRadius` is the knob that
   makes a corner dominate. NEXT: install the new `.so`, set `CornerSmoothing=0.6` and LOOK.
2. **The bend follows all four edges of the band — DONE, and it wants the same screen.** The user: "en
   el fondo de la barra se ven lineas verticales, no curvea nada de ese fondo". The band's bottom is
   the top of the CONTENT and not a frame edge, so the frame's distance is flat there and the bend
   along the bottom was exactly zero; the simulator always bent, so the two disagreed and the shader
   was the wrong one. `bandEdge` is that edge now and the direction BLENDS the edges by proximity
   instead of taking a `min` (a min seams wherever two edges are equally far). The reach is its own
   knob, `RefractionReach`, default 16 px, MEASURED as the largest reach whose falloff is exactly
   zero at the middle of a 38 px band. Parity measured: `effect-kwin/measure-refraction.py`
   transcribes the shader and compares it with the simulator -- **0.000 px** at all four edges, the
   bottom's direction vertical. NEXT: install + relogin, then look at a window over an app with
   vertical lines.
3. **Audit finding 1 — DONE (2026-10-15), and verified on screen.** The capture is the BAND now: the
   journal reads `capture texture QSize(466, 42)` where it read `QSize(466, 381)` (Konsole `933x762 ->
   933x84`, ~9x; a maximised window ~17x), and `test-glass.sh` still returns GLASS (146.2 against 12).
   The shader needed no change: `uBackgroundOffset + vTexCoord*uBackgroundScale` already maps the frame
   into any sub-rectangle. `CaptureSubRect` is now the EXTENT switch (band / whole window, the escape
   hatch). The hot reload did NOT pick the library up and a relogin did; the tell is the
   `capture texture` size.
4. **Audit findings 4, 7 and 8 — DONE (2026-10-15).** #7 removed the dead code (`deviation`/
   `byDeviation`, `kFrostOpacity`, `m_active`, a duplicated `kLuma` and one re-fetch) and the two
   assertions that were keeping the retired expression alive. #8 resolves the uniform locations once
   (`GLShader::uniformLocation` + `setUniform(int, ...)`) instead of 24 name lookups per paint. #4
   keys the capture cache by **(window, size)** with the bound raised 4 to 8 -- cheap now that audit 1
   shrank a slot from up to 8 MiB to ~0.5 MiB -- and drops a window's entries when it closes. The
   build is ahead of the installed `.so`; the changes are behaviour-identical, so only a performance
   gain is waiting on an install + relogin.
5. **Audit finding 6 — DONE (2026-10-15).** `tests/lib.sh` grew `afirmar_glsl`, which strips comments
   (as `afirmar_codigo` does), removes ALL whitespace from both sides and matches the pattern as a
   CONTIGUOUS literal, so a reformat passes, an operator change fails, reordered tokens fail and a
   pattern that lives only in a comment fails -- all four proven in `test-harness.sh`. 95 shader
   assertions were converted, 19 of them from a NAME to the EXPRESSION that decides.
6. **M3 — the Plasma global theme: BUILT, and it wants the user's session.** `output/look-and-feel/
   KdeMacOS/` (the LookAndFeel: `metadata.json` + `contents/defaults`) and `output/desktoptheme/
   KdeMacOS/` (the PlasmaStyle: `metadata.json` + `colors` + `plasmarc`) are generated by
   `tools/generate-global-theme.py`, installed by `install.sh` and pinned by
   `tests/test-global-theme.sh`. `defaults` links the colour scheme, the PlasmaStyle, the Aurorae
   decoration and the `macosglass2` effect, and points at KDE's own defaults for the parts M5/M6
   will ship, because naming a component the user does not have is how a global theme breaks a
   desktop. Two bugs came out of it, both in `HANDOFF.md` §9z: `install.sh` looked for the themes
   in `salida/`, a directory that does not exist (`plan` printed "source does not exist" for ALL
   six entries, so it installed NOTHING and said nothing), and the colour schemes' reproducibility
   check called its generator with no arguments, so it never regenerated and could not fail. TO
   APPLY, and this is the user's step -- not verified on screen:
   ```
   ./install.sh aplicar --si
   plasma-apply-lookandfeel -a KdeMacOS     # or System Settings > Global Theme > KdeMacOS
   ./install.sh rollback                    # to undo
   ```
   MEASURED LATER, and it was a real miss (`HANDOFF.md` §10e): that tool does NOT carry the
   theme's SEVEN font keys and `macosglass2Enabled` -- the effect switch -- anywhere, so a theme
   that promised a type scale and an effect applied neither. `install.sh aplicar` now READS the
   generated `defaults` and writes the missing keys itself with `kwriteconfig6`, so the installer
   is the one that applies them and a relogin is what makes Plasma re-read the fonts.
   NEXT was M4 typography -- DONE, and it is point 7.
7. **M4 -- the macOS type scale: BUILT, and it wants the user's session.**
   `tools/generate-global-theme.py` writes the font keys into the SAME `contents/defaults` M3 ships
   (there is no second package) and READS the sizes and weights from the tokens instead of
   restating them. Three facts were MEASURED with a Qt 6.12 probe before any of it was written, and
   `HANDOFF.md` §10d has the numbers: **the size goes in the POINTS field**, derived from the pixel
   token at the measured 96 DPI (13 px -> 9.75 pt) -- see the AMENDMENT in §10d-bis, because the
   first attempt wrote it in the pixel field and real applications printed
   "QFont::setPointSize: Point size <= 0 (-1)": `QFont` holds points OR pixels, so a pixel size
   answers `pointSize()` with -1. It is NOT the QStyle -- measured with Breeze too -- and
   `tools/font-probe.cpp` now proves both halves (Qt reads a size > 0, and the metrics still equal
   the pixel form's, so the render did not move). **The weight must be the LEGACY 0..99 code**
   (`fromString` reads 400 as 900 = Black), and **the tracking has NO destination in kdeglobals** --
   64 of the 80 tokens, which is why applying it belongs to M6. Pinned by
   `tests/test-typography.sh`, which forbids a modern weight by name. Evidence:
   `evidence/2026-10-15-m4-text-scale.png`, generated by `tools/render-type-comparison.py`, which
   PRINTS the measured advance widths (335 -> 272 px, ratio 0.812 = 13/16). Both rows render with
   Noto Sans because **Inter is NOT installed** on this machine: `sudo pacman -S inter-font` and
   re-run the script to see the real typeface. TO APPLY, the user's step and not verified on screen:
   ```
   ./install.sh aplicar --si
   plasma-apply-lookandfeel -a KdeMacOS
   ```
   NEXT: M5 icons, then M6 QStyle -- which is also where the tracking lands.

8. **M5 -- the icon squircle: MEASURED, and one half of it is NOT verifiable.** `tokens/tokens-icon-
   geometry.toml` carries the figure: **R/S = 0.215 +- 0.01**, measured from the user's OWN macOS
   screenshots -- twelve valid Launchpad icons in `muestras/Untitled3.png` and `muestras/Untitled2.png`
   (medians 0.2161 +- 0.0026 and 0.2135 +- 0.0067) -- with `tools/measure-icon-geometry.py`, whose
   `--self-test` draws a corner of a KNOWN radius and reads it back (0.00 px error at R = 14, 20 and
   26) BEFORE it is allowed to report anything from a photo. Evidence:
   `evidence/2026-10-15-m5-icon-corner.png`, our own drawing of the profile, never a crop of Apple's
   pixels. **Two things are NOT verifiable and the token declares both**: no FOLDER icon appears in
   any of the nine captures (only app icons, which sit on the same Apple icon geometry, but the
   folder's own body was not checked against anything), and the corner FAMILY cannot be resolved at
   the 96 px an icon is drawn at -- the kit's own `smoothing = 0.6` corner and a plain circle differ
   by less than the sub-pixel top row (fitting a circle to the kit's corner leaves 0.29 px), so a
   smoothing reported from these captures would be noise. Also measured, and it corrects the
   ROADMAP: **the kit has NO iOS icon radius** to compare against -- `Global/Radius`, `Button/Radius`,
   `Checkboxes/Radius`, `Disclosure/Radius` and `Stepper/Radius` are CONTROL radii, and
   `[squircle] smoothing = 0.6` is a construction parameter, not a radius. `HANDOFF.md` §10f has the
   four measurement mistakes that cost this section its first two attempts.
   NEXT: M6 QStyle. The folder question wants a capture of a Finder window with large icons.

9. **M6 — the QStyle: the FIRST SLICE is built, and it wants the user's session.** This is the
   biggest step of the brief (the ROADMAP says one to three months) and the only milestone NOT on top
   of anything already done, so the first slice deliberately ships a **skeleton**: a Qt style plugin
   whose key is `KdeMacOS`, a `QProxyStyle` that chains to the base style, and **no primitive
   overridden at all**. That absence IS the feature -- M6's done criterion asks for a style that is
   "selectable **without breaking applications**", and the only way to be sure of that before the
   primitives exist is for selecting it to change nothing. The plan, the seven measurements that
   decided its shape and the slices that follow are in
   [`M6-QSTYLE-PLAN.md`](M6-QSTYLE-PLAN.md); what it cost is in `HANDOFF.md` §10g. Proven two ways:
   `tests/test-style.sh` builds the plugin, validates its metadata and runs a real Qt application
   under the **offscreen** platform, and that probe renders the same widget under the base style and
   under ours and compares the images pixel by pixel -- **`DIFF: 0`**. The first version of that
   probe counted non-white pixels and would have called a style that painted NOTHING a pass. TO TRY
   IT (no install, no relogin, ONE application, nothing on disk changes):
   ```
   QT_PLUGIN_PATH="$PWD/style-kde-macos/build" QT_STYLE_OVERRIDE=KdeMacOS dolphin
   ```
   and what you should see is **exactly the same window as before**, because the skeleton draws
   nothing of its own. To install it for the session, and to go back:
   ```
   ./install.sh aplicar --si
   # then LOG OUT and back in -- the environment file is read at login
   kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle KdeMacOS   # select (your step)
   ./install.sh rollback                                                    # undo
   ```

10. **M6 — slice 1: THE PRIMITIVE INSTRUMENT is built, and it says which control to redraw first.**
    The plan's rule is that a primitive is only changed with its measurement in front, and this IS
    the measurement: a gallery of nineteen controls rendered under the base style and under ours,
    with the pixel difference **per widget** and the metrics Qt answers for each one. Today
    everything is **zero** -- `19 primitives - pixel differences: 0 - metric differences: 0` -- and
    that zero is the starting line slice 2 has to move, in pixels, on purpose.
    `style-kde-macos/tests/primitive-gallery.cpp` draws it and `tests/test-style-gallery.sh` runs it
    under the offscreen platform; the evidence is `evidence/2026-10-15-m6-gallery.png` (OUR drawing:
    the base panel beside ours) and the "before" table every following slice diffs against is
    `evidence/2026-10-15-m6-baseline-metrics.txt`. What it cost is in `HANDOFF.md` §10i.
    - **Nine controls have NO macOS reference in the kit** (`scrollbar`, `tabbar`, `menubar`,
      `progressbar`, `listview-selected`, `tableheader`, and the focus ring): the Sizes collection
      does not define them. They are DECLARED, in the test, so that a slice cannot quietly redraw one
      of them from taste.
    - **The first primitive to redraw is the PUSH BUTTON**, and the table is the reason: the largest
      measured gap against a reference that EXISTS (its height is 34 px where the kit's `global`
      height is 24 -- 42% too tall), the most visible control on the desktop, and its reference
      (radius 6, padding 16) is already in `tokens/tokens-sizes.toml`. Its risk is that a button's
      size hint is every dialog's layout -- which is why it gets measured before it is changed.

11. **M6 — slice 2: THE PUSH BUTTON is redrawn, and it is the first control that has moved.** It
    answers `104x24` where the base answered `84x34`. The height is the kit's
    `[global] height.medium = 24` (`tokens/tokens-sizes.toml:88` -- 42% less than the base), the width
    is the content plus twice `[button] padding_horizontal.medium = 16` (`:24`), and the corner is
    `[button] radius.medium = 6` (`:27`). The other **sixteen** primitives still differ by exactly
    zero pixels, and `tests/test-style-gallery.sh` asserts BOTH halves -- including the new height,
    read from the token file rather than from a number written into the test.
    - **The corner is a plain arc, and that is a measurement**: at 6 px the clothoid and the arc
      differ by less than the antialiasing (`HANDOFF.md` §10j has the 0.29 px figure), so the plan's
      open question is closed rather than deferred.
    - **To see it, in ONE application and without installing anything**:
      `QT_PLUGIN_PATH="$PWD/style-kde-macos/build" QT_STYLE_OVERRIDE=KdeMacOS dolphin`.
    - **NOT verified: a real session.** A button that is 24 px tall inside EVERY dialog is a layout
      change that only a session shows, and `sizeHint` is the layout of every dialog.

`docs/HANDOFF.md` §9v has every audit finding with `file:line` and effort, and the list of things NOT
to touch **with the measurement behind each one**. Read it before changing anything in the shader.

## The toolbox, and how to iterate without a relogin

    bash tests/run.sh                 # the whole safety net, a few seconds
    ./build.sh                        # refuses to install if verify-chain.sh fails
    ./install.sh                      # needs the password; then a relogin, or the hot path below
    ./tune.sh --show                  # what is set; ./tune.sh Key=Value applies in ONE call, live
    ./tune.sh --reset                 # back to the defaults above (safe: they are the user's taste)
    python3 simulate.py --self-test   # the model of the shader, checked against two known cases
    python3 measure-corner.py --self-test  # the SHAPE of a corner, against five known synthetic cases
    ./capture-pair.sh                 # the two screenshots simulate.py needs, in one command
    ./snapshot.sh                     # a photo of the FIXED scene + commit + INSTALLED md5 + values
    ./snapshot.sh --self-test         # its refusal and its naming, with no screen
    python3 measure-capture-map.py --self-test   # the capture's sub-rectangle mapping, known geometry
    python3 render-type-comparison.py            # M4's rendered scale comparison + the measured widths

`simulate.py` implements the band's arithmetic in numpy so a look can be judged WITHOUT a relogin, with
every knob as an option and the defaults read from `src/glass.h`. Use it before proposing a value.

**Emergency runbook** (the effect once took the user's windows away): §9u of `HANDOFF.md`. In short,
from any shell: `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass2`, then
`kwriteconfig6 --file kwinrc --group Plugins --key macosglass2Enabled false` and `/KWin reconfigure`.

## Three rules this repository learned the hard way

1. **Verify the file, not the patch.** Five times in one session a multi-part edit applied in part --
   the header without the shader, the body without the signature, the plumbing without the log, a fix
   that silently did not apply -- and every one was caught by grepping the file afterwards, never by
   the patch reporting success. Write, then look.
2. **A test backdrop has to be able to SHOW the variable.** A uniform backdrop cannot show refraction, a
   grey one cannot show dispersion (every channel samples the same greys), one without stripes cannot
   show moire, and a metric can flatter itself: `|R-B|` on a coloured backdrop measures the backdrop.
   Three tests in a row measured something true about a question nobody asked.
3. **Never report green without having seen it.** Twice a commit message said "suite green" while the
   run in that same call had failed. Chain it: `bash tests/run.sh && git commit ...`.

Two more, from the same day: the shader and `simulate.py` are two implementations of one formula and
**they must be changed together** (they drifted four times, and their numbers never contradicted each
other while they measured different shapes); and **do not trade the look for speed without measuring** --
the 36-tap frost kernel is slow on purpose, because four equal levels only killed 82.5% of the text
behind the bar and the radius alone did nothing.

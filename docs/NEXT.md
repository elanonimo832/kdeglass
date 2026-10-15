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
6. **Then the shell**: M3 Plasma theme, M4 typography, M5 icons, M6 QStyle. See `ROADMAP.md`.

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

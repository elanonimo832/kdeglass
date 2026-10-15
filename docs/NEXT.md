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

1. **M2 — squircle corners, and it is HALF DONE the wrong way.** Read `HANDOFF.md` §10c before
   touching it. The door exists and works: `CornerSmoothing` (default 0, range 0..1, in `tune.sh`,
   the README table, the suite and the shader), a known-value test, and a simulator that draws it with
   bit-for-bit parity against the arc at 0. **What is behind the door is the wrong curve:** I built a
   superellipse with an invented calibration, and the user's screenshot showed a nearly square corner
   (at y=5 the circle's boundary is at x=6.8, mine at 20.0). Apple's construction -- an arc shrunk to
   `r*(1-s)` plus two tangent Bezier transitions -- bulges 0.23 px where mine bulged 4.62. Replace the
   curve in `simulate.py` AND the shader together, and build the SHAPE instrument before using it on
   a screenshot: an attempt at one failed three times in a single session and was thrown away
   (see §10c for the three ways).
2. **Audit finding 1 — capture the band, not the window.** `glass.cpp` blits `expandedGeometry` (up to
   3840x2160) per window per repaint when the band needs 3800x38 plus the kernels' reach: about 30x
   less traffic, and the audit calls it the only high-impact item. HIGH EFFORT: it changes the capture
   geometry and the uv mapping, so it wants a session of its own WITH the simulator to hand.
3. **Audit findings 4, 7 and 8 — small and safe.** Cache the capture per window instead of per size
   (an LRU of 4 is pessimal for five cyclically repainting windows); delete the dead code, including
   `m_active`, which is never written and makes the documented "effect off" measurement path
   unreachable; cache the 19 `setUniform` locations.
4. **Audit finding 6 — the tests pin GLSL spelling.** `tests/test-glass.sh` asserts exact strings, so a
   correct cleanup breaks assertions while real drift passes. It has already cost several false
   failures today.
5. **Then the shell**: M3 Plasma theme, M4 typography, M5 icons, M6 QStyle. See `ROADMAP.md`.

`docs/HANDOFF.md` §9v has every audit finding with `file:line` and effort, and the list of things NOT
to touch **with the measurement behind each one**. Read it before changing anything in the shader.

## The toolbox, and how to iterate without a relogin

    bash tests/run.sh                 # the whole safety net, a few seconds
    ./build.sh                        # refuses to install if verify-chain.sh fails
    ./install.sh                      # needs the password; then a relogin, or the hot path below
    ./tune.sh --show                  # what is set; ./tune.sh Key=Value applies in ONE call, live
    ./tune.sh --reset                 # back to the defaults above (safe: they are the user's taste)
    python3 simulate.py --self-test   # the model of the shader, checked against two known cases
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

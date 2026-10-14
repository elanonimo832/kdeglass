# Handoff — where this stands and what comes next

Written at the end of a long session so the next one does not have to reconstruct
anything. Everything below is either verified in this repository, measured on the
real machine, or explicitly marked as an open question.

The short version: **the material works as a blur, and cannot show the desktop
because the shader only ever reads the window's own texture.** The next step is to
capture the background. The user asked whether KWin's own blur effect already does
this, and whether it is safe to build on. That question is answered in full below.

---

## 1. The question the user asked, answered

> "you say the current blur effect of kwin does achieve the macOS glass thing, with
> all its complexities, I am not sure whether that kwin effect supports it"

**KWin's blur effect does achieve it, and it is not a special case.** It is not
emulating anything; it uses four public primitives that are installed on this
machine and available to any effect:

| Piece | Header | What it is for |
| --- | --- | --- |
| `GLFramebuffer::blitFromRenderTarget(source, viewport, sourceRect, destRect)` | KWin opengl/glframebuffer.h:113` | copies what is already painted on screen into a texture of your own |
| `GLTexture` | KWin opengl/gltexture.h | that texture |
| `GLShader` / `ShaderManager` | KWin opengl/glshader.h | the blur, as a second sampler |
| `GLVertexBuffer` | KWin opengl/glvertexbuffer.h | the quad to draw the result with |

KWin 6.7's own blur.cpp (923 lines) does exactly this and nothing
else. Its `drawWindow` is the whole idea in three lines:

```cpp
void BlurEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport
        &viewport, EffectWindow *w, int mask, const Region &deviceRegion,
        WindowPaintData &data)
{
    blur(renderTarget, viewport, w, mask, deviceRegion, data);   // capture + blur
    effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}
```

and the capture itself:

```cpp
const Region dirtyRegion =
    viewport.mapFromDeviceCoordinatesContained(deviceRegion) & backgroundRect;
for (const Rect &dirtyRect : dirtyRegion.rects()) {
    renderInfo.framebuffers[0]->blitFromRenderTarget(
        renderTarget, viewport, dirtyRect, dirtyRect.translated(-backgroundRect.topLeft()));
}
```

**A rejected option, recorded so nobody spends time on it again.** An earlier plan
in the session proposed GLFramebuffer plus a raw glBlitFramebuffer. That was
abandoned after reading KWin: glBlitFramebuffer reads from whatever is bound as
GL_READ_FRAMEBUFFER, and the screen is not a framebuffer object, so blitting from it
is not portable. blitFromRenderTarget exists precisely to solve that, and it handles
the case where the source is the screen:

    bool GLFramebuffer::blitFromRenderTarget(...)
    {
        OutputTransform transform = sourceRenderTarget.texture()
            ? sourceRenderTarget.texture()->contentTransform() : OutputTransform();
        const bool normal = transform == OutputTransform::Normal;
        if ((normal || mirrorX || mirrorY) && EglContext::currentContext()->supportsBlits()) {
            blitFromFramebuffer(sourceViewport.mapToRenderTarget(source), destination, ...);
            return true;              // the normal path: no source texture needed
        } else {
            const auto texture = sourceRenderTarget.texture();
            if (!texture) {
                return false;         // only fails when the output is ROTATED
            }
            ...
        }
    }

The output here is not rotated, so the normal path applies. Note also
mapToRenderTarget(source), which is what converts the logical coordinates of
frameGeometry() into framebuffer coordinates -- the coordinate-space risk noted in
section 5 is handled by using this function rather than by arithmetic.

So: **do not depend on the blur effect, and do not reimplement its internals. Use
the same primitives it uses.** Depending on it would be fragile — its region, its
two-pass down/upsample, its noise and its strength settings are not ours, and the
order in which effects run is not something we control. Writing our own capture is
a few dozen lines and is the same technique.

## 2. Why the current implementation cannot show the desktop

This is a mechanism, not a bug, and it is why a translucent alpha changed nothing.

The shader's only input is the window's own offscreen texture:

```glsl
// src/glass.cpp, kDiffusionFragment
uniform sampler2D sampler;          // <- the WINDOW, set by ShaderTrait::MapTexture
sum += texture(sampler, vTexCoord + d);
```

Consequences, in order:

- the title text smears, which is why it became unreadable
- the traffic lights smear, which is why they disappeared
- the bar colour is uniform, and **blurring a uniform colour returns that same
  uniform colour**, so there was nothing to see

The user said it first and better than any measurement had:

> "el fondo blanco no me deja ver nada, solo lo se por los botones que no se ven y
> el titulo que no se lee"

An alpha of 0 would still not show the desktop: it would show the window's own
black. **No alpha and no uniform can put the desktop into a texture that does not
contain it.** That is the whole remaining problem.

## 3. Where to capture, and why the answer is not obvious

`apply(w, mask, data, quads)` is where the uniforms are set, but **it does not
receive the render target**, so it cannot capture anything. The capture has to
happen in `drawWindow`, and specifically **before** the base class draws the window,
because at that moment the screen still contains the desktop.

```
Desktop painted
      |
      v
MacosGlassEffect::drawWindow(...)     <- screen holds THE DESKTOP. Capture here.
      |  capture the desktop into our own FBO
      v
OffscreenEffect::drawWindow(...)      <- maybeRender() + paint(). Draws the window.
```

As implemented (step 2), the capture covers the window's **expanded geometry** -- the
frame plus the decoration's shadow margins -- because that is the region KWin's own
offscreen texture covers and the region the shader's `vTexCoord` runs across.
Band-only is an optimisation for later.

**This requires overriding `drawWindow`.** `verify-chain.sh` used to **forbid** that
outright, because overriding it badly was the cause of two black screens; the ban
was the wrong rule. Since step 1 below it checks the property instead: **an override
is acceptable if its body continues the chain on every path** -- it must contain an
`effects->drawWindow(` or `OffscreenEffect::drawWindow(` call, and no `return` that
can leave before it (comments do not count; that trap already cost a session).

The override itself must call **`OffscreenEffect::drawWindow(...)`**: that base
implementation redirects the window, runs `apply()` -- our shader -- and continues
the chain. KWin's own `BlurEffect::drawWindow` calls `effects->drawWindow(...)`
because it does not derive from `OffscreenEffect`; the verifier accepts both forms,
deliberately, so that a correct override is not another false alarm.

## 4. Plan, in steps that each leave the repository working

| Step | Change | State at the end |
| --- | --- | --- |
| 1 | Teach `verify-chain.sh` that a `drawWindow` override is acceptable when it calls the base class on every path. | ✅ **done** (2026-10-14): the rule is now per function and per path, and four synthetic sources prove it accepts what continues the chain and rejects an early `return` or a commented-out call |
| 2 | Override `drawWindow`; capture the band rectangle into an owned `GLFramebuffer` + `GLTexture`; call the base class; bind the captured texture as a second sampler and composite it over the band. | 🟡 **written and compiled** (2026-10-14), **not yet seen on screen**: the desktop is captured frame-sized, clamped to the render target, and composited in the fragment shader (unit 1, `uHasBackground`). Needs `./install.sh` + a relogin to verify |
| 3 | Blur the captured background, tune alpha, restore `frost 6` and the kit values. | not started |

Each step must be committed before starting the next. If a session runs out of
context, the repository is left in a working, committed state and the next session
can see exactly where it stopped.

## 5. Risks, measured rather than assumed

- **The blit rectangle can fall outside the framebuffer.** `frameGeometry()` for a
  window partly off screen (or a maximised one: `frame=(0,0 3840x2160)`, which is
  the full framebuffer) produces a source rect at or beyond the edge.
  `blitFromRenderTarget` with an out-of-bounds source is undefined behaviour, and
  the visible symptom would be a black or garbage band. **State: done** -- the source
  is `intersected()` with `viewport.renderRect()` and the destination is offset by the
  same amount, so a partly off-screen window captures only what exists.
- **Coordinate spaces.** KWin's blur converts with
  `viewport.mapFromDeviceCoordinatesContained(deviceRegion)`. `frameGeometry()` is
  in logical coordinates. On this machine the scale is 1 so they coincide, but the
  code must not assume it. **State: done** -- sizes and offsets come from
  `viewport.mapToRenderTargetTexture()`, KWin's own logical-to-texture transform,
  not from arithmetic by hand.
- **The offscreen texture's v axis is flipped relative to window coordinates.**
  Established the hard way in M1.2b: the distance from the window's top is
  `(1.0 - vTexCoord.y)`, i.e. v = 0 is the window's BOTTOM. **State: settled, and the
  default is correct.** Reading KWin 6.7.5's `GLFramebuffer::blitFromFramebuffer`
  settles what the header could not: the blit maps the destination rect's top to
  `dstY0 = texH - (d.y + d.height)`, i.e. NDC `v = (texH - d.y - 0.5) / texH`, which is
  the same v the window quad carries for the same device row. Both textures are
  bottom-up and agree, so `BackgroundFlipV` stays false. The knob is not dead code:
  the agreement breaks if the source render target's `contentTransform()` is non-Normal
  (a rotated output), which takes KWin's `texture->render` fallback branch instead of
  the blit. Keep it, and keep it documented as a rotation escape hatch rather than as
  an unresolved guess.
- **The capture must cover the EXPANDED geometry, and getting it wrong looks like a uv
  bug.** The redirected texture is `snapToPixels(expandedGeometry(), scale) * scale` --
  the frame PLUS the decoration's shadow margins -- and the shader's `vTexCoord` runs
  0..1 across all of it. The first version of this step captured `frameGeometry()`:
  the desktop would have been sampled shifted by the top/left margin and scaled by
  `expanded/frame`, and the symptom (a band showing the wrong piece of background)
  would have been blamed on the uv maths or on the flip. **State: fixed**, and the
  test now asserts the region is `expandedGeometry()` snapped the way KWin snaps it.
- **The re-render into the offscreen texture does NOT re-enter this effect.**
  Worth writing down because it is the opposite of what the code looks like, and a
  review did flag it as a high-severity bug. `OffscreenEffect::maybeRender()` really
  does call `effects->drawWindow(offscreenRT, ...)`, but
  `EffectsHandler::drawWindow()` advances the effect cursor *before* calling an effect
  and **rewinds it after** (`--m_currentDrawWindowIterator;`, effecthandler.cpp) --
  so while our `drawWindow` runs, the cursor is already past us and the nested call
  resumes at the NEXT effect. If it re-entered us, every `OffscreenEffect` in KWin
  would recurse forever: `m_isDirty` is cleared only after the nested call returns.
  Consequence: the capture is taken once per paint, from the screen, and is not
  overwritten by the window's own texture. Do not add a re-entry guard for this.
- **The window is drawn over the band.** **State: resolved by construction** -- the
  composite happens inside the fragment shader that draws the band, so there is no
  second quad that could end up under the window.
- **`uTexelSize`/`uTextureSize` are frame-sized while the texture is expanded-sized.**
  Real, pre-existing (M1.2b), and it does NOT cancel cleanly: the band boundary lands
  at `barHeight * (expandedH / frameH)`, and the blur offsets shrink by the same
  fraction. It looked right because the band's implicit origin is the frame top, which
  is one shadow margin below the texture top, and the two errors very nearly cancel --
  within a few percent on a normal window, more on a small one. **State: left alone on
  purpose.** The obvious fix (`uTextureSize = expanded * scale`) makes the band START
  at the shadow top and grow by the margin, i.e. it breaks what is verified. The
  correct change carries the margin explicitly --
  `(1 - vTexCoord.y) * textureHeight > uMarginTop + uTitleBarHeight` -- and that is a
  visible geometry change, so it belongs with step 3, where it can be verified on
  screen together with the blur radius.
- **One capture texture for every window.** The M1.2b hazard (one shader, many
  windows, the last one wins) in a new place. Safe for the two reasons above: the
  capture is never re-entered, and `capture(A) -> draw(A) -> capture(B)` completes
  inside one compositing pass. If a band ever shows ANOTHER window's background, the
  capture must become per window. Written down here because it is the third time this
  shape has appeared.
- **The capture is not limited to the damaged region.** It is one blit of the window's
  area per repaint, and during a full-screen repaint that is every window. The fix,
  when it matters, is to capture the BAND only and map its uv in the shader --
  arithmetic that has to be verified on screen, so it belongs with step 3 or later.
- **GL objects are destroyed without making the context current.** `~GLFramebuffer`
  warns and skips deletion when there is no current EGL context, and KWin's own
  `unredirect()` works around it (`OffscreenEffect::unredirect` makes the context
  current before erasing). This effect's destructor does not, so unloading it can leak
  the capture FBO and print a warning. **State: known, low, not fixed** -- it is a leak
  at unload, not a crash and not a black screen, and it disappears if the capture
  becomes per window and is released in `slotWindowDeleted`, where the context is
  current.
- **Every code change needs a session restart.** KWin keeps the `.so` it loaded at
  startup; it never re-reads a changed file. Never use `kwin_wayland --replace`.
  `./install.sh` needs sudo; verify by relogin, and keep
  `bash ~/RECOVER-KDE.sh reanimar` at hand. The effect can also be unloaded for the
  session with `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass2`.

## 6. What is already done and verified

| Piece | State |
| --- | --- |
| Tokens, KDE colour schemes, GTK CSS, aurorae decoration | done |
| **M1.1** — an effect draws, anchored to the window | ✅ verified on screen |
| **M1.2** — diffusion (`frost 6`), shader correct | ✅ verified |
| **M1.2b** — the band covers the title bar only, and survives window switches | ✅ verified by the user |
| **M1.3a** — translucent band by alpha alone | 🔴 **measured OPAQUE**, does not achieve glass (see §2): the shader only ever saw the window's own texture |
| **M1.3a step 1** — the chain rule accepts a correct override | ✅ done, and the verifier is shown to fail on defective sources |
| **M1.3a step 2** — the desktop is captured and composited | 🟡 compiled and green in the harness, **not yet seen on screen**: needs `./install.sh` + relogin |
| M1.3 refraction (70), M1.4 dispersion (20), M1.5 specular highlight | not started |
| M2 squircle clipping, M3 Plasma theme, M4 typography, M5 icons, M6 QStyle | not started |

Current measurements, from the effect's own diagnostics and the user's screen:

```
title bar band: "~ : fish — Konsole" frame=RectF(1467,548 905x993)
                                     client=RectF(1471,586 897x951) barHeight=38
```

`barHeight = clientGeometry().top() - frameGeometry().top()`, **measured, not
assumed**, so it works for any decoration theme. Windows with client-side
decoration (Zen Browser, most Electron apps) report those rectangles as identical,
so the height is 0 and they get no material. That is deliberate: a guessed fallback
was tried, it blurred Zen Browser, the user asked for it to be removed, and it is
gone.

## 7. How to test, and the trap in testing this

```bash
cd effect-kwin
./install.sh        # installs; needs sudo while the timestamp is live
# then LOG OUT AND BACK IN. KWin does not reload a .so.
./test-titlebar.sh  # band blurred, content sharp, survives window switching
./test-glass.sh     # does the bar take colour from behind it?
```

**First, without logging out:** `bash tests/run.sh` validates the embedded shaders
with `glslangValidator` (`#version 330 core` prepended; KWin prepends its own header
at runtime, so what this proves is that the shader BODY is well formed, not that
KWin's preamble matches). A shader that does not compile is otherwise invisible until
a relogin: `loadShader()` logs a critical, the effect draws nothing, and there is no
way to see it from here. Skipped, loudly, if the validator is not installed.

**Then, for M1.3a step 2 specifically:** the criterion is that the band shows the
desktop, so `test-glass.sh` + `measure-glass.py` is the verdict (it reported 3.2,
OPAQUE, for the alpha-only attempt; a composite at `uGlassAlpha` should move by tens
because the bar now carries 45% of the background).

**`test-titlebar.sh` will NOT say CORRECT yet, and that is not a regression.** Its
criterion is M1.2b's -- the band loses edge energy -- and in step 2 the band shows the
captured desktop, which is still SHARP (step 3 is the blur). What the tool must do is
say *which* state it is, so it now has a third verdict and its own exit code:

    0 CORRECT (band blurred, content intact)   -- expected again after step 3
    3 THE BAND CHANGED BUT KEPT ITS DETAIL     -- the expected state in step 2
    1 NOT APPLIED (the band did not change)    -- a real problem

**And the journal says which problem you have**, which saves a second relogin:

```bash
journalctl --user -b -o cat | grep macos-glass | grep -E 'capture:|refused'
```

    capture: ok=N refused=0   the desktop IS being captured -> a wrong band is a
                              COMPOSITE problem (uv, alpha, colour), not a missing one
    capture: ok=0 refused=N   there is no capture at all; the band is the old opaque
                              alpha path (the GL context refused the blit)

Two things the instruments CANNOT catch, and both are for the eye:

- **the desktop upside down** -- two flat backgrounds look the same flipped. If that
  is what you see, `BackgroundFlipV` in `kwinrc` (see section 5) is the switch.
- **a band that shows another window's background** -- the capture texture is one
  object shared by all windows. Check two windows over different backgrounds.

`test-glass.sh` **holds the window still and changes only the background**. Its
first version asked the user to move the window, which changed two things at once —
the pixels being measured and what was behind them — and it reported a difference of
189.5 as "GLASS". The 189.5 was the movement. The user caught it by looking.

The instruments:

| Tool | Question it answers |
| --- | --- |
| `measure-titlebar.py` | is the TITLE BAR blurred while the CONTENT stays sharp |
| `measure-glass.py` | does the bar change colour when only the background changes |
| `measure-diffusion.py` | is local contrast lost with brightness preserved |
| `verify-chain.sh` | does the effect continue KWin's paint chain (black-screen safety) |
| `tests/run.sh` (glass) | do the embedded shaders compile, without a screen |

## 8. Lessons this step paid for

Recorded without softening, because they cost the user real sessions.

**Three bugs in M1.2 were the same bug: state belonging to one window kept
somewhere belonging to all of them.**

- `setUniform()` without binding the shader. It is `glUniform1f()`, which writes to
  whichever program is active. `uRadius` stayed 0, all nine taps sampled the same
  texel, and the output equalled the input — a perfect no-op with no error.
- the uniforms were written once per window at add time, but **one shader object is
  shared by every window**, so the last window won. The band vanished when focus
  changed. That is what the user reported and what the counters showed.
- a guessed fallback band applied one assumption to every window.

**A measurement can be correct and still answer the wrong question.**

- whole-window diffusion reported "not diffused" and could not tell *where* the
  band was. It was at the bottom, because the offscreen texture's v axis is flipped.
- the glass test compared two different screen regions.
- an ad-hoc check of regex syntax was satisfied by its own error message, because
  the error text contained the pattern being searched for.

**A check that does not run is not a check.** A stray quote left `test-titlebar.sh`
unparseable while the harness reported all green. A pattern that matched a comment
made an assertion fail on correct code. In an extended regex, `\(` opens a capture
group; a literal parenthesis needs `[(]`.

**The user's direct observation beat the instruments three times.** They said the
effect vanished on window switch, that the band was at the bottom, and that the
glass was invisible. Each time a number said otherwise, and each time they were
right. When a symptom does not match a measurement, **suspect the measurement
before the observation.**

**Do not build a solution to a problem the user did not report.** They reported that
Konsole *lost* the material when Zen loaded. The response was a new feature for Zen,
which they then had to ask to have removed.

**Bulk substitutions damage the file being edited.** Three times, twice in the
effect source and once in the tests. All three were caught by the compiler or by
running the tests, none by reading the diff.

## 9. Working agreements

- **Conversation in Spanish. Everything written in the repository in English.**
  Token file *contents* stay Spanish on purpose: Figma collection names and keys are
  read by the generators.
- **TDD.** Write the test, watch it fail, break the implementation on purpose to
  confirm the test detects it.
- **Small commits**, each explaining *why*, not what.
- **Honest documentation.** Superseded conclusions stay visible and are marked as
  superseded. `docs/METHODOLOGY.md` is the place for process lessons.
- Installers run **without** a `sudo` prefix: `./install.sh`.
- **Never** recommend `kwin_wayland --replace`: it starts a second compositor
  competing for DRM and GL, and it produced a black screen twice. Recovery is
  `bash ~/RECOVER-KDE.sh reanimar`, which is hot and needs no logout.
- The user values persistence over giving up, and has said so directly. What they do
  not want is a fifth hypothesis presented as a fix.

## 10. RESOLVED: the harness was not deterministic, and the cause was measurable

**No longer a priority.** The failure was not state leaking between test files, and
it was not the live session. It was one line in `tests/lib.sh`:

    grep -vE '^\s*(//|\*|/\*)' "$2" | grep -qE "$3"

`grep -q` exits at the FIRST match and closes the pipe. The comment-stripper on the
left is then killed by SIGPIPE, and `set -o pipefail` -- set by `run.sh` -- makes the
whole pipeline report 141 **even though the match was found**. Whether the producer
is still writing when `grep -q` exits is a scheduling question, so the same
assertion on the same file was stable on its own and unreliable in company.

That signature -- deterministic alone, unstable together -- is exactly what state
leaking between files would look like, and it is why the failures moved from one
file to another: whichever `afirmar_codigo` call lost the race was the one reported.

Measured instead of guessed:

    the helper on the real glass.cpp (14 KB), 200 calls   -> 1 false FAIL
    the same helper on a 500 KiB file, 200 calls          -> 200 false FAILS
    before the fix: 8 full runs -> 150,150,150,150 and 149,149,148,148 (1-2 fails)
    after the fix:  25 full runs -> 0 fails, rc 0, all nine section headers

The 500 KiB case matters: larger than the 64 KiB pipe buffer, the producer is still
writing when `grep -q` exits, so the race becomes **certain**. A race that cannot be
forced cannot be tested, and `tests/test-harness.sh` now forces it.

What changed:

- `tests/lib.sh`: `afirmar_codigo` is split into `codigo_contiene` (the predicate,
  no pipe) plus the counter. Comments are still stripped, and there is a check for
  that too, because the cheap fix for a race is to match comments as well -- which
  is the false-positive trap this project already paid for once.
- Nine `... | grep -q ...` pipelines -- one in `lib.sh`, five in `test-effect.sh`,
  three in `test-titlebar.sh` -- now capture the producer first
  (`grep -q PAT <<< "$(producer)"`).
- `tests/run.sh` no longer `source`s the test files into its own shell. Each file
  runs in its own process through `tests/run-one.sh`, with its own counters and its
  own failure list, and the runner sums them. A variable, a function, a `set` flag
  or an `exit` in one file can no longer reach the next.
- Each file is bounded by `timeout` (120 s default, `TEST_TIMEOUT` overrides). A
  hang is now a named failure of that file, in the summary, so "did not finish"
  cannot pass unnoticed again.

### The three candidates in the older reading, checked one by one

1. **The headers were lost by the runner.** No: every full run -- before the fix as
   well as after -- contains all nine `== name ==` headers. The loss was in that
   session's capture, not in `run.sh`.
2. **A test was touching the live session.** No: `test-glass.sh` and
   `test-titlebar.sh` are pure static assertions over `glass.cpp` and `glass.h`.
   Nothing under `tests/` contains `qdbus`, `busctl`, `dbus` or an executed
   `kwin_wayland --replace`. The scripts that DO talk to the live KWin are
   `effect-kwin/test-installed.sh` and `effect-kwin/test-hot.sh`, and the suite
   never runs them.
3. **The `.pass-count` cache was a race.** No: `run.sh` writes it and nothing reads
   it -- no test, no tool, no doc, and it is git-ignored. It stays as a convenience
   only.

### The contamination was real, it just was not the cause

Sourcing every test file into one shell did leak state, and that was measured, not
deduced: `test-diffusion.sh` sets `CABECERA`, and with the old runner that variable
was still set when `test-harness.sh` ran. `tests/test-harness.sh` keeps a canary
for it, so a future runner that goes back to one shared shell fails a test instead
of losing a session.

**The harness is deterministic now.** The count itself is deliberately not written
in this document (see section 11); what is written is the property: every full run
since the fix -- more than fifty by now, including after each M1.3a commit, which is
when a harness usually starts drifting again -- has produced **byte-identical**
output, `fail: 0`. The rule that was broken was already in `docs/METHODOLOGY.md` and
already enforced on `effect-kwin/*.sh` -- the file that runs every assertion was the
one place it did not reach. Rule 6 exists for that.

### Superseded (kept for the record): the isolation hypothesis

This is how the evidence read before the cause was measured. It was wrong about the
mechanism, and right that the harness could not be trusted.

Found while checking this document against reality, and it undermines confidence in
every "all green" claim made during the session that produced it. Five consecutive
runs of `bash tests/run.sh`, with nothing else touching the repository:

    run 1: pass=148
    run 2: pass=149
    run 3: pass=149
    run 4: did not finish
    run 5: did not finish

and the `== section ==` headers did not appear in the captured output at all, even
though `tests/run.sh` prints them.

**Start here.** A test runner whose result varies between identical runs cannot
verify anything, and this is the third time this project has hit that idea -- after
the `grep -q` under `pipefail` and the test files damaged by edits made while the
suite was reading them. The difference is that this time the runner itself is the
unreliable component, so no individual assertion can compensate.

Things to check, in order:

  1. Does `run.sh` capture output in a way that loses the section headers, or was the
     capture in the check the problem? The suite may be fine and the *measurement of
     it* broken -- which would be entirely in keeping with this session.
  2. Does one test leave state behind for the next? `test-glass.sh` and
     `test-titlebar.sh` talk to the running KWin over the session bus, unload and
     reload the effect, and write to `build/`. If any of them runs during a
     non-interactive suite invocation, it must not touch the live session at all.
  3. Is there a timeout? Two runs produced no summary, which looks like truncation
     rather than an assertion failure.

### The evidence points at test ISOLATION, not at the patterns

Measured directly, and this narrows it a long way:

    the exact grep, 20 times in a row          -> 20 pass, 0 fail
    bash tests/run.sh glass   (that file alone) -> 6 runs, 0 failures
    bash tests/run.sh         (the whole suite) -> fails intermittently

The same assertion, on the same file, with the same pattern, is deterministic on its
own and unreliable in company. So the fault is almost certainly **state leaking from
one test file into the next**, not a badly written pattern. That is why several
assertions in this project appeared to "fail at random" and were patched one by one
without ever being understood -- and why the failures moved between files on
successive runs.

Two candidates, both worth checking first because they are the ones that touch
anything outside the repository:

  - `tests/test-glass.sh` and `tests/test-titlebar.sh` talk to the LIVE KWin session
    over the session bus. They unload and reload the effect and write into
    `effect-kwin/build/`. If the suite sources or runs either of them
    non-interactively, they are modifying the user's desktop from inside an
    assertion.
  - `run.sh` caches a check count so tests can cite it without re-running the suite.
    A cache that is read by the run that writes it is a race, and it would produce
    exactly this pattern: stable alone, unstable together.

Until this is resolved, treat any "all green" in this repository as unconfirmed.

**That conclusion is superseded: it is resolved, see the top of this section.** The
sentence stays because the shape of the mistake is the lesson -- a plausible
mechanism ("state leaks between files") was written down as a finding before the
tool that produced the evidence had been verified.

## 11. Repository state

- Branch `main`, remote `https://github.com/elanonimo832/kdeglass` (public).
- Harness: `bash tests/run.sh` (all) or `bash tests/run.sh <name>` (one file). Each
  test file runs in its own process via `tests/run-one.sh`, bounded by
  `timeout` (`TEST_TIMEOUT` overrides, 0 disables). `tests/test-harness.sh` audits
  the harness itself. Do not write the harness size in docs: a doc that quotes the
  count breaks the run that verifies it.
- Effect plugin id: `macosglass2`. The id `macosglass` broke rendering with
  byte-identical code; the cause was never explained, and `macosglass2` works.
- `macosglass2Enabled` in `~/.config/kwinrc` is **true**, so the effect loads at
  login. It is stable in that state (the band stays put across window switches),
  but it also means the desktop is NOT sharp on login. If a test needs a sharp
  baseline, set it false and re-login, or unload it for the session with:
  `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass2`
- Installation target: `/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so`
  (note `plugins/` at the end; installing one level up makes KWin never see it).
- No Apple material in version control. SF Pro is not redistributable; the project
  uses Inter (SIL OFL). The original brief stays in Spanish as `BRIEF-ORIGINAL.md`,
  sha256 `1f95c5239a3af3ef99614ff1104363a6e2c7799b4e1929d5eeba1053497bf5e1`.

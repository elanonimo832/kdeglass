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
| 2 | Override `drawWindow`; capture the desktop into an owned `GLFramebuffer` + `GLTexture`; call the base class; bind the captured texture as a second sampler and composite it over the band. | ✅ **VERIFIED ON SCREEN** (2026-10-14): band moved **73.8** over two backgrounds where 12 is the threshold, `capture: ok=1200 refused=0`. The capture covers the window's expanded geometry, clamped to the render target, composited in the fragment shader (unit 1, `uHasBackground`) |
| 3a | Blur the captured background, in two scales so it does not read as ghost copies. | ✅ **done and seen on screen** (2026-10-14): `BackgroundRadius` defaults to the kit's outer 16, the inner scale is 6/16 of it, and 0 still takes the single-sample path. Tuned live with `reconfigureEffect`; the user's eye picked 16 over 6 |
| 3b | Make the chrome readable again (title and buttons), round the corners, and make the quality knobs tunable. | ✅ **done** (2026-10-14): the bar's blur became the blank that isolates the chrome, which is drawn crisp over the glass; the halo the first version produced was fixed with a TIGHT baseline of its own; `GlassAlpha`, `ChromeRadius` and `ChromeLow` are settings |
| 3b″ | Vibrancy: the chrome keeps a minimum contrast against the glass, so a dark backdrop does not swallow a dark title. | 🟡 **written, off by default, NOT in the installed build**: `Vibrancy` is the minimum contrast (0 = off, try 0.30-0.45). Adapted from macOS, and only for achromatic chrome so the traffic lights keep their colours |
| 3b′ | The rounded corners the user asked for. | ✅ **done in the effect, not in the theme**: this theme's SVG has a 12 px arc but aurorae clips the corner piece into a 1 px cell, so the frame is a rectangle and there was nothing to follow. The effect draws the rounded rectangle itself (`CornerRadius`, default 12; 0 = off) and discards what falls outside. That is the beginning of M2, driven by a real request |
| 3c | A frost that AVERAGES instead of sampling, so text behind the window dissolves into a haze. | ✅ **done** (2026-10-14): the backdrop is captured already reduced (a scaled blit) and the kernel only has to be wide, not dense; the tone of the bar in the glass is averaged over half the bar's height so the title leaves no ghost |
| 3c′ | Stop the per-paint diagnostic from flooding the journal. | ✅ **fixed** (2026-10-14): `prePaintWindow` incremented its counter only while it was below six and then gated the message on `pre <= 6`, so it logged on every paint of every window. Folded into the next build; the regression guard is in `tests/test-glass.sh` |
| 3d | Settle whether the band samples the backdrop where it belongs, or displaced by the decoration's shadow margins. | 🟡 **instrument ready, measurement pending**: `measure-alignment.py` correlates the band against the same backdrop just outside the window (rows against a strip beside it, columns against a strip above it), with synthetic cases in the suite that prove it recovers a known (14, 7) WITH its sign and refuses to invent one from a flat backdrop. Needs one screenshot with text behind and `BackgroundRadius=0` |

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
- **The corner clip assumes the fragment's `vTexCoord` runs across the FRAME.** It is
  the same assumption the band's own geometry was measured under, and the user's first
  look at the rounded corners -- "creo que ya funcionan las esquinas" -- supports it at
  the radius in use. It is not proof: a few pixels of error in that mapping would show as
  arcs that are not symmetric or not concentric with the frame's edge. The pixel
  comparison written down for step 3d is still the way to settle it exactly.
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
  **State: measured, and the predicted artefacts are NOT there.** An off/on capture
  pair of a real window, differenced, gives the band's exact rectangle: **39 rows**
  starting at the window's visible top edge and ending at the client top (barHeight
  38), spanning the window's **full visible width**, with hard zero-difference
  boundaries immediately outside. So the band covers the whole title strip and paints
  nothing into the shadow: no tab on either side, no strip above the frame, no short
  band. The screenshot shows the same thing -- the blurred traffic lights and title
  text sit inside the strip, and the wallpaper outside is untouched.
  **What was wrong in the first reading**, recorded because it is the same trap twice:
  the "side tabs" came from taking the *whole-window* difference bounding box and
  attributing it to the band, with the frame's origin taken from the log line of a
  DIFFERENT window ("~ : fish" against the captured "effect-kwin : bash"). Comparing
  the band rows against client rows -- the margins change in the former and not in the
  latter -- is what settled it: those columns are the window's own left and right
  edges, not shadow.
  **What is still open is the SAMPLING, not the shape.** Every size the shader uses is
  derived from `frameGeometry()` while KWin's texture is
  `snapToPixels(expandedGeometry(), scale) * scale`, so the sampled background may be
  offset by the top/left shadow margin and scaled by ~1.9%. Against a flat wallpaper
  that is invisible, and no measurement so far can see it. The test that would: with
  `BackgroundRadius=0`, put a window with TEXT behind the target and check whether the
  band's content lines up with the same text where it shows around the window. If it
  does not, the fix is to pass the texture's own size and the margins as uniforms.
  **And the band's own measurement is NOT evidence that the sampling is fine**, which is
  worth writing down because it looks like it is: a review derived that the band test
  normalises `vTexCoord` through `uTextureSize`, so the margin cancels and the band lands
  exactly at the frame's top edge UNDER EITHER reading. The band sizes correctly and the
  background can still be sampled 14 px to the left.
  **The corners, on the other hand, do discriminate, and they point at an offset.** The
  clip draws a rounded rectangle from `vTexCoord * uTextureSize`, i.e. from the FRAME's box;
  if `vTexCoord` spanned the expanded texture instead, the arcs would land at the shadow's
  corners, 14 px left and 7 px up, and a 12 px radius there would leave the window's own
  corner essentially square. The user saw rounded corners at radius 12 and said so ("creo
  que ya funcionan las esquinas"), which is evidence for the frame reading -- and therefore
  evidence that the SAMPLING offset is real rather than hypothetical. Two smaller
  consequences of the same mismatch, both negligible: the frost and chrome kernels step by a
  margin-sized fraction fewer texels than asked (~1.9 %), and the clip box is off by the
  margin.
- **One capture texture for every window.** The M1.2b hazard (one shader, many
  windows, the last one wins) in a new place. Safe for the two reasons above: the
  capture is never re-entered, and `capture(A) -> draw(A) -> capture(B)` completes
  inside one compositing pass. If a band ever shows ANOTHER window's background, the
  capture must become per window. Written down here because it is the third time this
  shape has appeared.
- **The capture is not limited to the damaged region.** It is one blit of the window's
  area per repaint, and during a full-screen repaint that is every window. The fix, when
  it matters, is to capture the BAND only and map its uv in the shader. **Its condition is
  now met** -- step 3 is done, and `measure-alignment.py` is what makes that arithmetic
  verifiable at all: a wrong uv mapping shows up as a displacement of the band's content,
  which is a number, not an opinion. **It is still not done here on purpose**, and the
  reason is sequencing rather than risk: the build waiting for a relogin has to be looked
  at first, and a change to the freshly-verified sampling should not ride along with it.
  Whoever does it should run the instrument before and after.
- ~~**GL objects are destroyed without making the context current.**~~ **THIS CLAIM WAS
  WRONG, and checking it took one paragraph of KWin's own documentation.** It assumed the
  context is not current in the destructor and proposed making the capture per window to
  avoid the leak. KWin's `/usr/include/kwin/effect/effect.h` says the opposite, in the section on
  OpenGL: *"The framework ensures that the OpenGL context is current when the Effect gets
  created, destroyed or reconfigured and during the painting stages."* The destructor is defaulted,
  the cache dies with it, and the journal has never carried `~GLFramebuffer`'s "no current
  context" warning. **State: not a risk; nothing to fix.** Kept here, struck through,
  because the shape of the mistake -- writing down an API behaviour instead of reading it --
  is the one this project has paid for most often.
- **The capture texture used to be reallocated whenever the window size changed.**
  **FIXED (2026-10-14), as this note said it would be once the mechanism was verified.**
  One GL texture sized to the window being captured meant that a frame in which two
  windows of DIFFERENT sizes both repainted allocated and freed it twice -- per frame,
  for as long as that kept happening (a terminal with a blinking cursor next to a video).
  It is now one texture+framebuffer per distinct reduced size, capped at four, evicting
  the oldest; the uv maths is IDENTICAL, which is why this shape was chosen over the
  other obvious fix (one grow-only texture with a scale uniform, which would add a
  packed-layout mapping that has to be verified on a screen). Three things keep it honest:
  `m_fondoActual` is cleared at the start of every capture, so a failure can never leave a
  stale texture bound; a live capture is consumed inside the call that fills it (the
  capture/draw ordering the note above depends on), which is why eviction is safe; and
  `std::map` nodes do not move on insert, so a pointer into the cache stays valid.
- **`test-installed.sh` is an M1.1-era instrument and its verdict is meaningless now.**
  It looks for the flat 48x48 marker patch that M1.1 drew; M1.2 replaced it with the
  material band. Running it today reports "not drawn" about a working effect. Its
  header and the effect README say so, and the live procedure points at
  `test-glass.sh` and `test-titlebar.sh` instead. Left in place because the reasoning
  in its comments (measure by difference, never by colour) is still the reason the
  other two tools are built the way they are.
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
| **M1.2** — diffusion (`frost 6`), shader correct | ✅ verified — and since M1.3a step 3b its role is the band's **baseline**, not its colour: the material is the frosted backdrop, and the blur is what isolates the chrome from the bar |
| **M1.2b** — the band covers the title bar only, and survives window switches | ✅ verified by the user |
| **M1.3a** — translucent band by alpha alone | 🔴 **measured OPAQUE**, does not achieve glass (see §2): the shader only ever saw the window's own texture |
| **M1.3a step 1** — the chain rule accepts a correct override | ✅ done, and the verifier is shown to fail on defective sources |
| **M1.3a step 2** — the desktop is captured and composited | ✅ **VERIFIED ON SCREEN** (2026-10-14): window held still, only the background changed, the band moved by **73.8** where 12 is the threshold (the alpha-only attempt scored 3.2), and the effect's own counter read `capture: ok=1200 refused=0` -- the blit never failed once |
| **M1.3a step 3a** — the frost over the capture | 🟡 shipped in that same build, off by default; switched on with a config key. See §7 |
| **M1.3a step 3b** — alpha, and the frame-vs-expanded geometry | ⬜ next, and it starts from a measured margin: `shadowMargin= QPointF(14, 7)` |
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

Both live test scripts **abort if the installed plugin is not the build in the tree**
(`cmp`), because a relogin that skipped `./install.sh` would measure the previous
effect and report its OPAQUE as if it were the new code's. At the time of writing the
installed plugin IS the pre-capture build, so `./install.sh` is not optional.

**First, without logging out:** `bash tests/run.sh` compiles the embedded shaders with
`glslangValidator` using **KWin's own preambles**, read from its source rather than
invented: `ShaderManager::generateCustomShader` prepends only the `TRAIT_*` defines and
`GLShader::preprocess` prepends the version directive -- `#version 140` on desktop
OpenGL, `#version 300 es` plus `precision highp` qualifiers on OpenGL ES. **Both are
checked**, because both are paths KWin takes and a shader that only compiles on one of
them would break on somebody else's machine and never here. A shader that does not
compile is otherwise invisible until a relogin: `loadShader()` logs a critical, the
effect draws nothing, and nothing on this side can see it. Skipped, loudly, if
`glslangValidator` is not installed. What it still cannot prove is which GLSL version
the running context reports.

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

**After the step-3b relogin, this is the checklist** (all of it is for the eye, and
none of it needs a second relogin):

- *Are the traffic lights and the title crisp?* They should read as clearly as with the
  effect off. If they look washed out, `GlassAlpha` is the knob (and if they look
  *smeared*, the baseline/chrome path is broken, not tuned).
- *Are the window's corners round?* They are drawn by the EFFECT now, because the
  theme's own arc does not survive aurorae's 1 px corner cells -- measured, not assumed:
  in an effect-off capture the title bar's white starts at the same x on its first row
  as fifteen rows below, i.e. no arc, and outside it there is shadow. `CornerRadius`
  tunes the radius and 0 turns it off.
- *Do the title and the buttons have a bright halo around them?* Then the chrome mask's
  baseline is too wide: `ChromeRadius` is that width (default 3 texels) and
  `ChromeLow` is how much deviation counts (default 0.06).
- *Is the frost a smooth haze, with no recognisable text behind?* Nine samples 16 px
  apart do not average the backdrop, they SAMPLE it, and text stays readable through the
  band with ghost copies of itself. The capture is therefore taken ALREADY REDUCED (a
  scaled blit, the way KWin's own blur does it); `FrostDownsample` overrides the factor
  and 0 derives it from the radius. Be precise about what that buys: GL minifies with
  BILINEAR filtering, which reads a 2x2 neighbourhood rather than box-averaging the whole
  block -- a pre-smoothing, not a true average, and enough to stop the taps from sampling
  text. A true average would mean averaging the block in the shader.
- *Is there a ghost of the title itself?* Then the bar's tone in the glass still has
  chrome in it: it is averaged over half the bar's height for exactly that reason.
- *On a DARK backdrop, does the title vanish?* That is the theme drawing a dark title on
  a bar whose tone is now the backdrop. `Vibrancy` (minimum contrast, 0 = off, try 0.35)
  pushes achromatic chrome towards black or white, whichever the glass is furthest from,
  and leaves the traffic lights alone. It ships OFF because it changes the title's colour,
  which is a decision for a screen:
  `kwriteconfig6 ... --key Vibrancy 0.35` then the usual `reconfigureEffect`.
- *Is there too much or too little glass?* Then `GlassAlpha` (bar opacity, default
  0.55) and `BackgroundRadius` (frost, default 16) are the two knobs, both live:
  `kwriteconfig6 ... --key GlassAlpha 0.4` then
  `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2`.

Two things the instruments CANNOT catch, and both are for the eye:

- **the desktop upside down** -- two flat backgrounds look the same flipped. If that
  is what you see, `BackgroundFlipV` in `kwinrc` (see section 5) is the switch.
- **a band that shows another window's background** -- the capture texture is one
  object shared by all windows. Check two windows over different backgrounds.

**And for step 3d, one screenshot settles it.** Put something with TEXT behind the
window, set `BackgroundRadius=0` (the sharp composite, so the band is not blurred), and:

```bash
python3 measure-alignment.py /ruta/captura.png <x> <y> <w> <bar>
```

The rectangle is the one the effect prints (`frame= ... barHeight= ...`). It reports a
horizontal and a vertical displacement, with the sign, and `(0, 0)` means the sampling
agrees with the decoration and there is no margin bug to fix. It needs structure in BOTH
axes to say anything: rows against a strip beside the window (text lines), columns
against a strip above it (window edges, page columns). A flat backdrop gives INCONCLUSIVE
rather than a number made of noise.

**Then the frost, in the same session.** The blur over the captured desktop is
`BackgroundRadius`, now defaulting to the kit's outer 16 (6 was too small to see, 0 is
the sharp composite step 2 was verified with):

```bash
kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundRadius 16
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
```

**That second command is not interchangeable with `qdbus6 org.kde.KWin /KWin reconfigure`**,
and this document said the wrong one for a whole session. Read from KWin 6.7.5:
`DBusInterface::reconfigure()` goes to `Workspace::slotReconfigure()`, which re-parses
`kwinrc` and touches windows and rules but never calls `effects->reconfigureEffects()`;
`EffectsHandler::configChanged()` only reacts to the `[Plugins]` group; and
`EffectsHandler::reconfigureEffect(name)` -- the D-Bus method above -- is the one that
re-parses and *then* calls the effect's `reconfigure()`. The symptom of using the wrong
one is exactly the worst kind: the value is written, the command reports success, the
effect keeps its old value, and nothing says so. The `reconfigure:` line in the journal
is what tells the two apart.

It does not disturb the measurement above: `measure-glass.py` compares the band's
**mean** colour over two backgrounds, and a blur preserves the mean. It does change
what `measure-titlebar.py` reports -- its exit code 3 ("the band changed but kept its
detail") is what an UNBLURRED capture looks like -- so read its numbers, not just the
code.

**And judge the frost with the right pattern.** The first attempt used a wallpaper of
380 px squares and reported "no frost": a 6 px blur is 1.5% of such a square and cannot
be seen, while the SAME 6 px smears the traffic lights and the title text beyond
recognition -- both are visible in the same screenshot. Text or a photo behind the
window shows the frost immediately; large flat geometry cannot show it at all.

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
| `measure-alignment.py` | is the backdrop sampled where it belongs, or displaced by the shadow margin (step 3d) |

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
  **The installed plugin is the 14:31 build, which is one step behind the tree**: it was
  measured byte-for-byte against `effect-kwin/build/`, whose file is the 14:36 build with
  the chroma term that stops the traffic lights coming out as bright rings with glass in
  the middle. Whoever next sees the screen should `./install.sh`, relogin, and expect
  SOLID buttons. The live test scripts refuse to measure a stale install for exactly this
  reason; source and build diverge on purpose in the meantime (see the note below).
- **The settings the user actually runs with** (read from `~/.config/kwinrc`, not assumed):
  `BackgroundRadius=24`, `CornerRadius=20`, `GlassAlpha=0.4`, and nothing else. That is a
  clear taste: a wider frost, rounder corners and LESS of the bar's own tone than the
  defaults (16 / 16 / 0.55). They were tuned against the build whose frost SAMPLED the
  backdrop; the reduced capture averages it, so the same numbers may read differently --
  re-tune by eye before baking any of them as the default.
- **The source is ahead of the built `.so` on purpose, and this is the complete list of
  what the next `./build.sh` will fold in.** All of it is committed and validated OFFLINE
  (the shader validator and the compiler read the source; see the note on `-fsyntax-only`
  below), because a rebuild would make the live tests abort mid-verification:
  1. **Vibrancy**, off by default (`Vibrancy = 0`), as a GLSL function called by BOTH the
     capture path and the no-capture fallback.
  2. **The consistency pass**: three comments that no longer matched the code, and the
     fallback's alpha documented rather than "fixed" without being able to measure it.
  3. **The journal-flood fix** in `prePaintWindow` (74,609 spam lines in one boot).
  4. **The per-size capture cache** (one texture+framebuffer per distinct reduced size,
     capped at four), replacing a single pair.
  5. **The review fixes** (two independent reviews of items 1-4): the capture cache evicts
     the least recently used size instead of the smallest, the capture pointer is cleared
     before any early return, the reduced texture is cleared before the blit, the
     no-capture fallback writes premultiplied like the main path, and windows whose frame
     reaches the screen's edge are no longer rounded. Plus the vibrancy arithmetic, which
     now delivers the contrast it promises instead of approaching it.
  6. **Comment-only and documentation changes** that cannot affect the artifact: the
     destructor's note about the context, the roadmap's closing criterion, the settings
     table in the effect README, the sampling evidence in section 5, and the new checks in
     `tests/`.
  **Every one of those is behaviour-preserving with vibrancy off**, so the relogin that
  installs them should show the band exactly as it is now: that is the thing to look at,
  and only then is `Vibrancy` worth turning on.
- **Compiling without producing an artifact** is possible and is what these changes were
  checked with: `ninja -C build -t commands | grep glass.cpp` gives the exact compiler
  invocation, strip `-MD/-MT/-MF` and add `-fsyntax-only`. The compiler type-checks the
  file and NOTHING is written, so `build/*.so` (and therefore the freshness guard the live
  scripts depend on) is untouched. Useful when the user is mid-verification.
- No Apple material in version control. SF Pro is not redistributable; the project
  uses Inter (SIL OFL). The original brief stays in Spanish as `BRIEF-ORIGINAL.md`,
  sha256 `1f95c5239a3af3ef99614ff1104363a6e2c7799b4e1929d5eeba1053497bf5e1`.

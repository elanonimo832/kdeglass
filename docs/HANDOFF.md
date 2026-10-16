# Handoff — where this stands and what comes next

**Starting here? `docs/NEXT.md` is the one-page entry point**: the current state, the
ordered next steps and the rules. This file is the long record, in order, with the
measurements behind every decision.

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
| 3b′ | The rounded corners the user asked for. | ✅ **done in the effect, not in the theme**: this theme's SVG has a 12 px arc but aurorae clips the corner piece into a 1 px cell, so the frame is a rectangle and there was nothing to follow. The effect draws the rounded rectangle itself (`CornerRadius`, default 20 since 9k -- 12 was the first attempt; 0 = off) and discards what falls outside. That is the beginning of M2, driven by a real request |
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
- **A dark strip along the bottom of the band.** **FIXED (2026-10-14), and it was this
  session's own regression.** Widening the tone kernel to half the bar's height (to stop the
  title ghosting into the glass) made it reach *below* the bar, where the theme's white border
  and then the client's dark content sit: a sample landing in the client drags the tone down,
  and the glass darkens in a band along the bottom edge. Measured on the user's screenshot:
  the lower **14 rows of a 39-row band** had an implied tone of **167** where the bar's own is
  **238** -- exactly (246 + 246 + 30) / 3, one sample of three in the client -- with a one-row
  transition, because three discrete samples make a step and not a gradient. `measure-*` could
  not have caught this; the user's eye and one profile of the screenshot did. Both kernels over
  the WINDOW texture (tone and chrome baseline) now clamp the sampled v to the band's own
  span; the kernel over the CAPTURE must not, because the backdrop legitimately extends past
  the bar -- and that distinction is asserted in the suite.
- **Ghost copies of the chrome, displaced by the tone radius.** **FIXED (2026-10-14), and it
  was the second half of the same mistake.** A blur of the bar still CONTAINS the chrome, just
  moved: measured on the user's screenshot, the traffic lights sit 20 rows below the bar's top
  and rows 48..70 of the band carried a dark ghost of them (minimum 59 against a band of 188),
  because one sample of the tone's 3x3 had landed on the buttons -- 19 rows above them, which
  is exactly the radius. The user's words were precise: "botones fantasma arriba de los
  botones". The tone is now a MEDIAN of five samples (centre plus four at the radius, the
  vertical ones clamped inside the bar), which discards a minority of chrome by construction:
  at most the centre can be on a button. The sorting network is a nine-compare-exchange one,
  verified against a Python replica over 20,000 random cases before it went into the shader,
  because a hand-written sorting network that is subtly wrong looks fine and is not.
  **AND THE SAMPLES HAD TO GO UP AND DOWN, NOT SIDEWAYS.** The first median took two of its
  five samples along the row; this theme's chrome is WIDE and THIN, so a line of text and a row
  of three traffic lights both cover it horizontally and three of the five samples were chrome
  again -- the user's next screenshots showed the buttons clean and the title still doubled,
  which is that difference exactly. All five samples are vertical now (centre, one radius, two
  radii, clamped inside the bar), and vertical is the only direction in which this chrome is
  not there. The suite asserts BOTH halves: no sample along the row, four along the column.
  **The bar's own colour is a setting now, and Apple's kit says what it should be**: see
  `tokens/tokens-kit.toml` `[liquid_glass]`, `opacity = 25`. The user's `GlassAlpha` was 0.4
  and the default 0.55, so "el efecto es muy blanco" is the material keeping too much of the
  theme's near-white bar -- Apple's own number is a quarter.
- **A white halo around the chrome: the third face of the same mechanism.** **FIXED
  (2026-10-14) by retiring the mask's own baseline.** A 3x3 baseline close to the chrome gets
  MIXED with it, so the bar pixels beside a glyph or a button deviate from that mixture, are
  classified as chrome, and are drawn with the theme's white bar. Measured on the user's
  screenshot after the median landed: **1140 pixels brighter than the band around the buttons**
  (maximum 255 against a band of 108) and **1812 around the glyphs**, which is what "el titulo
  sigue igual de mal" and "un circulo debajo de ellos" both were -- a halo, not a ghost.
  The mask now measures the deviation against the **median tone itself**, which is by
  construction "the bar's own colour": a glyph deviates from it, a bar pixel beside the glyph
  does not, a traffic light does. One kernel and one knob fewer: `ChromeRadius` is GONE, and
  the settings-table test made that impossible to forget.
- **Vibrancy aimed at the minimum contrast, which looks blurry.** **FIXED in the source
  (2026-10-14), waiting for the next build.** Aiming at exactly the threshold produced a
  MID-GREY glyph on a mid-grey glass, and the user described the symptom before the cause: "el
  texto como que es borroso o se ve de mala calidad". macOS does not aim, it FLIPS the content
  -- near-white on a dark material, near-black on a light one -- and so does this now, over a
  short ramp (a quarter of the threshold) so that a moving backdrop cannot flicker it. This is
  the third version of that function: mixing by the shortfall overshot and undershot, aiming
  undershot in the case the knob exists for, and aiming is also the wrong *idea*.
- **Transient lines inside the bar while a window moves.** **State: hypothesis, not fixed.**
  The frost kernel reaches up to `BackgroundRadius` (16-24 px) beyond the fragment while the
  capture extends only the decoration's shadow margin (7 px) beyond the frame, so the samples
  above the capture's top edge are clamped by the sampler and repeat its last row -- a smear
  that changes as the window moves, which is the shape the user described ("lineas que aparecen
  y desaparecen con el movimiento"). The other candidate is the capture itself: it reads the
  live framebuffer, so during a move it can contain the window's own previous pixels. The
  decisive question is WHERE the lines are -- at the band's top edge points at the sampler
  clamp; anywhere else points at the capture. Two fixes exist for the first (capture a region
  enlarged by the frost radius, which needs the uv transform that `CaptureSubRect` already
  builds, or make the frost kernel anisotropic) and neither is free.
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
  does not, the fix is to pass the texture's own size and the margins as uniforms -- **and
  that fix is in the build now, behind a live switch**: `CaptureSubRect` (default FALSE). Off
  sends the identity, which is exactly the sampling that was verified before it existed; on
  samples the frame's sub-rectangle inside the capture. Both are stable, so the procedure is
  an A/B rather than a guess: with `BackgroundRadius=0` and text behind the window, run
  `measure-alignment.py` with the key false and then true, and the value that reports
  `(0, 0)` is the true reading. The switch exists so that answer costs no extra build.
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
  *(Retired to `tests/archive/` on 2026-10-14, together with `test-hot.sh`, `calibrate.sh`
  and `test-diffusion.sh`: the first three could no longer say anything and the fourth
  measured a design that is gone.)*
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
| **M1.3a step 3b** — alpha, and the frame-vs-expanded geometry | ✅ **CLOSED (2026-10-14)**: `CaptureSubRect=true` is confirmed ON SCREEN by the user ("me agrada esta opcion"), which settles that `vTexCoord` runs across the FRAME and the capture -- expandedGeometry, frame plus shadow margins -- must be sampled at the frame's sub-rectangle. The arithmetic is in 9m |
| M1.3 refraction (70) | ✅ **approved on screen** (2026-10-14): the bend is applied to the frost's own uv, so the band is one material. `Refraction` 20 |
| M1.4 dispersion (20) | 🟡 measured, not built: 0.5 levels at the kit's ratio, three frosts to build (see 9l) |
| M1.5 specular highlight | ⬜ next candidate; the rim has a small white lift, not a specular |
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
| ~~`measure-diffusion.py`~~ | RETIRED: answered that for a design that took its blur from the window's own texture. In `tests/archive/` |
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
   `tests/archive/test-installed.sh` and `tests/archive/test-hot.sh`, and the suite
   never runs them.
3. **The `.pass-count` cache was a race.** No: `run.sh` writes it and nothing reads
   it -- no test, no tool, no doc, and it is git-ignored. It stays as a convenience
   only.

### The contamination was real, it just was not the cause

Sourcing every test file into one shell did leak state, and that was measured, not
deduced: `tests/test-offscreen.sh` sets `CABECERA`, and with the old runner that
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

## 9b. What Apple's material actually does, measured from the user's own samples

The user pointed at `muestras/Untitled5.png` -- a macOS Dock -- and described it better than any
document: "el dock tiene como un borde, no es directa la transparencia, y este toma el color del
background pero lo hace mas fuerte". Both halves are true, and the numbers say so.

**It is not a blend.** Sampling the dock over two different parts of the wallpaper:

| | backdrop (above the dock) | dock |
|---|---|---|
| A | (52, 84, 141) | (191, 194, 208) |
| B | (9, 31, 128) | (122, 146, 211) |

A plain `dock = a * colour + (1 - a) * backdrop` with one material colour gives
`(1 - a) = 1.6` from those two points: greater than one, which is impossible. The dock's colour
tracks the backdrop with a GAIN of about 1.6 -- the material amplifies what is behind it instead
of veiling it. That is the opposite of what this effect does today, and it is why a quarter-opaque
white veil looks like grey plastic next to Apple's glass.

**And it has a rim.** The vertical profile over the dock is bright bands at the top
(215-236) and at the bottom (206-218) with a darker middle (168-190). That is the edge treatment
the user saw as a border.

**What that means for the roadmap**: this is exactly the unimplemented half of the kit --
`refraction = 70`, `dispersion = 20`, the specular highlight -- and the measurement is the shape
of the work: a colour/luminance term that amplifies the captured backdrop, and an edge highlight
tied to the window's silhouette. Neither is a knob on the existing blend, and pretending otherwise
would be the mistake this project keeps having to unlearn.

**The halo, meanwhile, was vibrancy and is fixed.** Its pixels measure 206-217 against a band of
117 and a theme bar of 246: the installed version's `backdrop + 0.35` predicts 219 exactly. The
cause is that the anti-aliased edge of a coloured button is only PARTLY saturated, so the
achromatic test let those edge pixels through and vibrancy pushed them to a light grey. The gate
is `isColour > 0.15` now instead of `> 0.5`.

## 9c. The colours of adapted content are Apple's, from Apple's tokens

The user asked, before installing, whether the chrome's colour adaptation was right: "el texto
cambia de color, de blanco a negro dependiendo del fondo... creo que apple usa un gris obscuro,
no estoy seguro". They were right, and the exact value was in their own tokens:

```toml
[label]         primary = { light = { hex = "#000000", alfa = 0.85 } }   # a VEIL: black at 85%
[label_vibrant] primary = { light = { hex = "#1A1A1A", alfa = 1 }        # opaque, and the one
                            dark  = { hex = "#F5F5F5", alfa = 1 } }      # a material needs
```

The kit has both, and the distinction is the whole answer: `[label]` is a veil composed over a
background, while `[label_vibrant]` is OPAQUE -- which is what content on a material is. So the
flip targets are **#1A1A1A** and **#F5F5F5**, not black and white.

The theme's own text colour was `#404040`, which is `[label_vibrant] tertiary`, and it is now
`#1A1A1A` (the vibrant primary) with `#727272` for the inactive title (vibrant secondary). The
effect still samples whatever the theme draws, so the two changes compose: a dark-grey title on a
light material, and the same title flipped to near-white when the material goes dark -- which is
Apple's behaviour and, in their tokens, literally written down.

## 9d. The rim and the amplification are implemented, from that measurement

Section 9b measured what Apple's material does; this is the first cut of doing it.

- **`Rim`** (default 0.20): a two-texel highlight along the band's four edges, computed from the
  frame's own rectangle and from the title bar's height, which is where the hairline goes that
  macOS draws between the bar and the content. The measured reference is bright bands of 215-236
  (top) and 206-218 (bottom) around a middle of 168-190, so 0.20 is deliberately subtle.
- **`MaterialBoost`** (default 1.20): the backdrop's chroma around its own luminance is
  multiplied by this before the bar's tone is mixed in -- the gain that a plain blend cannot
  produce. **1.0 turns it off and the value measured on Apple's Dock is 1.6**, so the knob's
  range is the honest one: the default sits below the measurement, and the measurement is written
  next to the knob.

Neither is the whole of `refraction = 70` / `dispersion = 20` / the specular highlight, and
section 9b says why: those bend and displace what is behind the glass, and these two only boost
and outline it. They are what the measurement supported, no more.

**And the language pass caught its own author.** The first version of this change used `salida`,
`cromo` and `desdeArriba` -- Spanish names, in a repository whose agreement is English and after
a commit that had just renamed exactly those identifiers. The shader failed to compile and two
assertions failed with it: the tests, not the habit, are what keeps that agreement.

## 9e. Three corrections the next screenshot forced, and one wrong RULE

- **The halo was never vibrancy; it was the theme's own anti-aliasing.** The theme draws a
  button against ITS white bar, so the boundary pixel is a mix of the button's colour and
  #F6F6F6 -- a white fringe baked into the texture, which no compositing can remove. Classifying
  it as chrome painted that white over our glass, one pixel wide, around every light. The chroma
  term is `smoothstep(0.15, 0.30, ...)` now instead of `(0.06, 0.15)`, so the fringe stays glass
  and the button's edge dissolves into the material while the saturated interior still passes.
  The earlier vibrancy gate was a real bug too, but it was the second cause, not the first.
- **The rim was the wrong SHAPE.** Ours was a two-texel white line and the user's verdict was
  exact: "el de apple es mas grueso y se adapta al color del background, el nuestro es una simple
  linea fina delgada blanca". Apple's edge is **refraction** -- the glass bends what is behind
  it -- which is why the measured bands are thick and take the backdrop's colour. The
  approximation is now the AMPLIFIED backdrop over a 5-texel falloff with a small specular lift,
  and section 9b still says what is missing: true refraction displaces the sample
  (`refraction = 70`), which is the next milestone rather than a knob on this one.
- **Vibrancy's rule was wrong, not its value.** The user: "el texto es blanco, estamos en tema
  claro por lo que el texto deberia ser obscuro". Deciding the content's colour from the
  MATERIAL's momentary luminance means a light theme over a dark wallpaper gets white text.
  macOS decides it from the APPEARANCE (light/dark mode) and gives the material its own
  lightness. That is the design to grow into, and it needs the colour scheme rather than the
  glass, so it is not this knob: **`Vibrancy` is off by default again**, the theme's own text
  colour wins, and the knob stays for whoever wants the flip.

## 9f. Iterating without a relogin: simulate.py

The user asked for it in as many words: "habria forma de que automatices todo esto para no
reiniciar y puedas comparar vs lo que tenemos de apple". Every idea in this session had cost a
build, an install, a logout and a login, which is why three defects in one mechanism survived
three rounds. `effect-kwin/simulate.py` ends that: it implements the band's arithmetic in numpy
-- the frost over the reduced capture, the vertical median tone, the coverage estimate, the
mixes, the amplification and the rim -- and reproduces what the effect will do from two
screenshots: the title strip with the effect OFF, and the same region of the desktop with the
window out of the way.

It earned its keep on the day it was written. The first version of the coverage ramp used
`uChromeLow + 0.25`, and `--self-test` showed a half-covered glyph edge coming out at **1.00**:
the white fringe would have survived the fix meant for it. The ramp is `+ 0.85` now and that same
pixel measures **0.43**. Seconds, not a session.

`--self-test` is in the suite, so the model cannot drift from the shader, and it checks the three
things whose answer is known by definition: alpha 0 gives the frosted backdrop, alpha 1 gives the
bar's tone, and a glyph's half-covered edge must be PARTIAL rather than crisp. Its knob defaults
are read from `src/glass.h`, for the same reason the settings table is a test.

## 9g. The simulator's own inputs are a script, not a procedure

The user ran `simulate.py` and got a `FileNotFoundError`: the usage text described the two captures
it needs and gave no command to produce them. That is the same defect as a knob nobody can reach.

`effect-kwin/capture-pair.sh` takes both in one command:

1. reads the band's rectangle from the effect's own journal (`frame=` and `barHeight=`), which is
   the rectangle the band actually covers;
2. unloads the effect -- the capture that must show the THEME cannot show the glass -- waits, and
   captures the screen;
3. waits for the window to be moved away from that rectangle, and captures again;
4. crops both to the same strip and reloads the effect in a trap, so an interrupted run does not
   leave somebody without their glass.

`simulate.py` says that instead of a traceback when an input is missing, and the script is in the
suite's list with the properties that matter: it unloads, it loads again, the trap restores on
interrupt, the rectangle comes from the journal, and both crops are the same strip.

## 9h. The capture pair: fresh geometry, and an unload that is checked

The user ran `capture-pair.sh` successfully and the simulation "looked convincing" -- and it was
wrong twice, in ways worth writing down because both would have fooled anybody.

**The geometry was stale.** The script read the band's rectangle from the effect's journal, which
can be an hour old. It was: the crop landed on a window that had moved since, so "the theme's
strip" was the desktop and the backdrop was something else again. The mean colour gave it away --
the strip measured 55, a title bar of this theme is near white -- and the simulation matched it to
within three levels, which is exactly how a self-referential result looks convincing. The geometry
now comes from KWin's scripting for the **active window**, at the moment of the capture, the same
"x,y,w,h,bar" route `test-titlebar.sh` uses.

**The unload was assumed.** `unloadEffect` can be refused, and a capture taken with the effect
still loaded is the effect's OUTPUT, not its input. The script now asks `isEffectLoaded`, falls
back to disabling the plugin through `[Plugins]` (which KWin does honour, via `/KWin reconfigure`),
and refuses to capture if neither works -- because a self-referential capture is worse than no
capture: it produces a simulation that proves nothing and looks right.

One structural lesson, again: the `--geometry` test mode and the capture now share ONE parser, so
a test of the parse is a test of the step that runs. The version before this tested a parser the
capture did not use, and the capture failed on every run while the test passed.

## 9i. The gain, and the first measurement of our own material with real inputs

With a TRUE capture pair -- 905x38, geometry from the active window, the unload verified -- the
numbers finally describe our material instead of a stale crop: backdrop luminance 61, the theme's
bar 237.5, and the simulation reproducing a band at 107.6.

That is a VEIL: `0.75 * backdrop + 0.24`, both terms below the backdrop. Apple's Dock measures
`1.6 * backdrop + 0.42`. `MaterialGain` is that gain as its own term now, applied to the frosted
backdrop before the bar's tone is mixed in, so the material's amplification and its lightness can
be set independently. **1.0 reproduces exactly the behaviour before it existed** and **1.6 is what
the sample measured**; it was demonstrated in `simulate.py` first, which is what that tool is for:

| | luminance | deviation | chroma |
|---|---|---|---|
| the captured backdrop | 61.0 | 9.5 | -- |
| gain 1.0 (off) | 107.6 | 14.7 | 35.8 |
| gain 1.6 (Apple's) | 134.9 | 19.7 | 55.5 |

A third of a stop brighter and half again as chromatic, which is the user's own description of the
Dock: "toma el color del background pero lo hace mas fuerte".

**Known and next**: `clamp(desktop * gain)` clips hard above 0.625, so a bright backdrop will
blow to white rather than brighten smoothly. Apple's material is tone-mapped there, not clipped.
That is a soft knee, and it is the next thing this term needs.

**And the language habit is a test now.** The language pass renamed 133 identifiers and I relapsed
four times afterwards (`salida`, `cromo`, `desdeArriba`, `amplificado`), every time in a patch
written from memory. `tests/test-glass.sh` scans the effect's identifiers against a curated Spanish
word list, the same shape as the file-name scan in `test-claims.sh`. Checked by putting
`amplificado` back: it named it.

## 9j. "El centro esta blanco y la orilla translucida" is a TRADE, not a bug

Measured on the user's own screenshot with a local-variance map, once the gain's knee and the bend
were both in the installed build: **20.8% of the band is a flat, light slab** -- rows 29..44 of a
38-row bar, columns 61..943, level 149, and constant. It is not a defect with a line of code behind
it. It is the two things they asked for pulling against each other:

- The **centre** is the *frosted* backdrop. At radius 16-32 the frost averages the wallpaper's wide
  stripes away, and what is left is the material itself: the theme's white bar at `GlassAlpha`
  (0.25 of a *white* bar is a lot of white) over an amplified backdrop. Uniform, therefore a plate.
- The **edges** mix in the *unfrosted*, displaced backdrop -- the bend -- so the stripes come back.
  That is why they read as MORE translucent, in the user's words, than the middle.

So "the edge looks more translucent" was the symptom of the centre being too frosted, and the two
requests -- "30% more blur" and "the centre is a white square" -- sit at opposite ends of
`BackgroundRadius`, `GlassAlpha`, `MaterialGain` and `RimWidth`.

HONEST ABOUT THE INSTRUMENT: I tried to predict the right values in `simulate.py` and my synthetic
wallpaper was useless for it -- stripes ~190 px wide are not smoothed by a 16-32 px frost, so it
reported the same structure at every radius. The numbers below are what it CAN say, and the choice is
a screen judgement with `tune.sh`:

| | centre's mean level |
|---|---|
| `GlassAlpha` 0.25 (now) | 153.9 |
| `GlassAlpha` 0.15 | 148.6 |
| `GlassAlpha` 0.08 | 145.0 |

Lowering `GlassAlpha` is the direct lever on the plate, because it is the theme's white bar that
fills it. The kit's `opacity = 25` assumes the material has its OWN colour; using the theme's bar as
that colour is an approximation of mine, so 0.25 is not sacred and this is where to look first.

## 9k. Approved on screen, and how to know nothing was lost

The frosted rim was the user's own idea, asked as a question -- "que pasaria si le dieramos el valor
escarcha a la orilla pero manteniendo la refraccion" -- implemented the same day, and then approved
where it counts: "hice el install y se ve increible, estoy contento con el resultado". So the design
that ships is: ONE frost for the whole band, its uv bent toward the interior near the edges, with a
hairline of contrast at the outermost row and the gain's soft knee above mid grey.

**How to know the repository matches the screen.** The build the effect was approved on and the build
in the tree are the same file, checked by content and not by timestamp:

    md5sum /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so   -> 334d88c7
    md5sum effect-kwin/build/plugins/kwin/effects/macosglass2.so      -> 334d88c7

The defaults are the user's choices, with their reasons next to them: `CornerRadius` 20,
`Refraction` 20, `Rim` 0.30. A `--reset`, a clean install or another machine lands on what they
picked by looking.

WHAT IS STILL NOT DONE, said plainly so the next session does not have to rediscover it:

- `dispersion = 20` and the specular highlight from the kit are not implemented; the edge bends
  colour but does not separate it per channel.
- The last M1.3a box is the alignment measurement that was stopping on the `CaptureSubRect`
  question -- whether `vTexCoord` spans the expanded texture or the frame. Corner rounding landing
  correctly at radius 20 is evidence for the frame reading, and `CaptureSubRect` exists so the
  answer costs one setting rather than one build.
- `tools/*.py` and `tokens/` still carry Spanish variable names. The effect's identifiers are guarded
  by a test now; those two are not.

## 9l. The kit's last figure, measured before it was built

`dispersion = 20` was the only thing left in the kit unimplemented, and it took an hour to decide
not to implement it -- because the simulator could answer the question first. Modelled as the ratio
the kit implies (20/70: red bent furthest, blue least), and measured on a GREY high-contrast
backdrop, where the material cannot produce colour by itself and any red-blue separation in the
output is the dispersion and nothing else:

| | red minus blue at the rim |
|---|---|
| dispersion off | **0.0 levels** (the control, exact) |
| dispersion 0.29, the kit's ratio | **0.5 levels mean, 9 maximum** |

At Apple's own value the effect is below the perceptible level, and the reason is the rule the edge
already taught us: a 6 px separation between channels does not survive a 16 px frost. Making it
visible would mean a separation comparable to the radius, and in the shader that costs THREE frosts
per pixel -- the band's 36 taps become 108. So it is not built, it is measured, and the measurement
is a test: a grey backdrop must stay grey with dispersion off, and the kit's value must stay subtle.
If a future session wants the fringing for its own sake, the model is in `simulate.py` and the cost
is now a known number rather than a surprise.

## 9m. The frame-vs-expanded question, answered from the arithmetic (and why the eye could not)

The user ran `./tune.sh CaptureSubRect=true` and `=false` and reported "no veo o no percibo
diferencia". That is the correct observation, and it does not mean the setting is a no-op:

- the capture covers KWin's offscreen texture = `expandedGeometry()` = frame PLUS shadow margins. The
  user's own journal prints them: `shadowMargin= QPointF(14, 2)`;
- every size the shader uses comes from the FRAME, which the rounded corners prove: arcs built from
  the frame's box land exactly on the window's corners, at radius 20, on a 4K panel.

So `false` (the identity) maps the capture onto frame coordinates: **14 px of horizontal offset, 2 px
vertical, and a 2% scale** (1415/1387) that drifts to roughly 28 px at the far edge. Invisible
through a 16 px frost over a smooth backdrop -- and visible in one second over structure with the
frost off:

    ./tune.sh BackgroundRadius=0 CaptureSubRect=false   # TEMPORARY, see the warning below
    ./tune.sh CaptureSubRect=true                       # aligned
    ./tune.sh --reset                                   # back to the approved look

WARNING, from the user's second run: `BackgroundRadius=0` means ZERO frost, so "se ve todo el texto de
atras completamente" -- every letter of whatever is behind the window becomes readable. That is the
sharp end of the knob working as designed, and it is NOT a state to stay in. The user stopped before
the `--reset` and asked for their settings back, correctly.

THE NON-DESTRUCTIVE WAY is `measure-alignment.py`, which was written for this question and reports
(0, 0) for whichever sampling is true without changing how anything looks. It needs the capture pair
from `capture-pair.sh`. For a question already answered by the arithmetic and confirmed by the eye,
that is the better instrument, and it should have been the first suggestion rather than the last.

`GlassAlpha=0` was in the first version of that recipe and it was a bad ingredient: it means ZERO
material, so the bar becomes a transparent pane with no effect at all -- "todo se vio completamente
transparente", in the user's words, and they did not like it. Sharpness is what the test needs, not
the absence of glass. What saved the session from a half-applied mess was the all-or-nothing
validation: the command that failed on `CaptureSubRect=false` wrote NEITHER of the other two keys,
which is exactly the reason that rule exists.

The default is `true` now, decided on that arithmetic rather than on a preference. The switch stays
because a future session may want to re-check it on hardware this one never saw, and because
`measure-alignment.py` reports (0, 0) for whichever is the truth.

## 9n. M1.3a is closed, and the recipe that nearly cost the user their settings

The user ran the two settings and reported: "me agrada esta opcion" for `CaptureSubRect=true`, and for
the sharp version "hizo que todo se viera completamente transparente y no me gusto". Their `kwinrc`
settles what happened and it is the best evidence for the all-or-nothing rule: the ONLY key written
that day is `CaptureSubRect=true`, because the command that carried `BackgroundRadius=0 GlassAlpha=0`
failed on the boolean and therefore wrote NOTHING. Two settings I had told them to use were never
applied -- the validation rule that was written for a different reason is what prevented a
half-applied material.

So M1.3a's last box is closed: `vTexCoord` runs across the FRAME, the capture covers the expanded
geometry, and sampling the frame's sub-rectangle is the truth. The default in `glass.h` is `true` and
the switch stays for hardware this session never saw.

And the recipe is fixed. `GlassAlpha=0` was a bad ingredient -- it means ZERO material, so the bar
becomes a transparent pane with no effect, which is not a sharper version of the glass but the absence
of it. Sharpness is what the test needs: `BackgroundRadius=0` alone keeps the material and shows the
offset.

## 9o. M1.5: the kit had the numbers, and the tool was lying about where they were

The specular highlight is done, and it needed no invention. `[liquid_glass]` had TWO keys this
project had never used: **`light_angle = 0`**, the direction of the light source, which puts the
reflection at the top; and **`splay_regular = 20`**, its spread -- about 6 px at the same scale that
maps `refraction = 70` to 20 px, which is exactly the bright band measured on the user's Dock (12
rows at 2x). The strength comes from that sample too: its upper band sits 56 levels over the middle
and its lower one 26.

Three things had to be right before the numbers landed, and two of them were bugs of mine:

1. **Order.** With the specular in front of the hairline, the line clipped 35% of it: a weight that
   the arithmetic said would lift 49 levels lifted 23.5. A reflection is the outermost thing that
   happens to a surface -- material, edge line, then the light bouncing off it -- and now it is last.
2. **The cap.** `clamp(specular, 0, 1)` cannot express this: 1.0 means "all white", so no weight at all
   could lift a mid-grey edge to Apple's 236 over a middle of 180. A specular is the SATURATED image
   of the light source; the weight goes to 2, and `tune.sh` caps the knob there.
3. **The simulator was reading the wrong header.** `HEADER = "src/glass.h"` resolved only from
   `effect-kwin/`; from anywhere else the open failed, an `except OSError: pass` swallowed it, and
   every knob silently fell back to the hardcoded number beside it. That produced three contradictory
   measurements in a row while the header said 1.3 and the tool used 0.75. It is anchored to
   `__file__` now and a header it cannot read is LOUD. A default that depends on where you stand is
   worse than no default.

Measured, on a dark backdrop, against Apple's own bands:

| backdrop | upper band | lower band |
|---|---|---|
| dark (0.35) | **+55.6** (Apple: +56) | **+18.4** (Apple: +26) |
| mid (0.60) | +14.8 | +6.1 |
| light (0.85) | **+1.5** | -4.7 |

The upper band matches Apple's measurement almost exactly and the fade over a bright backdrop is the
physics working: adding light to something already bright is invisible. The lower band is short --
18.4 against 26 -- and the cause is structural rather than a value, because the bottom edge's baseline
is not the top's. Recorded rather than papered over.

The two new tests keep it honest: the acceptance bands are asserted (45..66 and 18..34, with the fade
under 8), and so is the anchoring, by comparing the default read from two different directories.

## 9p. A wrong decision corrects itself, and the bug that hid it was the same one

Section 9l concluded that the kit's dispersion was "below the perceptible level" and deliberately not
worth building. That conclusion was measured, tested and wrong. The dispersion is a FRACTION of the
bend -- `shift * (1 ± dispersion)` -- so its visibility moves with `Refraction`, and 9l measured at the
default of the time, 6 px, where the red-blue separation is 9 levels. At the current 20 px it is
**31.9**, which is colour you can see.

Two things hid it, and one is the bug from 9o: the simulator's `HEADER = "src/glass.h"` resolved only
from `effect-kwin/`, so when the default changed and a measurement was taken from the repository root,
the tool quietly used the old hardcoded 6 while the effect used 20. The same silent fallback that cost
three contradictory measurements in 9o also protected a wrong decision from being re-examined.

The test that replaces the old one asserts the SHAPE rather than a value, and my first version of it
was wrong too: I asserted that the separation scales in proportion to the bend, and it does not -- 17.9
at 6 px against 31.9 at 20 px is a factor of 1.8 where the bend grew by 3.3. The bend is applied to the
frost's uv, so a wider displacement is compressed by the same 16 px frost that smooths everything else,
which is a rule this project has now met from four different sides. What the test asserts is what is
true: a grey backdrop stays grey, a 6 px bend already fringes visibly (17.9 levels, not the 9 that 9l
recorded with the specular suppressing it), and a larger bend fringes more but sub-linearly.

So the dispersion moves from "not worth building" to "worth building, and there is a cheap shape for
it": since the bend lives in the frost's uv now, the fringe can come from three fetches of the
already-reduced capture -- one per channel -- instead of three full frosts. That is M1.4's next move,
and it exists because a wrong answer was found to be wrong.

## 9q. M1.5 was built, measured, and is OFF: the edge carries the ENVIRONMENT

The user stopped it with the observation that decides the term: "creo que hay una confusion, lo que
hiciste es una linea blanca, pero en apple no es color fijo, toma del entorno los colores. Observa
Untitled4.png, la linea superior tomo el color predominante de la parte inferior de lo que habia bajo
el dock, en este caso el background y la linea inferior tomo el color de lo que habia arriba."

They are right, and their own sample proves it: against that edge there are rows of unambiguous blue
(129, 150, 186), not white. The colour comes from the backdrop OPPOSITE the edge -- below for the top
band, above for the bottom -- which is what a glass bevel does with light bent around it, and which is
exactly what the refraction term already samples (it displaces the frost's uv toward the interior, so
the top band shows what is below). A fixed white line does not add to that; it DESTROYS it.

So `Specular` defaults to 0. The measurement behind it was sound -- 1.3 reproduced Apple's upper band
to within half a level -- and it was a correct measurement of the WRONG THING, which is a failure mode
worth naming: eleven commits of arithmetic cannot tell you that the quantity is not the one the
reference uses. What found it was the user's eye, again, and a sample this project had already
measured twice without looking at its COLOUR.

The token is re-read with it: `splay_regular = 20` is the SPREAD OF THE REFRACTION, not the width of
a white highlight. That misreading is what the whole term was built on.

M1.5 therefore closes as a negative result with a knob attached: the highlight is available, off by
default, and the edge's colour behaviour is the refraction's job -- which is where the user's
description points.

## 9r. The term Apple actually uses: the edge carries the environment's colour

With the white specular off, the user's reading of Apple's material became the work: "toma del entorno
los colores... la linea superior tomo el color predominante de la parte inferior de lo que habia bajo
el dock, y la linea inferior tomo el color de lo que habia arriba". Their sample agrees -- the band at
that edge is a clear blue, chroma 57, where its surroundings sit at chroma 1.

The mechanism was already there and was not doing enough: the refraction displaces the frost's uv
toward the interior, so the band DOES sample the backdrop opposite the edge, but the frost averages
that colour and the soft knee compresses it. Measured, the band arrived at a chroma of **35.1** against
an interior of **34.2** -- the same colour, which is precisely what the user was reporting.

`RimColour` multiplies the BAND's chroma around its own luminance, and nothing else:

| `RimColour` | band chroma | interior |
|---|---|---|
| 1.0 (as the frost delivered it) | 35.1 | 34.2 |
| 1.4 | 39.7 | 34.2 |
| **1.8 (default)** | **44.2** | 34.2 |
| 2.6 | 52.4 | 34.2 |

The middle of the bar does not move, which the test asserts, and the term is a knob because the
amount is a screen judgement like every other one in this file.

Two lessons landed together here, and they are the same lesson: MY MEASUREMENTS WERE RIGHT AND THE
QUANTITY WAS WRONG. The white specular was calibrated to half a level against a number that Apple's
edge does not use, and the refraction was carrying the environment's colour at the exact strength of
the interior, which is to say invisibly. Both were found by the user looking at a sample, and both
would have passed any amount of arithmetic.

## 9s. Three faults in one report, and only one of them was where it looked

The user set `RimColour=2.6` and reported "se arruino... toda la linea se volvio blanca", still white
after setting it back to 1.0. Three separate things were behind that, and none of them was `RimColour`:

1. **The white line was `Specular=2`, set by the user on MY advice.** The message before this one
   listed `Specular=2` among the knobs to try -- a stale suggestion for a term whose whole point had
   just been retracted, and which is a fixed white highlight BY DESIGN. The knob is off by default and
   labelled as not-Apple in the README; the failure was in the advice, not the code. Their `kwinrc`
   showed it plainly: `Specular=2`, `SpecularWidth=12`, `RimColour=1.2`.
2. **`RimColour` could blow out**: at high values the channels overshot 1, clamped, and the band went
   white. A knob that can turn the edge into a white line is broken whatever its range reads, so the
   boost is limited PER PIXEL to whatever keeps the strongest channel inside the display. Measured
   after the fix: 1.0 -> chroma 29.1, 1.8 -> 36.5, 2.6 -> 43.0, and 6.0 and 20.0 give exactly 43.0.
   The colour grows and stops; it cannot brighten.
3. **The journal was missing `rimColour`**, because one of my edits -- the log field -- silently did
   not apply while the other three did. I read that absence as "the uniform is never set, so the band
   is grey" and was wrong: the plumbing was complete. A diagnostic that omits a field is a diagnostic
   that lies, and this one lied to me within a minute of my writing it.

The pattern worth keeping is the third one. Three times today a multi-part edit of mine applied in
part: the header without the shader, the body without the signature, and now the plumbing without the
log. Every one was caught by a grep rather than by the patch reporting success, which is why the
verification step exists.

## 9t. The bright fillet IS there, and my first measurement could not have seen it

9q turned the specular off on the user's first reading -- the edge carries the ENVIRONMENT's colour --
and 9s made a knob that cannot blow out. Then the user looked again and asked the question that put it
back: "observa la de apple, pareciera que tuviera tambien un filo blanco en medio de esa linea
exterior no crees".

They are right, and the structure is BOTH things at once. Measured row by row on their own sample,
the dock's top edge from outside in:

| rows | reading | logical width |
|---|---|---|
| 279-285 | the environment's colour (129, 150, 186: chroma **57**) | ~3.5 px |
| 288-291 | a sharp bright neutral rise (196 -> 213 -> **219**) | ~2 px |
| 292-309 | the body, bright and neutral (222, chroma ~2) | ~9 px |

So: a coloured band AND a narrow bright fillet on top of it. The first `Specular` was the right idea
with the wrong geometry -- 6 to 12 px wide and REPLACING the colour instead of sitting on the band.
It is 0.7 at a width of 2 px now, and the simulated structure reproduces the sample's: row 0 rises
from 146 to 177 while its chroma FALLS from 39 to 28, and the coloured rows behind it do not move.

WHY I COULD NOT HAVE SEEN IT. The first pass over this same image sampled every third row and averaged
600 columns, which is a filter that deletes a two pixel line and reports the average of its
neighbours. I said at the time that the sample "shows clear blue, not white" -- true, and incomplete,
because the question I asked of the data was about a BAND and the answer was about a LINE. It is the
same failure as the one in 9r and 9s, in a third costume: measuring the wrong quantity, and this time
the quantity was wrong because the RESOLUTION was.

## 9u. Runbook: the effect took the windows away

The symptom, in the user's words: "perdi las ventanas, solo se ve la barra superior, no puedo ver nada
literal, solo el desktop y las barras de la ventana superior". If it happens again, this is the way out,
and it needs no relogin and no working screen -- it runs from any shell on the machine:

    export XDG_RUNTIME_DIR=/run/user/$UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass2
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass2   # must print false
    # and make it stick, in case a reconfigure loads it again:
    kwriteconfig6 --file kwinrc --group Plugins --key macosglass2Enabled false
    qdbus6 org.kde.KWin /KWin reconfigure

TWO BUGS, one behind the other, and both mine:

1. `discard` tested `min(edgeDistance, uTitleBarHeight - topDistance)`. The second term is NEGATIVE for
   every pixel below the bar, so the effect discarded the entire content of every window and left only
   the title bars. The bar's bottom belongs to the BAND's geometry, not to the shape of the window; it
   was conflated with it one commit earlier, when the corner distance was unified. Fixed by testing the
   frame's rounded distance alone.
2. That unified distance then had its SIGN inverted: `uCornerRadius - (sdf - uCornerRadius)` is the sdf
   mirrored about r -- positive everywhere near a corner -- so the discard never fired there and the
   corners came back SQUARE, with a +20 px bias on every edge term. The simulator had the correct
   expression and the shader did not, so their numbers never disagreed while their shapes did.

RECOVERY AFTER A FIX, which worked here and is worth remembering: `unloadEffect` then `loadEffect`
picked up the newly installed library with no relogin. If it does not, the tell is the SHAPE -- corners
square again -- and a relogin is the guaranteed path, because the plugin stays enabled and the disk has
the fix.

**AND IT FAILED A THIRD TIME (2026-10-15, audit 1).** The install landed at 15:17:08, the hot path
re-created the effect at 15:18:01 (`M1.2 loaded` in the journal), and the library that ran was still
the OLD one: the capture texture read `QSize(466, 381)` -- `933x762`, the whole expanded window --
where the new band code had to produce `QSize(466, 42)` from `933x84`. The unload/load DOES create a
new instance; what it did not do is re-read the file. A relogin fixed it on the first try. **The tell
is now cheaper than the shape: the `capture texture QSize(...)` line names the library.** Check it
before believing a hot reload, and do not conclude that new code is broken until it has been loaded.

FOUR TESTS came out of this, and none of the previous ones could have caught either bug: the discard
tests the frame's distance alone, the bar's bottom appears only in the band, the retired expression is
gone by name, and the rounded distance is checked numerically -- negative at the corner, exact inside a
straight edge. The content path never reaches the maths this suite can exercise, so the SHAPE of the fix
is the strongest check available, and it is now in place.

## 9v. The audit, and what is queued from it

An independent read-only audit of `effect-kwin/` (subagent, no files touched) measured where the cost
actually is and ranked the margin. Its verdict: **the shader is not the problem** -- the bar costs 42
taps per fragment with uniform branches, and the 36-tap frost is a measured decision -- while **the
capture is**: one blit of the window's `expandedGeometry` (3840x2160 for a maximised window) plus an
unconditional full-texture clear, per window per repaint. Roughly 31.6 MiB read + 8.0 MiB written +
8.0 MiB cleared, where the band needs 3800x38 plus the kernels' reach.

DONE IN THIS PASS -- the four simulator drifts, which could not affect the screen and mattered most
because a tool that predicts wrongly is worse than no tool:

1. it kept the white lift `* 0.15` that the shader retired when the fillet replaced it;
2. it gated the hairline and the fillet on `rim_strength > 0`, which the shader applies regardless;
3. it keyed the tone's radius to `BackgroundRadius` instead of `max(FrostRadius, barHeight/2)`;
4. it bent per axis instead of normalising, giving a corner sqrt(2) times the displacement.
Plus a fifth the audit did not list and that I found while fixing them: the block SHADOWED the rounded
distance with a box one, which is the same defect that made the corners square in the shader. The two
implementations now name the same quantities and the self-test compares the interior rows only, because
the edge terms are unconditional now and have their own tests.

QUEUED, with the audit's pointers, in its own order of impact x effort:

| # | finding | where | effort |
|---|---|---|---|
| 1 | **capture only the band**, not the whole expanded window (~30x less traffic, the real win) | glass.cpp:912, 923, 1042 | high |
| 2 | gate the unconditional `glClear` on `destination.size() != reducedSize` (~20% of capture traffic) | glass.cpp:1036-1039 | low |
| 3 | drop `m_shader.reset()` on reconfigure: the GLSL has no config baked in and is recompiled on every `tune.sh` call | glass.cpp:738 | low |
| 4 | key the capture cache by window instead of size: an LRU of 4 is pessimal for a cyclic 5-window set | glass.cpp:992-1002 | low-med |
| 5 | bound the `static QHash<QString,int>` on captions in the paint path (the journal-flood class again) | glass.cpp:1167-1178 | low |
| 6 | the tests pin GLSL *spelling*, so cleanup breaks them while real drift passes | test-glass.sh:461, 470-484 | med |
| 7 | dead code: `deviation`/`byDeviation`, `kFrostOpacity`, `m_active` (never written, so the documented "effect off" path is unreachable), a duplicated luma and one re-fetch | glass.cpp:298-299, 254, 92 | low |
| 8 | 19 string-keyed `setUniform` per window per paint: cache the locations | glass.cpp:1200-1255 | low |

AN UPDATE (2026-10-15): **#1 is DONE and VERIFIED ON SCREEN.** `CaptureSubRect` now selects
the capture's EXTENT -- the band by default -- and the frame-to-capture mapping became mandatory in
BOTH modes, because its OFF was the known 14 px offset and could never be the identity again. The
FIRST cut of the band was `expanded width, from expanded.top to frame.top + barHeight + reach`, and
its top was therefore capped by the window's own 2 px shadow margin. Measured BEFORE the change:
Konsole `933x762 -> 933x84` (~9x), a maximised window `3840x2160 -> 3840x~126`.
Measured AFTER it, on screen: the journal reads
`capture texture QSize(466, 42) (1/2 de QSize(933, 84))` where it read `QSize(466, 381)`, and
`test-glass.sh` still returns **GLASS** -- the band moves 146.2 with the background, against a
threshold of 12, with `capture: ok=3000 refused=0`. The hot path did NOT pick the new library up and a
relogin did (see the runbook above: the `capture texture` size is the tell now).
**#2 was already done** in an earlier pass (the `glClear` is gated on
`destination.size() != reducedSize`).

**AND THE BAND'S TOP EDGE WAS STILL STARVED, which the user saw before the numbers (2026-10-15).**
Their report: the backdrop bends along the bar's BOTTOM and not along its TOP, "curves very straight
at a very right angle", the Apple effect lost. The cause is the FIRST cut above: capping the region at
the window's expanded geometry left only the theme's 2 px top shadow margin for the frost and the
refraction to read, so the top edge had nothing to bend INTO and clamped; below the bar there is the
client, so it bent freely. **The blit reads the RENDER TARGET -- the screen -- not the window's own
texture**, so the environment above, below and beside the window is capturable. The region is now the
FRAME plus `reach` on every side, clamped to the render rect (the environment runs out at the screen's
edge, and a blit outside the target is undefined). For Konsole that is `993x126` against the full
window's `933x762`. Apple's material samples the environment AROUND the window; this is the same, and
it makes the two edges behave alike.

**AND THE REST OF THE QUEUE IS DONE (2026-10-15).** #4: the cache key is `(window, size)` and the
bound went 4 -> 8, with a closed window's entries dropped -- "key by window" alone, as the audit wrote
it, would have served the OLD texture after a resize, so the size stayed in the key. #7: the dead code
is gone (`deviation`/`byDeviation`, `kFrostOpacity`, `m_active`, a duplicated `kLuma` and one
re-fetch), and two assertions that pinned the RETIRED expression were re-pointed at the live one --
they would otherwise have kept the dead code green while breaking the cleanup. #8: the names resolve
once through `GLShader::uniformLocation` and `setUniform(int, ...)`; the VALUES are still set per
paint, which is what that has to mean. #6: `afirmar_glsl` strips comments, removes ALL whitespace and
matches the pattern as a CONTIGUOUS literal, so a reformat passes while an operator change, reordered
tokens or a pattern living only in a comment fail (all four proven in `test-harness.sh`); 95 shader
assertions were converted, 19 of them from a NAME to the EXPRESSION that decides. #3 was already done
(`reconfigure()` does not reset the shader).

DO NOT TOUCH, per the audit, with its reasons: the 36-tap pyramid and the finest level's weight 6 (four
equal levels only killed 82.5% of the text contrast and the radius alone did nothing); the 5-tap vertical
median and the 9-exchange network (a mean or a horizontal sample brings the ghosting back); the content
early-out, the corner discard, the radius-0 branch, the downsample cap of 2 and the tone clamp; one
cache slot per `(window, size)` consumed in the same capture/draw pair -- the KEY changed in audit 4,
the consumption rule did not; the per-paint uniform VALUES (audit 8 cached their LOCATIONS, not their
values); and the GLSL as a string literal, because the glslangValidator check extracts it.

AND ONE DOCUMENTATION LIE the audit caught on its way out: README.md documents `CaptureSubRect` as
false while glass.h has it true, and the suite's default check skips non-numeric defaults, so it cannot
see it. That is the next thing to fix.

## 9w. The horizontal seam was the bend's direction, and a metric that flattered itself

The user, on a zoomed corner: "en la linea vertical derecha e izquierda, antes de que empiece la curva
se ve una linea horizontal justo en medio, se puede arreglar?". Yes, and the cause was the direction of
the refraction: it was `normalize(vec2(sign(fromRight - fromLeft), -sign(fromBottom - fromTop)))`, two
per-axis signs, and those flip where the top and bottom distances cross -- the middle of the bar. The
bend changed direction abruptly there and drew a seam. It is the GRADIENT of the distance now, which is
the true normal: along an axis on a straight edge, radial inside an arc, and the two agree exactly where
they meet, so there is nothing to see.

AND THE DISPERSION VERDICT REVERSES BACK. Fixing the direction meant re-measuring, and the measurement
was 2.0 levels at a 6 px bend and 5.7 at 20 -- where the previous pass, in 9p, had reported 13.1 and
30.7 and used that to overturn 9l's "below the perceptible level". The old metric was `|R - B|` in the
band, which on a coloured backdrop measures the BACKDROP, not the dispersion: the control already read
135.7 in the last attempt. The honest metric isolates the effect -- how far red moves MINUS how far blue
moves -- and with no bend it reads exactly 0.0. On that metric the dispersion is subtle after all, so
9l was right, 9p's reversal was wrong, and the error in 9p came from the same drifted simulator that
this pass put right. Two verifications of the same quantity disagreed because one of them was measuring
something else.

A TESTING LESSON, NOW THREE TIMES OVER: a test backdrop has to be able to SHOW the variable. A uniform
backdrop cannot show refraction (measured 0.0 and I blamed the model), a grey one cannot show dispersion
(every channel samples the same greys, so no red-blue difference can exist however far it is bent), and
a stripe-free one cannot show moire. All three were mine, all three measured something true about a
question nobody asked.

**AND THE SAME BEND INVENTED A DIAGONAL WHERE IT HAD NO GRADIENT (2026-10-15).** The user, on the
whole bar rather than a corner: "desde la parte superior todo en 90 grados y casi en la parte baja de
la barra se van a un angulo sin curvas hacia la derecha". The direction was
`normalize(gradiente + vec2(0.0001))`, and `gradiente` is the gradient of the FRAME's rounded
distance -- which is `(0,0)` in the interior of a flat edge, because the BAR'S BOTTOM is the BAND's
boundary and not a frame edge at all. The epsilon INSIDE the vector turned that zero into a fixed
diagonal, and the falloff is still on near the bar's bottom, so the backdrop was pushed down-right
across the lower half of the bar while the upper half (where `q.y > 0` gives a real vertical
gradient) stayed straight. **It was a drift the user SAW:** the simulator divides by
`max(length, 1e-6)` and a zero gradient there moves the sample by ZERO, so the two implementations
disagreed about where the material bends. The shader now matches the simulator and both are pinned.
Two hypotheses of mine died first (the corner smoothing, then the capture's reach) and neither was
the cause; the image the user sent was the instrument that found it.

## 9x. The band capture's mapping read the v axis downwards, and THAT was the "vertical lines"

**The report.** The text behind the bar showed as SHARP VERTICAL LINES instead of the frosted haze it
had had earlier. No value fixed it, and two reverts (the environment reach `1c97e31`, then the whole
audit pass and M2.5) both came back "igual".

**The cause.** `uvBackground = uBackgroundOffset + vTexCoord * uBackgroundScale` (`glass.cpp:500`)
turns a frame coordinate into a region coordinate. The shader reads the window BOTTOM-UP -- its own
distance from the top is `(1 - vTexCoord.y) * uTextureSize.y` (`glass.cpp:323`), a flip that was
MEASURED on screen, not assumed -- but the offset was written top-down:
`(frameRect.y() - region.y()) / region.height()` (`glass.cpp:1193`, before the fix).

**Why it hid.** With the WHOLE expanded geometry as the region, the shadow margins are symmetric here
(2 px top against 2 px bottom), so both origins agree to 4 px out of 762. `measure-capture-map.py`
measures it: `uv.y = 0.948..0.997` either way. Audit 1 (`e727879`) made the region the BAND -- 126 px
instead of 762 -- where the top-down offset is `+0.349` and the bottom-up one is `-5.365`. Every band
fragment then asked for `uv.y = 6.06..6.37`: the texture clamped to one row, the frost averaged that
row horizontally, and the band showed ONE ROW of the backdrop repeated. Vertical lines.
`evidence/2026-10-15-capture-map-bug-vs-fix.png` draws both, side by side.

**Why the bisect failed.** Both reverts were LATER than the band capture, which is the commit that
carried the fault. The user named the missing instrument: "es una tristeza ver como perdimos ese
progreso por no tener bien documentado un set de imagenes con cada avance". That is `snapshot.sh`,
which writes the image with the commit, the INSTALLED md5 and the live values in its name.

**The fix** (`glass.cpp:1208`) is
`frameBottomFromRegionBottom = (region.y() + region.height()) - (frameRect.y() + frameRect.height())`
-- the frame's bottom measured from the region's bottom. The whole-geometry mode does not move
(0.0026 either way, since the margins cancel) and the band lands at `0.349..0.651`: the reach above
the frame plus the band, which is exactly the region the capture covers. The suite pins the
expression AND refuses the top-down form; both assertions were watched fail first.

**What the simulator CANNOT say.** `simulate.py` models the band's MATERIAL, not the capture: it is
handed the backdrop already cropped and assumes the mapping is right. It could not have found this,
and it must not be asked to -- the mapping is arithmetic between two rectangles, and that is
`measure-capture-map.py`. Stated here because "the simulator is green" was about to be read as "the
screen is right", which is the same mistake this file exists to prevent.

## 9y. The band's bottom edge bent NOTHING, and the cause was which edge the direction came from

The user, twice: "en el fondo de la barra se ven lineas verticales, no curvea nada de ese fondo" and
"la refraccion doble el fondo a lo largo de TODO el filo de la banda (arriba, abajo, izquierda,
derecha) y alcance hacia dentro, no solo en las esquinas".

**The defect was a drift between the two implementations.** The bend's direction was the gradient of
the FRAME's rounded distance. The band's bottom -- where the glass meets the content -- is NOT an edge
of the frame: the window continues below it. The frame's distance is FLAT there, its gradient is zero,
and `inward` came out `(0, 0)`: the bend along the bottom was exactly nothing. The SIMULATOR never had
this, because it measures the whole box whose bottom IS the band's bottom, so it always bent there --
measured `shift_y ~ -20` at the bottom rows while the shader's own expression gave `0.00`. Which of
the two was right was never in doubt: the user's eye.

**The fix.** The band's bottom is its own edge (`bandEdge = uTitleBarHeight - topDistance`), `toEdge`
is the nearer of the frame's and that one, and the direction is a BLEND of the two edges' inward
normals, each weighted by its own proximity, normalised, with the magnitude the stronger of the two. A
hard `min` was the obvious alternative and it is WRONG: it leaves a seam wherever two edges are equally
far -- the middle of the band, and the diagonal out of every corner -- which is the defect 9w already
paid for once. The blend fades out at the middle instead of flipping through it.

**The reach is its own number.** It was `RimWidth`, the rim's own width, so the bend could not reach
further without widening the rim -- and the user asked for exactly that. `RefractionReach` (default
16 px) is separate, and 16 is MEASURED rather than chosen: with the bar at 38 px it is the largest
reach whose falloff is still exactly zero at the middle, so the top and bottom bends meet without a
seam. At 18 the middle flips +/-0.69 px, at 20 +/-2.08 and at 24 +/-5.19, which is the seam returning.

**The measurement, because a transcription can drift from the GLSL.** `effect-kwin/measure-refraction.py`
transcribes the shader's expressions and compares them with the simulator's field at the middle of each
of the four edges. Before the fix it read `bottom 0.00 px` against the simulator's 19.90
(`parity_max_mismatch=19.899`); after it the two agree to **0.000 px** at all four edges, and the
bottom's direction is vertical and upward. The suite also asserts the deciding GLSL expressions by
text, so the transcription and the shader check each other.

**The rest does not change.** Against the previous code on a high-contrast backdrop, the interior rows
18..26 are identical to the bit (max|diff| 0.0000); only the rows within a reach of an edge move.
Suite 430 pass / 0 fail, and the GLSL compiles under KWin's preambles for desktop GLSL 140 and ES 300.

**Still not seen on a screen.** Nothing here has been looked at: the install is pending (build
`50a68291...` against the installed `7ae6e419...`). The case to look at is the user's own -- a window
over an app with vertical lines.

## 9z. M3: the installer installed NOTHING, and the reproducibility gate was a formality

Two things came out of building the global theme, and both came out of **measuring** instead of
reading the scripts.

**1. `install.sh` pointed at a directory that does not exist.** It had `SALIDA="$AQUI/salida"`,
while every generator writes to `output/` (`install-decoration.sh` has always read
`$AQUI/output/aurorae/...`, and `tests/test-artifacts.sh` asserts `output/`). `./install.sh plan`
printed `source does not exist` for **all six** map entries -- the two colour schemes and the four
GTK files -- so `aplicar` copied nothing, wrote nothing and reported nothing wrong while looking
like it worked. The `.gitignore` comment still calls that directory "salida/", which is where the
wrong name came from: **a stale comment became a path**. `tests/test-global-theme.sh` now walks
`plan` and forbids that sentence, so the two names cannot drift apart again.

**2. The colour schemes' reproducibility check could not fail.** It calls
`python3 tools/generate-kde-schemes.py` **with no arguments**, and that `main()` starts with
`if len(sys.argv) < 3: print(__doc__); return 2`. It regenerates NOTHING, so the `cmp` compares a
file with itself and passes every time. The check meant to catch a generator drifting from the tree
was a same-file formality. (The decoration's check IS real: `generate-macos-decoration.py` has
working defaults, which is how it once caught its own drift.) The new generator is written to run
bare and the test asserts its **exit code**, so the M3 comparison is real. The scheme check is left
untouched on purpose: it is named here so the small pass that fixes it is not forgotten.

**3. What M3 ships.** `output/look-and-feel/KdeMacOS/` (`metadata.json` with
`KPackageStructure: Plasma/LookAndFeel`, plus `contents/defaults`) and
`output/desktoptheme/KdeMacOS/` (`metadata.json` with `X-Plasma-API: 5.0`, `colors`, `plasmarc`).
The formats were **measured on this machine**, not remembered: `breeze-dark` and `breeze-light` are
exactly `metadata.json + colors + plasmarc`, and Breeze's own global theme supplied the shape of
`defaults` (its `[file][group]` sections) and the KPlugin keys. The version is **read** from the
decoration's metadata, so the project declares it once. The parts we do not ship yet (icons, widget
style, cursor) point at KDE's own defaults, because naming a component the user does not have is
exactly how a global theme breaks a desktop; M5 and M6 change one constant each.

**Verified, in an isolated `XDG_DATA_HOME`:** `install.sh aplicar --si` now copies all five package
files (11 created, 0 modified), so the install path works and the user's session was not touched.

**Applying it is the user's step** -- the exact commands are in `docs/NEXT.md` -- and it has NOT
been verified on screen: the effect's session is not mine to change.

## 10a. Two taste changes the user asked for, made in the THEME not the effect

"podrias hacer los botones mas grandes y texto en negrita y mas grande" -- before the next
install, and it needs no build, because neither the buttons nor the title are drawn by this
effect: it composites what the theme drew. Two settings, both live:

- **Buttons 12 px -> 16 px**, in `output/aurorae/KdeMacOS/KdeMacOSrc` (`ButtonWidth`,
  `ButtonHeight`) and in the installed copy at
  `~/.local/share/aurorae/themes/KdeMacOS/KdeMacOSrc` (backed up next to it). The SVG button
  files are five-state 100x20 sheets with a 12 px circle in each 20 px cell, and aurorae
  SCALES that cell to these numbers, so the sheet needs no edit. **macOS's own is 12 px and
  the kit in `tokens/` does not define it**, so 16 is the user's taste and is recorded as
  taste -- the same argument as the corner radius: at 1:1 on a 4K 27" panel, 12 px reads small.
- **Title 12 pt bold**, in `kdeglobals [WM] activeFont` and `inactiveFont` and in
  `kwinrc [org.kde.kdecoration2] Font` (the system default was Noto Sans 10 regular). Both
  places are set because which one aurorae reads is not worth guessing, and the font string's
  weight field is 75 for bold against 50 for normal.
- `/KWin reconfigure` applies both, and unlike the case in section 10 it DOES work here: the
  decoration is KWin's own, so there is no effect whose `reconfigure()` has to be reached. The
  theme's own rc may need a reload; if the buttons do not grow, the relogin the pending install
  wants anyway will do it.

**AND THE VERTICAL LAYOUT NEEDED FIXING, measured.** With 16 px buttons the theme's own
numbers pushed them out of the bar: `PaddingTop=7` plus `ButtonMarginTop=8` is 15 px of
downward offset in a 28 px bar, so the button's centre landed at 23/28 = 82% and it overflowed
the bottom. The user saw it immediately ("los botones estan muy abajo"). Their screenshot
measures it: the glass band is 39 px with its centre at row 73, the buttons (16 px) occupy rows
72..87 with their centre at 79.5 -- **6.5 px low** -- and the text's centre is **4.5 px low**.
With `PaddingTop=2`, `PaddingBottom=2` and `ButtonMarginTop=4` the button's centre lands at
2+4+8 = 14, the exact centre of the 28 px bar, and since the bar is centred in the band, the
band's centre too. Section 10b's language debt had a piece left in `output/aurorae/`, and the
GENERATED colour schemes had Spanish headers citing a filename that no longer exists: fixed in
the generator and regenerated (headers only; the values are byte-identical).

The effect needs no change for either: it samples the window's texture, so a bolder, larger
title arrives with the theme. Worth writing down because the instinct is to look for the
button size in the effect, and it is not there.

## 10b. The language drift, and where it stands

The working agreement is **English in-repo**; Spanish is the language of the conversation. The
repository had drifted, and one session made it worse rather than better.

**Done (2026-10-14, same session that recorded it):**

- **`effect-kwin/src/` is English.** 133 identifiers renamed (123 in `glass.cpp`, 10 in
  `glass.h`), including the shader's locals, the capture cache's members and the two that the
  first sweep missed. The suite caught every assertion that quoted a renamed name and named
  every pattern that had to follow -- a rename is what the assertions are for.
- **The harness's shared variables are English**: `PROJECT`, `TEST_NAME`, `COUNT_FILE`,
  `FAILURES_FILE`, `PASSED`, `FAILED`, `SOURCE`, `HEADER`, `TIME_LIMIT`, and the scripts'
  `HERE`, plus the tests' own locals.
- **The tests' labels and the Spanish comments** in `run.sh`, `test-claims.sh`,
  `test-scripts.sh` and `test-harness.sh` are English.

**Deliberately still Spanish, and it should stay that way:**

- `tests/archive/` -- retired instruments are a RECORD, not live code. Rewriting history to
  look tidy destroys what makes it evidence.
- The user's own words, quoted in comments and docs ("los botones se ven algo extraños",
  "creo que ya funcionan las esquinas"). A translated quotation is not a quotation.
- `tests/test-claims.sh`'s `PALABRAS` list, which is DATA: the detector needs the Spanish
  spellings. A rename translated one of them to `output` and the check started flagging the
  `output/` directory.

**Still owed:** `tools/*.py` (~7 files, roughly a hundred Spanish comment lines) and the
`tokens/` headers. Nothing in the effect or the harness reads them, so they are lower risk --
but they are the same debt.

One thing the pass taught: a rename is not `sed`. It broke two checks in ways the suite could
not have predicted -- one vacuous check came back to life as a false positive, and a data list
of Spanish words got translated into `output`. Both are fixed and both now test the property
they name.

## 10c. M2: the squircle was the WRONG CURVE FAMILY, and the user saw it before I measured it

The three M2 commits (`cf9e1f8`, `0e21232`, `a23fb04`) are real and stay: they are the door, its test
and its measurement. What is behind the door is wrong, and this section exists so the next session
does not rebuild it.

**What the user saw.** After `./install.sh` and `./tune.sh CornerSmoothing=0.6`: *"se arruinaron las
esquinas... tiene un borde blanco la ventana muy grande y feo"*. Two separate things, and they have to
stay separate:
- the **white border** is the decoration theme (aurorae/KdeMacOS), not this geometry, and the user
  said so themselves ("no me he quejado de ello porque no estoy seguro si mas adelante veremos eso").
  It is queued, not part of M2.
- the **corners** are mine, and they were broken.

**The measurement that explains it.** The boundary's x at each height y, in the corner's own frame,
radius 20:

| y | circle | my superellipse (n=5) | Apple's construction |
|---|---|---|---|
| 1 | 13.76 | **20.00** | 16.12 |
| 5 | 6.77 | **20.00** | 12.55 |
| 10 | 2.68 | **19.87** | 13.25 |

A circle starts curving at y=6.2. **Mine stays at x=20 until y≈15 and then turns abruptly**: that is
a nearly square corner with a spike, not a subtle squircle. The white border was visible at the same
time and made it worse.

**The mistake, named.** I built the corner as a superellipse centred on the corner box's outer vertex,
`c(phi) = r*(sin^p, cos^p)`, with `p = 2/n` and a CALIBRATION I invented, `n = 2 + 5*smoothing`,
anchored on `0 -> n=2` and `0.6 -> n=5`. That family is not Apple's corner. Apple's construction
shrinks the arc to `r*(1-s)` and fills the gap with two tangent Bezier transitions that reach the
straight edge at `r*s` from the vertex; with `r=20` and `s=0.6` its bulge is **+0.23 px**, where mine
was 4.62 px. The number 4.6229 was measured honestly and pinned in the suite -- what was wrong was the
SHAPE that number described, which is the failure mode this repository already has a name for: a
metric that flatters itself.

**Why the suite did not catch it.** The test pinned the bulge and the gradient, and both were exactly
as designed. There is no known-value test for the shape as a whole, only for its two anchors, and both
anchors (circle at 0, "n=5" at 0.6) were true by construction. A calibration is not a measurement.

**Where it stands now.** `CornerSmoothing` defaults to `0` and `kwinrc` is at `0`: the screen is back
to the circular arc, confirmed in the effect's own log (`cornerRadius= 20 cornerSmoothing= 0`).
Nothing on screen is broken. The knob, its range, its README row, its uniform and its gate all work;
only the curve behind them is wrong.

**What M2 needs next, in one line:** replace the superellipse with Apple's construction -- smaller arc
plus two tangent Bezier transitions -- in `simulate.py` AND in the shader, together. That breaks the
"one parametric curve" assumption the current nearest-point search (table, and coarse+refine in GLSL)
rests on, so the distance to a piecewise curve needs its own decision. A whole session, and it wants
the instrument FIRST. Such an instrument was attempted in this session, **failed three times** (frame
of reference; a malformed known-value case; and then a naive row scan, which cannot even describe a
flat corner because it looks for the first window pixel in each row), and was DELETED rather than
committed, so no file of that name exists in the tree. Build it with a synthetic corner whose answer
is known before pointing it at a screenshot.

AND THE METHOD LESSON, because it is the same one the file already carries twice: I measured the bulge
(4.6229 px) and the gradient (0.04 deg) and reported both as if they settled the shape. They did not.
The user's eye, on a real screenshot, was the instrument that found it -- and it found it in one look,
after I had spent a session on the arithmetic. When the thing being judged is a SHAPE, the test that
matters compares the shape, not two numbers extracted from it.

### 10c-bis. The shape instrument exists now (2026-10-15)

`effect-kwin/measure-corner.py` reads a corner's boundary out of a COVERAGE image and reports it row
by row (`x_at_y_k`), plus the missing area and the length of the flat run, against closed-form
arithmetic. `python3 measure-corner.py --self-test` checks five cases whose answers are known by
construction, and the suite runs it (`tests/test-corner-shape.sh`). The first attempt was deleted
three times; this one was built against the synthetic corners FIRST, as this section demanded.

- **circle**: the arc of radius r centred at (r, r). Measured x at y=1/5/10 is 13.81/6.71/2.62
  against the closed form 13.76/6.77/2.68, and the diagonal reads 11.80 px inside r.
- **flat**: a square corner. It reads inset 0 everywhere -- described, not refused. That is the
  measurement the naive row scan of the first attempt could not make.
- **spike**: the wrong superellipse of this section (smoothing 0.6). It reads x=20.00 at y=5 and a
  flat run of 14 rows: the near-square corner the user saw, named as such by the instrument.
- **frame**: the same corner offset in a canvas and mirrored. The vertex is recovered and the profile
  does not move. The frame is DERIVED from the bounding box and then CHECKED against the straight
  edges; a profile that would be measured in the wrong frame is refused, not printed.
- **refuse_empty**: an all-background image is refused instead of measured.

TWO THINGS THE INSTRUMENT FOUND ON ITS FIRST RUN, both about frames rather than about curves:

1. **The renderer and the reader have to agree on the half pixel.** With the synthetic corner sampled
   at pixel CORNERS and the reader interpolating between pixel CENTRES, the circle read 5.64 where its
   arc is at 6.77 for y=5 -- a systematic half-pixel, not a bad curve. The case is sampled at centres
   now, which is what makes `y` mean `inset(y)`.
2. **This section's "Apple's construction" column is non-monotonic** -- 16.12 at y=1, 12.55 at y=5,
   13.25 at y=10 -- where a corner boundary's x can only fall as y grows. Either those three numbers
   were taken in different frames or one of them is wrong. They are NOT used as known values
   anywhere; the instrument settles Apple's construction from pixels, in one frame, when that curve
   is built.

The screenshot path (`--image`) is validated by two synthetic cases -- `image_png`, a round-trip, and
`realistic`, a gradient wallpaper with a light title band over dark content. The first REAL capture
(the user's, 1043x125, Konsole on a blue wallpaper) forced two more fixes, both measured rather than
guessed:

- the window's colour was sampled from the two INNER edges. A title band is a LIGHT glass and the
  content below it is dark, so the "foreground" came out as the content and the whole band sat below
  the 0.5 crossing: the tool refused with "no window pixel along this line". It is now sampled just
  inside the edge, found by walking the inward diagonal to the first strong rise -- the one sample
  that is right whatever the window's colour, after three wrong ones (bottom row, coarse bounding
  box, fixed offset).
- the background was GLOBAL. A wallpaper has a gradient across a wide crop, and at the far end it
  exceeded the glass-to-wallpaper step: the frame check found a "window" at x=828 of 1043. The
  measurement is now made on a LOCAL crop a few radii around the corner.

**ACCURACY, and its honest limit.** The synthetic realistic case reads the corner to 0.36 px. That is
the same size as the Figma-to-arc difference at a 20 px radius (0.36 px at y=1), so a screenshot
CANNOT settle which of the two curves is on screen. The `apple` case -- no background, an exact
render -- is what distinguishes them; a capture proves only that the corner is a rounded arc of about
the right radius and NOT the near-square corner of 10c. Making the difference visible would need a
much larger `CornerRadius`, because corner smoothing redistributes curvature rather than changing it.

### 10c-ter. The curve is replaced, in both implementations (2026-10-15)

The superellipse is GONE from `simulate.py` and `src/glass.cpp`. What is there now is the Figma
construction the kit's `cornerSmoothing = 0.6` actually names -- and the measurement of it is in
`10c-bis`, above.

    p          = (1 + s) * R    the straight edges end p from the vertex
    arc        = radius R, its MEASURE shrunk to 90*(1-s) degrees, centred at (R, R)
    transition = two cubic Beziers, tangent to the edge at p and to the arc

At `s = 0` it collapses EXACTLY to the circular arc, and the circular branch in both files is the
old expression, operation for operation: the shape approved on screen cannot move. At the kit's
`0.6` the middle of the corner is still that circle -- measured `x` at `y=5` and `y=10` is 6.77 and
2.68, the arc's own values -- and only the transition is fuller (14.12 against 13.76 at `y=1`).

THE DECISION 10c ASKED FOR, MADE: a piecewise boundary has no single parametric nearest point, so
both implementations SEARCH SEGMENTS and keep the two straight edges as rays, with the split moved
from `q=0` to `q=-s*R`. The simulator searches 96+ segments by `np.clip`; the shader searches 24
(within ~0.02 px of the true curve) with `clamp`. The sign comes from the curve's own monotone
inside test in the simulator and from the winning segment's normal in the shader.

PARITY, MEASURED RATHER THAN ASSUMED: a transcription of the shader's block (24 segments, normal
sign) against `simulate.figma_corner_sdf` (400 segments, monotone sign) over a 41x41 grid covering
the corner and both transitions gives **0 sign mismatches** and a maximum difference of **0.029 px**,
all of it the segment count. The old `n = 2 + 5*smoothing` appears in neither file, and the suite
now asserts that with `negar`, by name -- the assertion the old section could not make, because it
pinned the wrong curve as the right one.

DEFAULT-OFF, ON PURPOSE: `kCornerSmoothing` is 0 and `kwinrc` is 0, so an install changes nothing
on screen until the value is asked for. That is what makes shipping the port safe before anyone has
looked at it: if the smoothed branch is wrong, the control is still the approved arc and the recovery
is `tune.sh CornerSmoothing=0` or the §9u runbook.

**Install pending as this was written**: the built `.so` carries the port and the installed one does
not. `cd effect-kwin && ./install.sh`, then a relogin or the §9u hot path, then
`./tune.sh CornerSmoothing=0.6` and LOOK.

THE VISUAL COMPARISON M2's done criterion asks for is
[`evidence/2026-10-15-m2-figma-vs-arc.png`](../evidence/2026-10-15-m2-figma-vs-arc.png): both
boundaries at radius 20, 10x, with the sliver the smoothing removes from the arc drawn in green.
It is a SYNTHETIC comparison on purpose, because a screenshot cannot resolve the difference (0.36 px
accuracy against a 0.36 px difference, above). The figure makes the shape honest at a glance: the
green appears only at the two ends of the transition and is absent along the whole middle arc, which
is exactly the claim -- the smoothing changes how the curve MEETS the edges, not the arc itself.

### 10c-quater. M2.5: the curvature instrument, and the CLOTHOID is the G2 candidate (2026-10-15)

The user, on the whole bar over a busy backdrop: the refractory streaks come out vertical at the top
and "en un angulo sin curvas hacia la derecha" low down, and they asked for the curvature of
`muestras/Screenshot_20261014_214038.png`, where "es precioso como curvea todo el color verde de una
forma bonita y elegante". The streak DIRECTION was a separate bug (section 9w, the invented diagonal).
This is the SHAPE: the Figma construction on screen is tangent-continuous (G1) but its curvature
OVERSHOOTS the arc's by **+47%**, and that overshoot is the angle the eye reads in the highlight.

**THE INSTRUMENT FIRST**, and it is `measure-corner.py --curvature <curve>` plus the `curvature`
self-test case. It measures kappa(s) as TURNING PER ARC LENGTH. Two estimators died before this one
and both were mine: the second derivative of x and y against arc length read a spike at every SEAM
where the sampling density changes (the transition and the arc are sampled differently), and
pre-smoothing the POINTS rounded those seams and invented a bump of its own (+14% on a clothoid whose
signed turning is provably at or below 1/R everywhere). The verdict is `spike`: kappa somewhere more
than 1% above the arc's own 1/R. It is checked on the two cases whose answer is known by definition,
and it must agree with the user's eye before it judges a replacement:

    circular arc        kappa 0.05000..0.05000   +0.00%   spike=False   maxima=0
    Figma, ON SCREEN    kappa 0.00001..0.07344   +46.89%  spike=True    maxima=2

**THE CANDIDATES**, all at R=20 and the kit's s=0.6, measured with that instrument:

| construction | kappa min..max | overshoot | spike | maxima |
|---|---|---|---|---|
| circular arc (the reference) | 0.05000..0.05000 | +0.00% | no | 0 |
| **Figma, on screen today** | 0.00001..0.07344 | **+46.89%** | **yes** | 2 |
| **clothoid (Euler spiral) + arc** | 0.00004..0.05000 | **+0.00%** | **no** | **0** |
| curvature-matched cubic Bezier | 0.00001..0.06459 | +29.19% | yes | 2 |
| superellipse centred on the ARC CENTRE, n=3 | 0.00107..0.08909 | +78.18% | yes | 1 |
| the same, n=4 | 0.00017..0.12613 | +152.26% | yes | 1 |

Two of them deserve a note, because both look right on paper:
- the **arc-centred superellipse** is a DIFFERENT family from the one 10c threw away -- that one was
  centred on the corner VERTEX with the invented `n = 2 + 5*s` -- and it was a legitimate candidate.
  It is rejected by MEASUREMENT: it overshoots, and worse as n grows. Rejected on its numbers, not by
  association with the old mistake.
- a **curvature-matched cubic Bezier** -- kappa 0 at the straight edge and 1/R at the arc, both
  tangents matched, which is textbook G2 at the JOINTS -- still overshoots +29% BETWEEN them. Matching
  the ends is not enough; the curve has to be the right one in the middle.

**RECOMMENDED: the clothoid.** kappa(s) = s/(R*L) rises LINEARLY from 0 at the straight edge to 1/R at
the arc, monotone by construction, so it cannot overshoot: measured +0.00% with no maximum above the
arc, which is exactly what the instrument tests. The transition's turn is fixed by the arc's measure
(`dtheta = (90 - m)/2`, so `L = 2*R*dtheta`), and the corner's symmetry about `x = y` fixes where it
meets the straight edge (`p = 30.09` at m=36, against the Figma construction's 32). It is the standard
transition curve in road and rail design and is used in type design for G2 corners. It is NUMERICAL (a
Fresnel integral), not closed-form, so both implementations will carry it as a sampled polyline --
which is what they already do for the Figma piecewise curve, so the nearest-point search does not
change shape.

**THE SAMPLE could not be turned into a numerical target**, and saying so is part of the measurement:
at 386x221 the green mask's boundary has one-pixel steps, and even a sub-pixel extraction of the 0.5
crossing leaves 9 local maxima and a noisy kappa. It is the LOOK reference; the criterion that can be
decided is the overshoot relative to the arc, and on that the clothoid is the only candidate that is
G2. Its profile (0 -> 1/R, monotone) is also the character the sample shows, which is the qualitative
comparison the resolution supports.

**WHAT IS NOT DECIDED HERE:** the arc measure `m` -- the shape between 36 and 54 degrees is a taste
and a comparison against the sample, not a curvature question -- and the implementation in
`simulate.py` AND `src/glass.cpp`, which is the next step and touches both at once. **NOTHING in the
effect changed in this step:** this is the instrument and the decision, and the suite pins all four
verdicts (the arc continuous, the Figma curve flagged, the clothoid G2, the two rejected families
overshooting) so a rewrite cannot quietly reach for one of the others.

### 10c-quinquies. The clothoid is IMPLEMENTED in both, and its shape change is measured (2026-10-15)

`simulate.py` and `src/glass.cpp` now carry the clothoid, both integrating the SAME heading in a
bounded loop (the simulator 48 steps, the shader 16 with 8 for the arc) and both searching segments.
What keeps the two integrals identical is asserted: `radians(90*(1-s))`, `dtheta = (pi/2-m)/2`,
`L = 2*R*dtheta`, and the edge rays beginning at `edgeQ = R - p` -- NOT at 0, because p > R. At
`smoothing = 0` the transition has no length and the corner is the circular arc, and that branch is
untouched, operation for operation.

**PARITY, MEASURED:** a transcription of the shader's block (16/8 steps, normal sign) against the
simulator's `corner_sdf` (400-sample polyline, monotone sign) over a 61x61 grid covering the corner
and both transitions -- **0 sign mismatches, maximum difference 0.0226 px**, all of it the step count.

**AND ONE CONSEQUENCE THE CURVATURE INSTRUMENT COULD NOT SEE, reported rather than buried.** The
clothoid is G2, but its ARC CENTRE is not at (R, R): measured (20.78, 20.78) for R=20, m=36, so the
corner is **~1 px FULLER than the circle** -- `x` at y=1/5/10 is 17.02/8.39/3.86 against the arc's
13.76/6.77/2.68, and the closest point to the vertex is 9.32 against 8.28. The Figma construction it
replaced kept the middle ON the circle and paid a +46.9% curvature spike for it; the clothoid trades
that middle for continuous curvature, and the trade is in the direction Apple's continuous corners
go (they are fuller than a circular arc of the same radius). The suite pins the fuller numbers, so
the change cannot be mistaken for a regression later. Whether the SIZE is the one the user wants is a
look judgement, and it wants a screen: `install.sh` + relogin (the hot path does not re-read the .so).

## 10d. M4: the type scale reaches kdeglobals, and three MEASURED facts decided how

**What it does.** `tools/generate-global-theme.py` now writes the font keys into the SAME
`contents/defaults` M3 ships -- there is no second package -- and it READS the sizes and weights
from `tokens/tokens-typography_macos.toml` instead of restating them. Six roles come from the
tokens (`font`/`menuFont` <- Body, `toolBarFont` <- Subheadline, `smallestReadableFont` <-
Caption 2, `[WM] activeFont` <- Headline, `inactiveFont` <- Body); `fixed` is a DECLARED fallback
(`Noto Sans Mono`), because the HIG publishes no monospaced size token.

**Three facts, measured with a Qt 6.12 probe BEFORE the code was written.** The probe was three
small C++ programs linked against `Qt6Gui`, and these numbers are why the emitted strings look
odd:

1. **The size goes in the PIXEL field, not the point field.** `setPointSize(13)` emits
   `Inter,13,-1,...`, and KDE renders POINTS at its font DPI -- 96 here, with no `forceFontDPI`
   key set -- so 13 pt is `13 * 96/72 = 17.3` logical px: a THIRD larger than macOS.
   `setPixelSize(13)` emits `Inter,-1,13,...` and renders 13 px. macOS draws its styles at
   1 pt = 1 px and has no Dynamic Type (the scale is fixed), so the pixel form is the faithful
   one, and `fromString` round-trips it (measured: `pixelSize=13` back, weight 400 from `50`).
2. **The weight is the LEGACY 0..99 code.** `QFont::fromString` reads `75` as 700 (Bold) but `400`
   as **900 (Black)**: everything >= 99 saturates at Black. Measured table: `0->100, 12->200,
   25->300, 50->400, 57->500, 63->600, 75->700, 81->800, 87->900`. Writing Qt 6's own
   `toString()` output (400 for Normal) would paint every label black. The generator maps
   CSS -> legacy, and `tests/test-typography.sh` forbids a modern weight BY NAME, so the trap
   cannot come back silently.
3. **The tracking has NO destination, and it is 64 of the 80 tokens.** kdeglobals has no
   letter-spacing key at all. The other 7 are styles with no KDE role (`large_title`,
   `title_1..3`, `callout`, `footnote`, `caption_1`): kdeglobals has about seven font keys against
   the HIG's eleven styles. Applying the tracking needs QSS/widget-level styling, which is M6's
   territory -- and saying so is the point, because an unapplied token that nobody names reads
   later as an applied one.

**The evidence** (`evidence/2026-10-15-m4-text-scale.png`, generated by
`tools/render-type-comparison.py`) renders the same strings at KDE's default (Noto Sans 12 pt at
96 DPI = 16 px) and at the macOS scale (13 px), and PRINTS the measured advance widths:
`335 -> 272 px`, ratio **0.812** (= 13/16). Both rows use the same font file, because **Inter is
NOT installed on this machine** (`fc-list | grep -i inter` is empty, measured) and fontconfig
substitutes Noto Sans: the picture compares the SCALE, not the typeface, and says so inside the
image rather than in a caption nobody reads.

**The user's step**, not run here because applying it is their session:
```
./install.sh aplicar --si
plasma-apply-lookandfeel -a KdeMacOS
```
and, for the real family, `sudo pacman -S inter-font` (Arch/CachyOS: `extra/inter-font` 4.1-1).

**What this session could NOT verify:** anything on screen. Whether Plasma's font KCM shows a
pixel-sized font the way its dialog expects is the first thing to look at when it is applied --
it is a real risk of the pixel choice, and it is written here BEFORE it is tested so that a
surprise later is a finding and not a forgotten doubt.

`tests/test-typography.sh` pins the mapping: the pixel field, the legacy weight, and the refusal of
a modern one by name. (The counted size of the suite is deliberately NOT written here: a doc that
quotes the count breaks the run that verifies it -- section 11.)

## 10d-bis. AMENDMENT to 10d: the size moved to the POINTS field, and the pixel field was wrong

**What 10d got wrong, and how it showed.** 10d's item 1 put macOS's size in the PIXEL field and
called it the faithful unit, flagging one risk (the font KCM works in points). The KCM turned out
BENIGN -- it shows `Inter 9.75pt` and accepts it, measured on screen -- but a different symptom
appeared in real applications, and only there:

```
QFont::setPointSize: Point size <= 0 (-1), must be greater than 0
```

**The cause is a fact of `QFont`, not a choice:** it holds a size in POINTS **or** in PIXELS, never
both. A pixel-sized font answers `pointSize()` with **-1**, and any code that re-applies it prints
that line. **Measured, and this is what settles where the bug lives:** the message appears with
`QT_STYLE_OVERRIDE=Breeze` too, so it is NOT the QStyle (`style-kde-macos/`). It is the font.

**The fix.** The generator now writes the size in the POINT field, derived from the pixel token at
the measured font DPI (96, no `forceFontDPI`): `72/96 = 0.75`, so macOS's 13 px -> **9.75 pt**,
11 -> **8.25**, 10 -> **7.5**. The factor lives in one place (`PUNTOS_POR_PX`), and
`tests/test-typography.sh` derives the same factor from the same token, so they cannot drift.

**The proof, in two independent halves.**

1. **`tools/font-probe.cpp`** (built by `tests/test-typography.sh` with the Qt 6 the desktop runs)
   parses each emitted string and reports what Qt sees. The test asserts `pointSizeF() > 0` for all
   six roles -- `9.75 / 9.75 / 8.25 / 7.50 / 9.75 / 9.75` -- AND that the metrics still equal the
   pixel-form YARDSTICK, which is the same font, same family and same weight with only the unit
   changed, so a bold title is not compared against a 13 px body. Measured: identical (`height`
   16/16/14/12/16/16 and `advance` 276/276/233/214/283/276 before and after). The test also runs the
   OLD pixel form on purpose and requires it to read `-1.00`, because an assertion that cannot fail
   proves nothing.
2. **The render evidence is byte-identical.** `tools/render-type-comparison.py` prints the same
   advance widths (`335 -> 272`, `336 -> 273`, `210 -> 171`, `220 -> 179`) and regenerates the same
   PNG: `git status` does not even list it.

**The accepted cost, written down.** At a font DPI other than 96 the points scale and a pixel size
would not. A fixed scale is what macOS has; a valid `pointSize()` is what KDE needs without
warnings, and at this machine's DPI the two are the same pixels. 10d's item 1 is SUPERSEDED; its
items 2 (the legacy weight) and 3 (the tracking) stand unchanged.

## 10e. The global theme carried a type scale and an effect switch, and NOTHING applied them

M4 wrote the macOS fonts into the global theme's `contents/defaults`, `install.sh aplicar` copied the
package correctly, the user ran the documented `plasma-apply-lookandfeel -a KdeMacOS` -- and the text
did not change. The cause was MEASURED, not guessed, and it is not only about fonts.

`plasma-apply-lookandfeel` does not write the defaults into the user's configuration. It writes them
into `$XDG_CONFIG_HOME/kdedefaults/<file>`, which is the layer KDE reads as a **fallback**, and it
silently DROPS the keys that do not fit there. Measured by applying into an isolated
`XDG_CONFIG_HOME` and grepping the result file by file:

| `defaults` entry | where it lands |
|---|---|
| `[kdeglobals][KDE] widgetStyle`, `[kdeglobals][General] ColorScheme`, `[kdeglobals][Icons] Theme` | `kdedefaults/kdeglobals` |
| `[plasmarc][Theme] name` | `kdedefaults/plasmarc` |
| `[kcminputrc][Mouse] cursorTheme` | `kdedefaults/kcminputrc` |
| `[kwinrc][org.kde.kdecoration2] library`, `theme` | `kdedefaults/kwinrc` |
| `[ksplashrc][KSplash] Theme` | `kdedefaults/ksplashrc` |
| **`[kdeglobals][General]`** `font`, `menuFont`, `toolBarFont`, `smallestReadableFont`, `fixed` | **NOWHERE** |
| **`[kdeglobals][WM]`** `activeFont`, `inactiveFont` | **NOWHERE** |
| **`[kwinrc][Plugins]`** `macosglass2Enabled` | **NOWHERE** |

So it was not the fonts alone: the theme also promised to switch the effect on, and that key went
missing with them. And a fallback would not have been enough even if the font keys HAD landed,
because the user's own `[WM] activeFont=Noto Sans,12` wins over a default -- which is why the fix
writes into the user's file and not into the defaults layer.

The fix lives in `install.sh aplicar`: it READS the installed `defaults` -- the one source of truth,
the same file the map copies, never a copy of its values that could drift apart -- and writes with
`kwriteconfig6` ONLY the keys the tool did not carry, which is exactly what the Fonts KCM does when a
font is changed by hand. Each file is backed up once and recorded in the manifest, so `rollback`
undoes it, and with no `kdedefaults` layer at all (the tool has never run) every key is written,
which is what applying a theme means.

`tests/test-lookandfeel-apply.sh` runs the whole cycle with an isolated `XDG_CONFIG_HOME` and
`XDG_DATA_HOME`: it compares EVERY font key against the file -- never against a string remembered in
the test, or it would pass the day the defaults change and the installer does not -- and asserts that
the effect switch lands and that a key which is NOT the theme's survives untouched. Two traps, both
mine and both caught by the runner: an `EXIT` trap of its own REPLACES the one `tests/run-one.sh`
uses to report the counter (the file reports "died without reporting a counter" while every
assertion passed), and `kreadconfig6` MERGES the `kdedefaults` fallback, so a key the tool dropped
looks present until the test reads the file directly.

## 10f. M5: the icon radius IS measurable, the corner family is NOT

The ROADMAP said: "The squircle radii of the folder icons are missing. There are iOS values in the
kit, but the macOS ones could not be confirmed." The answer turned out to be half of each, and the
half that is NOT confirmed is the more useful half to have written down.

**WHAT IS CONFIRMED, and from the primary source.** The radius. `muestras/` holds the user's own
macOS screenshots and is gitignored, so the measurement is versioned and the pixels are not.
`tools/measure-icon-geometry.py` reads the corner profile out of a capture -- the subpixel x where
the icon's body starts, row by row -- and fits three families: a circle, the kit's own
`cornerSmoothing` construction (IMPORTED from `effect-kwin/measure-corner.py`, because this
repository does not keep two copies of one formula) and a superellipse. Before it is allowed to
report anything from a photo, `--self-test` draws a corner of a KNOWN radius and reads it back:
R = 14, 20 and 26 come back with **0.00 px** of error. Twelve icons fitted within 2 px across
`Untitled3.png` (median 0.2161 +- 0.0026) and `Untitled2.png` (median 0.2135 +- 0.0067), giving
**R/S = 0.215 +- 0.01** for a 96 px icon (R = 20.6 px). The tolerance is 0.01 and not the 0.006 the
spread suggests, because the 0.5 crossing on an antialiased edge moves with the contrast, worth
about half a pixel -- rounding a token's precision UP is how a token starts lying.

**WHAT IS NOT CONFIRMED. Two things, and the token declares both.**
1. **No folder icon is drawn in any of the nine captures.** The Launchpad and the Dock give APP
   icons; the macOS folder is a folder shape with its own tab, and its body was never checked
   against anything. The app icons sit on the same Apple icon geometry, so 0.215 is the best
   available figure and NOT a measurement of the folder. A capture of a Finder window with large
   icons would settle it.
2. **The corner FAMILY cannot be resolved at this size.** This is a property of the pixels, not of
   the fitter: the kit's own corner at `smoothing = 0.6` has a profile that differs from a plain
   circular arc only in its first two rows, and from row 2 down the two agree to 0.01 px. Fitting a
   CIRCLE to the kit's own drawn corner leaves a **0.29 px** residual (`--self-test` prints it). At
   the 96 px an icon is drawn at on a 4K screenshot, the row that carries the difference is
   sub-pixel, so the radius is measurable here and the smoothing is not. Anyone reporting a
   smoothing from these captures is reporting noise.

**THE KIT HAS NO iOS ICON RADIUS, which corrects the ROADMAP.** The five iOS values are CONTROL
radii -- `Global/Radius`, `Button/Radius`, `Checkboxes/Radius`, `Disclosure/Radius`,
`Stepper/Radius` -- and `tokens-shape-effects.toml`'s `[squircle] smoothing = 0.6` is a
CONSTRUCTION parameter (what Figma's cornerSmoothing means), not a radius. `tokens-icons.toml`
declares itself a context-only collection with no numeric values. So there was no iOS icon figure
to compare against, and the figure in the token is a measurement and not a comparison.

**FOUR MISTAKES MADE WHILE MEASURING, so the next reader does not repeat them.** Each one was
caught by looking at the OUTPUT rather than at the code:
- The reader took the first light pixel of the WHOLE row. On a Launchpad that is whatever is
  brightest elsewhere in the screenshot: the first run reported insets of 180, 360, 540 px -- the
  icon grid's own spacing -- with residuals that grew by one grid step per icon.
- The icon's side was "the widest light row", which under a Launchpad icon is the LIGHT LABEL with
  the app's name, not the icon: it read 112 px and 150 px for a 96 px icon.
- The evidence render drew the BEST fit while its own caption claimed the worst (a stray minus),
  and the next version drew a REJECTED measurement -- whose 8 px residual is a mis-detected corner
  and not a difference between models -- under a caption saying the models agreed. It now draws the
  worst fit AMONG THE VALID ONES, which is the residual worth looking at.
- A measurement whose fit does not hold is REPORTED AND COUNTED, not averaged in: three icons of
  fifteen had 8-11 px residuals and were left out of the statistic, visibly, rather than quietly
  pulling the median.

## 10f-bis. AMENDMENT to 10f: the FOLDER is measured too, and it is NOT the app figure

The user brought exactly the capture 10f asked for: `muestras/Untitled6.png`, a Finder window with
four folders (Applications, Library, System, Users). The first of 10f's two "not confirmed" items is
therefore **confirmed**, and the answer justifies having waited for it -- the folder's body corner is
about **four times tighter** than the app icons'. Assuming the app figure, which was the only
alternative available to 10f, would have been wrong.

**THE MEASUREMENT.** Four of four folders, none rejected: **R/S = 0.049** (R = 5.85 px on an icon
120 px wide; the body is 120 x 89). The four agree to the grid's resolution (spread 0.000) and the
figure carries 0.01 because the 0.76 px fit residual and the edge detection add a systematic term the
spread cannot see, exactly as 10f argued for the app figure. Against the app icons: 0.215 / 0.049 =
**4.4x tighter**, so "a folder is drawn on the app icons' squircle" is now a measured falsehood and
not an untested assumption -- which is what M5 existed to find out.

**THE FOLDER NEEDED THREE THINGS THE INSTRUMENT DID NOT HAVE.** All three are in it now:
- A **POLARITY**: `find_icons` looked for LIGHT bodies on a dark background, which is the Launchpad.
  The Finder draws DARK blue folders on a WHITE desktop, and the first run read the SIDEBAR as one
  more icon. Hence `--polarity dark`, and `--x-range` for the same reason.
- A **CORNER**: a folder is a folder SHAPE and its TAB covers the top-left, the corner the reader had
  always used. `--corner tr` reads the body's clean top-right one.
- A **RADIUS RANGE AND A ROW COUNT**: the fitter's grid started at 12 px, far above the folder's ~6,
  and the first run answered `R = 12.00, error 6.92 px` -- a grid edge, not a measurement. The probe
  that finds the icon's top edge also had to move to the corner's side, or it found the TAB and put
  the top edge three rows above the body's.

**THE TAPER IS THE MEASUREMENT'S OWN WARNING.** The profile is 5.10, 3.28, 2.20, 1.15, 0.45, 0.04 --
and then 0.29, 0.63, 0.86, 0.99, 1.13, 1.20, 1.22, 1.22: past the corner the body's right edge keeps
moving INWARD. That is the icon's own taper (and its shadow), not a corner, and fitting it in moved
the radius from 5.9 to 5.1 px. `--rows 6` is the corner up to its first minimum, and the command
recorded in the token says so.

**AND THE FAMILY IS STILL NOT RESOLVABLE**, for the reason 10f gave: at a 5.9 px radius the circle,
the kit's construction at any smoothing and a superellipse fit identically (the fit returns `s = 0.00`
and `n = 2.00`, which ARE the circle). The radius is a radius.

**THREE MISTAKES OF MINE, each caught by looking at the output:**
- The rewritten reader walked the profile **outwards** -- the direction it samples the background --
  so every row came back NaN. It broke the app icons too, which is what caught it.
- The "side" was taken from a fixed 160 px window, which in a Finder grid reaches the NEXT folder: it
  read `side = 160` for a 118 px folder and fed that inflated number into `R/S`. It is the icon's own
  run now.
- `fit_all` refused profiles shorter than 8 rows, and a folder's corner is 6: the command printed
  "no icons measured" with the corner sitting right there in the profile.

## 10g. M6, first slice: a QStyle that is selectable and draws NOTHING yet

The ROADMAP calls M6 "the biggest step of the brief (1-3 months)", the only milestone not on top of
anything already done, and its done criterion is "it exists, is installed, and is selectable
**without breaking applications**". The first slice therefore ships a SKELETON and stops, and this
section is about the half of that criterion that is not "it exists": a style plugin is loaded by
every Qt application on the desktop, so the one way to be sure that selecting it breaks nothing --
before a single primitive exists -- is for selecting it to change nothing at all.

**WHAT SHIPS.** `style-kde-macos/`: a `QStylePlugin` whose `Keys` are `["KdeMacOS"]`, wrapping a
`QProxyStyle` that chains to a base style and overrides **no** primitive; `install.sh` installs the
plugin and the one environment variable Qt needs to see it, with its `rollback`; and
`tests/test-style.sh` proves the three claims. The plan, the decisions and the slices that follow
are [`M6-QSTYLE-PLAN.md`](M6-QSTYLE-PLAN.md).

**THE PROOF IS A DIFFERENCE OF ZERO, and the first version of the probe could not have found a
style that painted nothing.** That probe counted non-white pixels and reported `19800 of 19800` --
the whole canvas -- because the WIDGET'S OWN BACKGROUND covers it. A green number for a no-op. What
it does now is render the SAME widget twice, once under the base style and once under ours, and
compare the images pixel by pixel: **`DIFF: 0`**. That is what "does not break applications" means
while the skeleton is a skeleton, and the day a slice implements a primitive, that difference is the
measurement the slice owes.

**SEVEN MEASUREMENTS decided the shape of it**, all taken with a throwaway probe plugin before any of
the component was written (Qt 6.12, Plasma 6, Wayland):
1. `QStyleFactory` scans a **`styles/` SUBDIRECTORY** of the plugin path, not the path itself. A
   plugin at `<path>/kdemacosstyle.so` is invisible; at `<path>/styles/...` it appears in
   `QStyleFactory::keys()`. Hence `CMAKE_LIBRARY_OUTPUT_DIRECTORY`.
2. The keys Qt reports here: `Breeze`, `kvantum-dark`, `kvantum`, `Windows`, `Fusion`.
3. Qt does **NOT** search `$HOME/.local/lib/qt6/plugins` on its own -- the library paths are
   `QT_PLUGIN_PATH`, then `/usr/lib/qt6/plugins`, then the application's directory. So installing
   the plugin is not enough and the environment file is half the job.
4. Qt 6.12's `qt_add_plugin` has **no `SOURCES` keyword**: `SOURCES src/x.cpp` is read as a source
   file named `SOURCES` and the configure step dies with "Cannot find source file: <build>/SOURCES".
   The sources are plain arguments.
5. The metadata is the shape Breeze's is -- `QStyleFactoryInterface_iid` from Qt's own header plus a
   `metadata.json` with `{"Keys":[...]}`, read back with `QPluginLoader::metaData()`. Breeze carries
   `Keys` and nothing else, so neither do we.
6. The **offscreen platform is enough** to test it: a real `QApplication` creates the style through
   the factory and renders widgets into a pixmap, with no screen and no session.
7. **systemd's `environment.d` is the mechanism this session has** (`/usr/lib/environment.d/` is
   populated and `systemctl --user` responds; `~/.config/environment.d/` did not exist). The KDE
   `~/.config/plasma-workspace/env/` exists here too, but was not measured to be read on a
   systemd-managed Wayland session, so it is not the one used.

**THREE DECISIONS, and the reasons are the interesting part.**
- **The base style is RESOLVED, not written down**: Breeze if Qt offers it, else Fusion.
  `QStyleFactory::keys()` is asked at construction. Breeze first because chaining to the style the
  user already had is what makes "does not break" true; Fusion as the fallback because it is the one
  style Qt always has, and an EMPTY base is not neutral -- `QProxyStyle` then falls back to the
  application's style, which may be this very style, and that is recursion.
- **The install is user-level plus an environment file**, rather than `/usr/lib/qt6/plugins/styles`
  which would need no environment file at all: the system path needs `sudo`, and `install.sh`'s
  golden rule (never escalate, never write outside `$HOME`) is exactly what makes `rollback` able to
  undo everything.
- **Installing is NOT selecting.** The installer writes the plugin and `QT_PLUGIN_PATH`; it does not
  touch `widgetStyle`, because changing how every application on the desktop is drawn is the user's
  decision and not an installer's side effect. Selecting is
  `kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle KdeMacOS` (then a relogin), or, for
  ONE application with no config and no relogin, `QT_PLUGIN_PATH=... QT_STYLE_OVERRIDE=KdeMacOS`.

**A TRAP IN THE TEST ITSELF, of the kind this repository collects.** The assertion that no primitive
is overridden used a plain `grep`, and the header's own comment lists the primitives to explain why
they are ABSENT -- so the test counted the explanation as the deed and reported two overrides that
do not exist. It uses `codigo_contiene`, which ignores comments, exactly as the harness's `afirmar_-
codigo` does. Same lesson as "verify the file, not the patch", pointing the other way.

## 10h. The suite opened a dialog in the user's session, because a test isolated every variable except HOME

MEASURED on 2026-10-15, and it is the kind of thing this section exists for: the user reported a KDE
dialog reading **"Configuration file `//.config/kreadconfig6rc` not writable. Please contact your
system administrator."** while the suite was running. The suite had been started with `env -u HOME`,
to see whether anything needed it, and `tests/test-lookandfeel-apply.sh` isolated `XDG_CONFIG_HOME`
and `XDG_DATA_HOME` -- but **`kreadconfig6`/`kwriteconfig6` fall back to HOME** for their own
bookkeeping. With HOME empty they resolved `//.config/kreadconfig6rc`: a path at the root of the
filesystem, which is why the complaint was about permissions.

Three things worth keeping:

1. **Nothing was written.** `/.config` does not exist, and the write failed for that reason. The
   user's `kdeglobals` was checked afterwards and still carried `ColorScheme=KdeMacosLight`,
   `activeFont=Inter,-1,13,5,75,...` and `widgetStyle=Breeze`.
2. **The fix is one line and it closes the class, not the instance**: the test now points **HOME**
   inside its temp directory as well. It passes with HOME unset, which is the way the failure was
   reproduced in the first place.
3. **A test that is supposed to touch nothing must not be able to open a window**, and the detector
   for that class is not "did it write": it is "which variables does the tool I am calling fall back
   to, and have I isolated ALL of them". XDG_CONFIG_HOME is not HOME, and a tool is free to use both.

The same HOME-less run produced a failure that looked like a real one -- `test-style.sh`'s probe
reported nothing usable -- and was not: with no HOME the probe cannot do its bookkeeping either. A
suite run outside a normal environment reports the environment, which is why the incident is written
here instead of being debugged into the plugin.

## 10i. M6, slice 1: the primitive instrument, and the four times it measured the wrong thing

The plan's rule is that a primitive is only changed with its measurement in front, and this slice IS
that measurement, built so the NEXT slice moves a number instead of a taste. It renders nineteen
controls under the base style and under ours, reports the pixel difference **per widget**, and prints
what Qt answers for each control (`sizeHint`, `pixelMetric`, `sizeFromContents`, `subControlRect`,
`subElementRect`) together with whether OUR answers differ from the base's.
[`primitive-gallery.cpp`](../style-kde-macos/tests/primitive-gallery.cpp) draws it and
[`test-style-gallery.sh`](../tests/test-style-gallery.sh) runs it under the offscreen platform; the
evidence is `evidence/2026-10-15-m6-gallery.png` (OUR drawing: the base panel beside ours) and the
baseline table is `evidence/2026-10-15-m6-baseline-metrics.txt`. Today: **19 primitives, 0 pixel
differences, 0 metric differences** -- a starting line, not an achievement.

**FOUR TIMES THE INSTRUMENT MEASURED THE WRONG THING. Every one was caught by looking at the OUTPUT
and not at the code**, which is the method this repository wants to keep:

1. **`PAINTED base=6216 of 6216`.** It counted pixels that were not the canvas colour, and the
   WINDOW'S OWN BACKGROUND covers the canvas -- so the number was the canvas area, and it would have
   been green for a style that painted no control at all. The same trap the slice-0 probe recorded,
   repeated by the file that quotes it. What is counted now is what the CONTROL contributes beyond an
   EMPTY widget of its own size: the same window is rendered twice, once with the control and once
   with a blank child.
2. **`menu PAINTED base=0`, and `show()` did not help.** A real `QMenu` does not paint under the
   offscreen platform: its painting depends on the platform's popup handling. The row now draws the
   menu's OWN primitives (`PE_PanelMenu` plus `CE_MenuItem` per row) through the style -- the code
   path a slice would change -- rather than a row named "menu" that measured nothing while looking
   like a measurement.
3. **`METRIC menu sizeHint=-1x-1` and `sizeFromContents(CT_MenuItem)=109x129`.** A plain `QWidget`
   answers -1x-1, and the call was handed the WIDGET's size hint: "how big is an item" asked with the
   whole menu. The row has a size hint now, and each content type is given a text-sized box.
4. **`subElementRect(SE_TabBarTabText)=0,0,0,0`** for the tab, the list item and the header: a
   sub-element rect is computed FROM the option's rectangle, so an option without one reports a zero
   rectangle -- a number that reads as "the style has nothing to say" when it means "nobody asked".

**TWO FACTS ABOUT Qt 6 THAT CHANGED THE DESIGN**, both read out of `<QtWidgets/qstyle.h>` after the
compiler refused the guesses:

* **A button, a checkbox and a radio button are NOT complex controls.** There is no `CC_PushButton`,
  `CC_CheckBox` or `CC_RadioButton`, so `subControlRect` has nothing to answer for the most visible
  control on the desktop; their geometry is `subElementRect(SE_PushButtonBevel|SE_CheckBoxIndicator|
  SE_RadioButtonIndicator|...)`. The gallery reports BOTH families for that reason -- a table with
  only one of them would have left the button with no rectangle at all.
* **A sub-control only means something with its complex control.** Qt REUSES the values
  0x1/0x2/0x4/0x8 in every group, so `SC_SliderGroove`, `SC_ScrollBarAddLine` and `SC_ComboBoxFrame`
  are all `0x1`. A table keyed on the sub-control alone would print the WRONG NAME for two of the
  three, and the cases do not even compile as a plain `switch`.

**THE TABLE'S FIRST USE: nine controls have NO macOS reference.** `scrollbar`, `tabbar`, `menubar`,
`progressbar`, `listview-selected`, `tableheader` and the focus ring are not defined in the kit's
Sizes collection at all. They are DECLARED in the test (not only in this section), so the list cannot
grow silently and a slice cannot redraw one of them from taste. The first control to redraw is the
**push button**: the largest measured gap against a reference that EXISTS -- its height is 34 px
where the kit's `global` height is 24, **42% too tall** -- the most visible control on the desktop,
with its radius (6) and its padding (16) already in `tokens/tokens-sizes.toml`. Its risk is stated
with it: a button's size hint is every dialog's layout.

**A TRAP IN THE TEST ITSELF.** The per-widget assertion asked for a function called `renderUnder`,
which does not exist -- the gallery's is `renderOne`. The test was right to fail, because the contract
is the name; the fix was to correct the expectation, not to rename working code to satisfy a test.

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
  **Whether an install is pending is a MEASUREMENT, not a fact to write down**: a hash in a
  document expires the moment anything is rebuilt, so what goes here is how to read it.
  `md5sum effect-kwin/build/plugins/kwin/effects/macosglass2.so` against
  `md5sum /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so`; if they differ, an install is
  pending (`cd effect-kwin && ./install.sh`, then a relogin, or the hot path in §9u). The live test
  scripts refuse to measure a stale install for exactly this reason.
  **As of 2026-10-15 the two agreed** and no install was pending -- re-verify, do not quote this.
  What the tree carries is in the list at the end of this section.
- **The settings the user actually runs with** (read from `~/.config/kwinrc`, not assumed):
  `BackgroundRadius=24`, `CornerRadius=20`, `GlassAlpha=0.4`, and nothing else. That is a
  clear taste: a wider frost, rounder corners and LESS of the bar's own tone than the
  defaults (16 / 16 / 0.55). They were tuned against the build whose frost SAMPLED the
  backdrop; the reduced capture averages it, so the same numbers may read differently --
  re-tune by eye before baking any of them as the default.
- **The built `.so` was current as of 2026-10-15**, and it folds in everything the sessions that
  built it produced. Whether it still is is a measurement, not a sentence: the two `md5sum` lines
  above, and `./install.sh` + a relogin is what makes it real. The freshness guard refuses to
  measure until that is done. What it contains, in the order it was written:
  1. **Vibrancy**, off by default (`Vibrancy = 0`), a GLSL function called by BOTH the capture
     path and the no-capture fallback.
  2. **The capture cache**: one texture+framebuffer per distinct reduced size, LRU-evicted.
  3. **The journal-flood fix** in `prePaintWindow`, plus the diagnostic contract pinned.
  4. **The review fixes**: the pointer cleared before any early return, the reduced texture
     cleared before the blit, the no-capture fallback premultiplied like the main path, and
     corners no longer rounded on windows whose frame reaches the screen's edge.
  5. **`CaptureSubRect`**, the live switch for the one open question of step 3d.
  6. **The language pass**: the effect's identifiers and the harness's variables, labels and
     comments are English (the archive and the user's quotations are not, on purpose).
  Everything except vibrancy is behaviour-preserving with that key at its default, so the
  first thing to look at is that the band is unchanged; then the four questions in section 7.
- **Compiling without producing an artifact** is possible and is what these changes were
  checked with: `ninja -C build -t commands | grep glass.cpp` gives the exact compiler
  invocation, strip `-MD/-MT/-MF` and add `-fsyntax-only`. The compiler type-checks the
  file and NOTHING is written, so `build/*.so` (and therefore the freshness guard the live
  scripts depend on) is untouched. Useful when the user is mid-verification.
- No Apple material in version control. SF Pro is not redistributable; the project
  uses Inter (SIL OFL). The original brief stays in Spanish as `BRIEF-ORIGINAL.md`,
  sha256 `1f95c5239a3af3ef99614ff1104363a6e2c7799b4e1929d5eeba1053497bf5e1`.

## 10j. M6, slice 2: the push button, and the three facts of Qt that decided how

SLICE 2 redraws ONE control -- the push button -- and the contract has two halves: the button MUST
move, and the other sixteen primitives MUST NOT move a pixel. `tests/test-style-gallery.sh` asserts
both, and it asserts the button's new height against the token READ FROM THE FILE, not against a
number remembered here.

**The reference, with its provenance.**
`tokens/tokens-sizes.toml:88` `[global] height.medium = 24`, `:27` `[button] radius.medium = 6`,
`:24` `[button] padding_horizontal.medium = 16`. Mode `medium`, the one the typography slice took
too. What the base answered: `sizeHint=84x34` -- a button **42% taller** than the kit's. Ours:
`104x24`, where the width is the content plus twice the token's padding (84 + 2x(16-6)).

**Three facts of Qt 6 that changed the design, each read from the header AFTER the compiler refused
a guess:**
1. There is NO `PE_PushButtonBevel`. The bevel is `CE_PushButtonBevel`, a CONTROL element
   (`qstyle.h:172`); only `SE_PushButtonBevel` is a sub-element.
2. The bevel cannot be intercepted at the control element either: `QProxyStyle` chains to a SEPARATE
   base-style object, whose own `drawControl` calls dispatch to ITSELF, not to the proxy. The hook is
   therefore the whole `CE_PushButton`, and the label and the state decoration still come from the
   base.
3. `PM_ButtonMargin` is what the base adds around the text (6 px here). Sizing the button as "the
   content plus twice the token" WITHOUT subtracting it would have made the padding the base's plus
   ours -- a number nobody chose and nobody can point at a token for.

**The corner is a circular arc, and that is a measurement, not a preference.** The plan left open
whether a control's corner should reuse the window's clothoid. At a 6 px radius the two families
differ by less than the antialiasing: the kit's own corner at `smoothing = 0.6` fits an arc to 0.29 px
at 96 px, and at 6 px the single row that carries the difference is sub-pixel. A Fresnel integral in
the paint path of every button on the desktop to move a corner less than a pixel is not a trade this
project makes, so the arc is used and declared.

**The instrument lied twice before it told the truth, and both times the OUTPUT said so:**
* `DIFF -1` for the button. `differingPixels` returns -1 when the two images differ in SIZE, and they
  did: the canvas was sized from `sizeHint` -- the very number this slice changed (34 -> 24) -- so the
  two renders were 140x34 and 140x30, and the answer was "not comparable" where the question was "how
  different". The canvas is now the BASE's for BOTH passes, and the size change stays on the record as
  `METRICDIFF`.
* The baseline table wrote the BASE's metrics only, which would have shown this slice's button as
  34 px **after** it had been changed to 24. It now writes OURS as well, and that file is the
  "before" slice 3 will diff against.

**What is NOT verified:** the appearance in a real session. The gallery renders offscreen; the size
change is visible in the metrics and in the gallery's own image, but a button that is 24 px tall
inside EVERY dialog is a layout change only a session shows. `sizeHint` is the layout of every
dialog, and that risk was written down before the change, not after it.

## 10k. M7: the unified window chrome, the layer that owns each observation, and the prior art that was NOT established (2026-10-16)

M7 exists because the user put a real macOS Finder capture beside this desktop and named FOUR
differences. All four are real, and the milestone is written with the OWNER of each one, because the
first question a milestone like this has to answer is not "how" but "which layer is allowed to". Four
fixes without an owner would have made it the drawer everything is swept into.

**The bar is TWO bands today, and that is the decoration's `TitleHeight`, not a shader mistake.** Our
decoration is an Aurorae theme (`output/aurorae/KdeMacOS/`, generated by
`tools/generate-macos-decoration.py`), and `[Layout] TitleHeight=28` (`KdeMacOSrc:40`) is what makes
the frame reserve a strip above the client. `KDecoration3::Decoration` is the API that decides this:
`setBorders(QMarginsF)` sizes the frame around the client, `setTitleBar(QRectF)` places the buttons and
the caption, and the header's own comment says the title bar "is the area inside the Decoration
containing all controls (e.g. Buttons) and the caption"
(`/usr/include/KDecoration3/kdecoration3/decoration.h`). So the layer that can GIVE the strip away is
the decoration, and the layer that has to fill it is the application; the effect can only paint over
what it is given.

**The measurable half already exists, and it is M1's own expression.** The effect sizes its band as
`clientGeometry().top() - frameGeometry().top()` (`effect-kwin/src/glass.cpp:1030`), and its comment
already records the case that matters here: a window with client-side decoration reports
`frameGeometry() == clientGeometry()`, the difference is ZERO, and the effect then draws NO band
(`glass.cpp:1134`). M7's bar criterion is that same zero -- not a new instrument, and not a new meaning
for a number the effect already trusts. A decoration may still keep resize-only borders
(`Decoration::resizeOnlyBorders()`), and they do not show up in that difference.

**ONE PAIR OF NUMBERS DOES NOT RECONCILE, and the criterion deliberately uses neither.** M1's entry in
`docs/ROADMAP.md` records the strip as **39 rows** from the frame's top to the client's, and
`KdeMacOSrc`'s own comment says "the glass band is 39 px"; `glass.cpp`'s comment says **28 logical
pixels** for the same theme, and `TitleHeight=28` is the generated value. Which of the two is the
reserved strip is not settled here, and M7 does not need it: its criterion is the EXPRESSION, so a later
agent cannot hard-code 39 or 28 into it and be right by accident.

**The sidebar.** The decoration does not draw the client area: a sidebar's height and its material are
painted INSIDE the client, which starts below the frame's top border. So M7's sidebar is either the
application's own translucent surface, or the effect's material extended over that region (`Vibrancy`
and the capture path are already there), and the milestone says "the effect or the application" instead
of pretending one of them owns it. What IS measurable is the material: with the window held still and
only the background changed, a rectangle inside the sidebar must move by at least the threshold
`measure-glass.py` already applies to the band (12). The reference application is NOT chosen yet; the
one this repository already drives for M6 is Dolphin, and whether it carries a full-height sidebar is
part of the research.

**The shadow is not the effect's, and the kit already measured it.** `Decoration::setShadow()` and
`DecorationShadow` are how a window shadow reaches KWin; our theme enables it with `Shadow=true`
(`KdeMacOSrc:15`), and the effect must paint nothing into it -- an assertion M1 already makes. The kit
gives the shape as TWO layers: diffuse `radio = 54, offset_y = 18, alfa = 0.3` and contact
`radio = 1, alfa = 0.8` (`tokens/tokens-shape-effects.toml:85`), and the pair repeats under
`[ventana.sombra_estado]`, whose provenance is the interesting part:
`[Mode=Light, Active=True, Window Type=Unified Toolbar + Title] n=1` (`:102`) -- the kit's own
measurement set contains the unified window type this milestone is about. **HOW the shadow's width and
softness get measured is an OPEN DECISION and not a number**: nothing in this repository measures a
shadow, `measure-glass.py` only asserts that nothing was painted into it, and a threshold invented today
would be taste with a number on it.

**Margins and padding: M6's, linked and not copied.** They are measured by M6's gallery
(`tests/test-style-gallery.sh`), which reads the value from the token file instead of restating it, and
M7 points there. One gap is recorded rather than papered over: the kit's Sizes collection tokenises
CONTROL geometry -- `[button] padding_horizontal.medium = 16`, `[global] height.medium = 24` -- and has
no window, toolbar or sidebar margins at all, so whichever chrome margins M7 needs must be measured or
declared first.

**What is known about Qt, exactly.** Qt has `QMainWindow::setUnifiedTitleAndToolBarOnMac`, and Qt's own
documentation describes the property as the unified title-and-toolbar look **on macOS** ([Qt 6
QMainWindow](https://doc.qt.io/qt-6/qmainwindow.html#unifiedTitleAndToolBarOnMac-prop); the same wording
in the 5.15 archive). It is an application-level API: an application that never asks for it cannot be
given it by a style. This repository has NOT run the property on Wayland, so what is written here is the
documentation's own wording and the user's observation that it changes nothing on this session -- not a
claim about Qt's internals that was never tested.

**The prior art search: what it found, and what it did NOT establish.** The first pass found real,
macOS-styled decorations and Breeze forks: **Klassy** (a Breeze fork with a window decoration and an
application style: configurable titlebar margins, translucency and blur, and a "traffic lights" button
style), **SierraBreeze** ("a fork of Breeze Window decoration that aims to mimic the OSX Sierra titlebar
buttons"), and, named in its own acknowledgements, **Breezemite**, an Aurorae macOS-style decoration.
KDE bug reports about titlebar-button geometry came up as well. **NOT established, and this is the
point**: none of the sources read says that any of them RESERVES NO STRIP and draws its buttons over the
client area. Every one of them appears to keep a title bar and only change what is drawn inside it --
which is the difference between a macOS LOOK and macOS's unified chrome. Deciding it needs their source,
not their blurbs, and that is M7's first task.

**Open, in one list, so the next session starts here:**

* which KDE decorations reserve no strip, and what the KDecoration3 API lets a new one do -- read
  `/usr/include/KDecoration3/kdecoration3/decoration.h` first: `setBorders`, `setTitleBar`,
  `setResizeOnlyBorders`, `setShadow`;
* how far a Qt application that was never designed for a unified chrome cooperates -- dragging the
  window and double-clicking to maximize stop being the decoration's once its title bar is gone;
* which application is the reference, and whether it carries a full-height sidebar;
* how a shadow's width and softness are measured, if they are to be measured at all.

Links: [Klassy](https://github.com/paulmcauley/klassy),
[SierraBreeze](https://github.com/ishovkun/SierraBreeze),
[Breezemite](https://github.com/andreyorst/Breezemite),
[KDE bug 465621](https://bugs.kde.org/show_bug.cgi?id=465621),
[KDE bug 514600](https://bugs.kde.org/show_bug.cgi?id=514600),
[Qt 6 QMainWindow](https://doc.qt.io/qt-6/qmainwindow.html#unifiedTitleAndToolBarOnMac-prop).

## 10l. M6, slice 3: the checkbox and the radio button, off the palette, and a test that could not fail

**What the slice answers, and where each number comes from.** `pixelMetric` returns the kit's
indicator size and `drawPrimitive` draws `PE_IndicatorCheckBox` and `PE_IndicatorRadioButton`:
`[checkboxes] width = 16` (`tokens/tokens-sizes.toml:35`), `[checkboxes] radius.medium = 5.5` (:33),
`[radio] width.medium = 16` (:124), `[radio] width_dot.medium = 4.8` (:128), and the tick inside
`width_checkmark.medium = 9.31` / `height_checkmark.medium = 8.93` (:38, :31), taken as fractions of
the indicator so the glyph scales with the control instead of being drawn at the size it happened to
be measured at. The base answered `20x20` for both indicators, which is the +25% slice 1 measured.

**The accent is the palette's, and that is a requirement rather than a preference.** `KdeMacosDark`
is already generated and the plan makes every slice honour the active scheme; `Highlight` is the role
Qt itself spends on the accent, so the scheme's accent arrives without this file knowing which scheme
is active. A light constant here would be a second palette, and a second palette is how two palettes
drift apart.

**The one number the kit does not answer.** `[checkboxes]` gives the checkmark's BOX and no pen, so
the tick's stroke width (2) is named in the code as chosen rather than passed off as measured. It is
the only value in this slice without a token behind it.

**Trap 1: the slice-0 probe was asserting the no-op property on a control this slice owns.** It used
a `QCheckBox`, so it began exiting 5 the moment the checkbox moved. It now renders a `QProgressBar`,
which no DECLARED slice owns (the remaining ones are sliders/scrollbars, combos/tabs/menus, the
states and the tracking; `[progressbar]` has no reference in the kit at all). The controls that left
the probe are named in its comment, so they did not simply disappear.

**Trap 2, and the one worth remembering: `tests/test-style-gallery.sh` cannot be run on its own, and
running it directly made it PASS while asserting NOTHING.** It needs the harness that defines
`PROJECT` and the assertion functions; without them every `afirmar_*` is "command not found", the
script's exit code is whatever the last command left, and the run looks green. A deliberately broken
indicator size (20 instead of 16) therefore passed TWICE before the same break was run through
`tests/run.sh`, where it failed with six assertions -- including "our checkbox's indicator IS that
token", which is the one that names the token. The lesson is the repository's own, arriving from a new
direction: a test that can be green while measuring nothing is exactly what every instrument here
exists to catch, and this time the runner itself was the instrument that was lying. Run the suite,
never a test file.

**The instrument's numbers.** Five rows moved (`checkbox` 268 px, `checkbox-checked` 261,
`checkbox-disabled` 269, `radio` 252, `radio-checked` 252) and the other eleven are still zero;
`METRICDIFF` is non-zero for those five and zero for the rest. `CAMBIADOS` grew to eight rows, and the
"only the declared primitives report a moved value" check stopped being a count (which had to be kept
in step by hand) and became a property: every `OURS` line must belong to a declared row. The gallery's
evidence was regenerated: `evidence/2026-10-15-m6-gallery.png` and the baseline table.

## 10m. M5's errand: the icon theme the user already RUNS does not carry the measured radius (2026-10-16)

**The errand, and the question that replaced it.** M5 measured the macOS folder's body corner
(`[measure.folder]`: `R/S = 0.049 +- 0.01`, `R = 5.85 px` on a 120 px body) and could not APPLY it: the
generated global theme points at Breeze and an icon theme is not a milestone of this ROADMAP. The user
already runs a macOS-style icon theme -- `MacTahoe-light`, the one drawing the desktop's folders -- so
the errand's first question became whether that theme already carries the geometry. If it did, the
answer would be "nothing to apply", which is a RESULT and not a failure. **It does not**, and the gap
is now a number instead of a hunch.

**Which file, and why that one.** `~/.local/share/icons/MacTahoe-light/places/scalable/folder.svg`
(`places/` and the other icon contexts are symlinks into the sibling theme `MacTahoe`, so the three
`MacTahoe*` siblings draw the same artwork). It is the only macOS-style folder in the theme: the
`index.theme` says `places/scalable` is `Size=64`, `Type=Scalable`, `MinSize=32`, `MaxSize=512`, and
that is what a desktop icon size resolves to. The theme's `places/16`, `places/22` and `places/24`
carry a DIFFERENT folder -- a monochrome Breeze-style shape whose path is `ColorScheme-Text`, not the
blue one -- so the theme is not even consistent with itself below 32 px, and a measurement of any of
those three would have been a measurement of another shape. **The theme's files are read IN PLACE and
never copied, versioned or redistributed.** What travels is the measurement, exactly as with the
user's screenshots in `muestras/`.

**The tools.** `rsvg-convert` 2.63.2 (librsvg 2.63.2 on cairo 1.18.6) rasterizes the SVG -- the theme
is SVG, so it can be read -- and the raster is composed on white so the reader sees the same polarity
the Finder capture gave macOS. Then `tools/measure-icon-geometry.py`, whose `--self-test` was re-run
BEFORE any number: `R = 14, 20, 26` and the two small TOP-RIGHT radii the folder path needs
(`R = 5.0, 8.0`) all come back with **0.00 px** of error. The instrument is not the problem here.

**The number, and the two independent ways it was checked.** The visible corner is the SVG's BACK
shape's top-right one, a quarter-circle arc of `rx = 1.146` user units on a body `15.345` user units
wide -> **`R/S = 0.0747`**, i.e. `R = 8.12 px` on a 120 px canvas where the body is 108.75 px.

* the same reader on a **10x render** (1200 px, divided by 10): `R = 8.20 px`, `side = 108.8` ->
  `R/S = 0.0754`, residual 0.06 px at the 120 px scale. The two agree, and they are the value.
* what the tool answers on a LITERAL 120 px raster is `R = 7.30 px`, `side = 110` -> **`R/S = 0.0664`**
  (threshold 220, residual 0.53 px). That is **~12% low**, and the reason is a property of an 8 px
  corner in a 1 px raster: `corner_profile` takes its reference edge as an **INTEGER** pixel, and the
  corner's first row is only **62% covered**, so the profile starts one row into the corner. The token
  keeps it as `radius_ratio_at_120` rather than promoting it to the value -- this is the "the
  rasterization introduces its own alias" case, said out loud instead of reported as a measurement.

**Against the reference.** `0.075` against macOS's `0.049 +- 0.01`: about **1.5x rounder**, and it sits
OUTSIDE the reference's own window -- even the low 120 px read, `0.0664`, is above `0.059`. At the
reference's 120 px folder the theme draws `R ~ 9.0 px` where macOS draws `5.85 px`: **~3 px of radius
too much**. The verdict does not depend on which piece of the two-piece shape is called "the body":
the front panel's own corner is `1.058 / 15.345 = 0.0689`, still outside.

**Three traps, each of which produced a wrong number first.**
1. **The radius grid, which is M5's own trap arriving from a new direction.** The CLI's floor is 12 px
   and this corner is ~8: with the default grid the command prints `R = 12.00, err 5.23` and then
   "no icon fitted within 2.0 px" -- a grid edge answering the question. `--radius-min 2` is not a
   refinement, it is the difference between a measurement and a coincidence.
2. **The threshold, and this one is the theme's own artwork.** The theme draws a white highlight rim
   along the top edge, and it brightens the corner's FIRST row above 210. At `--threshold 210` the
   band finder skips that row, the profile starts one row into the corner, and the SAME file answers
   `R = 4.95 px`; at 220 the row is caught and it answers `7.30 px`. A **47% swing** from a threshold
   is not a measurement, which is the second reason the value above is not the 120 px raster's.
3. **The corner, and the piece nobody would guess.** `--corner tr` because a folder's TAB covers the
   top-left -- M5's own finding. But the shape is TWO pieces: a back shape carrying the tab, and a
   front panel whose top edge sits ~7.5 px lower. The front panel's own corner lies INSIDE the back
   shape's right edge (their right edges coincide to 0.002 user units), so it is an INTERNAL edge, and
   the instrument -- which reads the 0.5 crossing of the SILHOUETTE against the background -- cannot
   see it at all. There is exactly ONE corner to read there, and the profile confirms it: after the
   back's corner the inset goes to ~0 and stays there, with no second corner.

**Polarity, checked rather than assumed** (the trap the task named): dark folders on white give
`R/S = 0.0664` and the same icon lit on a dark background with `--polarity light` gives `0.0659` --
the same within the grid. The polarity is not what is wrong here.

**What was measured and what was rejected, counted.** Candidate files: **4** (`places/scalable`,
`places/24`, `places/22`, `places/16`); **1 measured**, **3 rejected** because they are a different
design (monochrome Breeze-style) and below the size a desktop folder is drawn at. Within the measured
icon: **1 corner measurable**, **1 rejected** as an internal edge (the front panel's). Raster readings:
**2**, of which **1 rejected as the value** (the literal 120 px read, ~12% low) and kept as a separate
token key. Fits: **1 icon, 0 rejected on residual** (0.53 px, well inside the 2 px tolerance). The
corner FAMILY is not resolved here either and is not claimed: at an 8 px radius a circle, the kit's
construction at any smoothing and a superellipse fit identically, exactly as §10f-bis found for macOS's.

**Two facts measured on the way, recorded so nobody chases them again.**
* **`qt.svg.draw: The requested buffer size is too big, ignoring` is NOT the QStyle.** It also appears
  with `QT_STYLE_OVERRIDE=Breeze`, and the style's own source carries no SVG, icon or pixmap code at
  all: `grep -niE 'svg|icon|pixmap' style-kde-macos/src/` gives **0** for `svg`, **0** for `pixmap`,
  and one `icon` hit, which is the comment naming `standardIcon` among the primitives the style
  deliberately does NOT override (`style-kde-macos/src/macosstyle.h:31`). It is preexisting environment
  noise from libQt6Svg drawing the icon theme's SVGs -- `INCIDENT.md` had already traced the message to
  `libQt6Svg` and called it secondary -- so it is not a symptom of anything in this repository.
* **Our global theme's `[kdeglobals][Icons] Theme` cannot stomp the user's choice.** The generated
  `contents/defaults` says `Theme=breeze`, and that lands in the **`kdedefaults` fallback layer**, not
  in the user's own file: measured on this machine, `~/.config/kdedefaults/kdeglobals` carries
  `[Icons] Theme=breeze` (written by the apply of 2026-10-15) while `~/.config/kdeglobals:144` still
  says `Theme=MacTahoe-light`. That is why the user keeps their icon theme although our package names
  `breeze`, and why the package does NOT have to solve the icon theme to be safe: a value there is a
  fallback, and the user's own value wins.

**So M5's errand STANDS, and it is no longer a blank one.** It has a number (`0.049`, where the theme
the user runs draws `0.075`), a size (at a 120 px folder that is ~3 px of radius) and a destination (a
theme of our own that draws the folder with the measured geometry). The value is pinned by
`tokens/tokens-icon-geometry.toml` `[measure.installed_theme]` and by `tests/test-icon-geometry.sh`,
which asserts the PROPERTY and not the sentence: the installed theme's figure must sit outside the
macOS figure's own window, and the low 120 px raster read must stay a separate, lower key.

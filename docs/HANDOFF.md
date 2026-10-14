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
- **The built `.so` is current as of this commit** (the tree and `build/` agree, 2026-10-14
  15:10, 123872 bytes), and it folds in everything this session produced while the user was
  away. `./install.sh` + a relogin is what makes it real, and the freshness guard will refuse
  to measure until that is done. What it contains, in the order it was written:
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

#include "glass.h"

#include <KPluginFactory>
#include <QLoggingCategory>
#include <QString>

#include <core/pixelgrid.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(MacosGlassEffect, "metadata.json",
                              return true;)

// ---------------------------------------------------------------------------
// M1.2 -- the diffusion shader.
//
// A box blur: for every pixel, average the texels in a square around it. That is
// the simplest thing that is genuinely a blur, and it is measurable -- local
// contrast drops while brightness is preserved (see measure-diffusion.py).
//
// Attribute and uniform names are KWin's, not invented:
//   in vec2 position   -- vertex position, set by GLVertexBuffer's VA_Position
//   in vec2 texcoord   -- texture coordinate, VA_TexCoord
//   uniform sampler2D sampler  -- the window's texture
//   uniform vec2 offset        -- a half-texel nudge KWin applies
// Confirmed by reading GLVertexBuffer's interleaved layout in glvertexbuffer.h
// and the uniform names in glshader.cpp.
//
// texcoord is used directly and NOT derived from position: how the texture maps
// onto the window is not guaranteed to be an identity, and assuming it is would
// make the blur sample the wrong places.
// ---------------------------------------------------------------------------
static const char *kDiffusionVertex = R"(
in vec2 position;
in vec2 texcoord;
out vec2 vTexCoord;
uniform mat4 modelViewProjectionMatrix;
uniform vec2 offset;

void main()
{
    vTexCoord = texcoord;
    gl_Position = modelViewProjectionMatrix * vec4(position + offset, 0.0, 1.0);
}
)";

static const char *kDiffusionFragment = R"(
uniform sampler2D sampler;
uniform sampler2D background;
uniform float uRadius;
uniform vec2 uTexelSize;
uniform vec2 uTextureSize;
uniform float uTitleBarHeight;
uniform float uGlassAlpha;
uniform float uHasBackground;
uniform float uBackgroundFlipV;
uniform float uBackgroundRadius;
uniform vec2 uBackgroundTexel;
in vec2 vTexCoord;
out vec4 fragColor;

void main()
{
    // THE MATERIAL COVERS THE CHROME, NOT THE CONTENT.
    //
    // Blurring the whole window was verified working and is unusable: it blurs
    // the text you are reading. macOS never does that -- its material covers the
    // title bar, toolbars and sidebars, and the content stays sharp.
    //
    // VERTICAL FLIP, and it was measured rather than assumed.
    //
    // The first version of this shader tested `vTexCoord.y * uTextureSize.y` as
    // the distance from the top of the window. The result was a blurred band at
    // the BOTTOM of every window -- the status bar, about 28 px up from the bottom
    // edge -- which is exactly where a 28 px band lands if vTexCoord.y is 0 at the
    // BOTTOM. The user's screenshot showed it plainly.
    //
    // OffscreenEffect renders the window into a texture whose v axis runs the
    // other way from window coordinates, so the distance from the window's top is
    // (1 - vTexCoord.y). The content sampling is left alone: it already reads the
    // right texel at the right place, so only the band test needed flipping.
    float yPixelsFromTop = (1.0 - vTexCoord.y) * uTextureSize.y;
    if (yPixelsFromTop > uTitleBarHeight) {
        fragColor = texture(sampler, vTexCoord);
        return;
    }

    // 9 taps in a 3x3 grid around the pixel, at a distance of uRadius texels.
    // Enough to be a real blur, few enough to stay cheap.
    vec4 sum = vec4(0.0);
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 d = vec2(float(x), float(y)) * uRadius * uTexelSize;
            sum += texture(sampler, vTexCoord + d);
        }
    }
    vec3 barColour = (sum / 9.0).rgb;

    // M1.3a -- THE DESKTOP ITSELF, NOT AN ALPHA.
    //
    // Writing uGlassAlpha as the alpha was measured OPAQUE: the shader's only input
    // was the window's own texture, and no alpha can put the desktop into a texture
    // that does not contain it. drawWindow() now captures the desktop into
    // `background` before the window is painted, and the composite happens HERE, so
    // the result does not depend on the scene blending our alpha at all.
    //
    // Compositing in the fragment shader also settles the ordering risk in
    // HANDOFF section 5: the band is drawn where the window is drawn, so there is no
    // second quad that could end up under the window.
    if (uHasBackground > 0.5) {
        // uBackgroundFlipV is 1.0 when the capture's v axis disagrees with the
        // window texture's. See glass.h: the default is the one that has to be
        // confirmed on screen.
        vec2 uvBackground = vec2(vTexCoord.x, mix(vTexCoord.y, 1.0 - vTexCoord.y, uBackgroundFlipV));

        // STEP 3a -- FROST: the same 3x3 kernel the bar uses, at the CAPTURE's texel
        // size (a different texture from the window's, so it has its own scale).
        //
        // Radius 0 takes the branch below and is the default, so the shipped
        // behaviour is exactly the sharp composite that step 2 verifies. Both branches
        // are kept separate on purpose: sampling the same texel nine times is not
        // literally the same float as sampling it once, and a default that is not
        // bit-identical to the verified one is a variable nobody asked for.
        vec3 desktop;
        if (uBackgroundRadius > 0.5) {
            vec4 suma = vec4(0.0);
            for (int x = -1; x <= 1; ++x) {
                for (int y = -1; y <= 1; ++y) {
                    vec2 d = vec2(float(x), float(y)) * uBackgroundRadius * uBackgroundTexel;
                    suma += texture(background, uvBackground + d);
                }
            }
            desktop = (suma / 9.0).rgb;
        } else {
            desktop = texture(background, uvBackground).rgb;
        }

        // The bar keeps uGlassAlpha of its own colour and lets the rest through:
        // that is the translucency macOS has.
        fragColor = vec4(mix(desktop, barColour, uGlassAlpha), 1.0);
        return;
    }

    // No capture available -- no framebuffer to read, blits unsupported, or the
    // window is off screen. Keep the previous behaviour rather than sample a
    // texture that was never filled.
    fragColor = vec4(barColour, uGlassAlpha);
}
)";

MacosGlassEffect::MacosGlassEffect()
{
    qInfo() << "[macos-glass] M1.2 loaded. frost radius" << kFrostRadius;

    connect(effects, &EffectsHandler::windowAdded, this, &MacosGlassEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &MacosGlassEffect::slotWindowDeleted);

    const auto windows = effects->stackingOrder();
    for (EffectWindow *w : windows) {
        slotWindowAdded(w);
    }

    effects->addRepaintFull();
}

MacosGlassEffect::~MacosGlassEffect() = default;

bool MacosGlassEffect::supported()
{
    // A shader-based effect needs OpenGL. Declaring support unconditionally would
    // make KWin load it on a software compositor and fail to draw.
    return effects->isOpenGLCompositing();
}

void MacosGlassEffect::reconfigure(ReconfigureFlags)
{
    // Read the settings. KWin gives effects their own config group, so these can be
    // changed without a rebuild:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key CsdBarHeight 70
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key FrostRadius 6
    //   qdbus6 org.kde.KWin /KWin reconfigure
    const KConfigGroup cfg = effects->config()->group(QStringLiteral("Effect-macosglass2"));
    m_frostRadius = cfg.readEntry("FrostRadius", kFrostRadius);

    // Only one of the two textures' orientations is unknown until it is seen on a
    // screen, so it is a setting rather than a guess baked into the source: if the
    // band shows the desktop upside down, flip it and reconfigure. No relogin.
    m_backgroundFlipV = cfg.readEntry("BackgroundFlipV", false);

    // The frost over the captured desktop, 0 by default: the first relogin verifies
    // the sharp composite, and this turns the blur on in the same session. See
    // glass.h for why a blur does not disturb the step-2 measurement (it preserves
    // the band's mean, which is what measure-glass.py compares).
    m_backgroundRadius = cfg.readEntry("BackgroundRadius", kBackgroundRadius);

    qInfo() << "[macos-glass] reconfigure: frostRadius=" << m_frostRadius
            << "backgroundFlipV=" << m_backgroundFlipV
            << "backgroundRadius=" << m_backgroundRadius;

    m_shader.reset();
    loadShader();
    if (m_active) {
        const auto windows = effects->stackingOrder();
        for (EffectWindow *w : windows) {
            redirect(w);
        }
    }
}

bool MacosGlassEffect::loadShader()
{
    if (m_shader) {
        return true;
    }
    // MapTexture: the shader receives the window's texture, which is what a
    // diffusion pass reads from.
    m_shader = ShaderManager::instance()->generateCustomShader(
        ShaderTrait::MapTexture,
        QByteArray(kDiffusionVertex),
        QByteArray(kDiffusionFragment));
    if (!m_shader) {
        qCritical() << "[macos-glass] the diffusion shader failed to load";
        return false;
    }
    return true;
}

void MacosGlassEffect::slotWindowAdded(EffectWindow *w)
{
    // DIAGNOSE: report every decision, so a silent no-op can be told apart from a
    // blur that is too subtle. The first M1.2 attempt produced no visible change
    // and no error, which is exactly the ambiguous case.
    static int logged = 0;
    const bool normal = w->isNormalWindow();

    if (!m_active || !normal) {
        if (logged < 8) {
            ++logged;
            qInfo() << "[macos-glass] DIAGNOSE skip" << w->caption()
                    << "active=" << m_active << "normal=" << normal;
        }
        return;
    }
    if (!loadShader()) {
        qInfo() << "[macos-glass] DIAGNOSE shader FAILED to load";
        return;
    }
    if (logged < 8) {
        ++logged;
        const QSize sz = w->frameGeometry().size().toSize();
        qInfo() << "[macos-glass] DIAGNOSE redirect" << w->caption()
                << "frameSize=" << sz
                << "texel=" << QVector2D(1.0f / (sz.width() ? sz.width() : 1),
                                         1.0f / (sz.height() ? sz.height() : 1));
    }
    // redirect() is what makes KWin render this window into an offscreen texture
    // so the shader can read it.
    redirect(w);
    qInfo() << "[macos-glass] REDIRECT" << w->caption().left(20);
    setShader(w, m_shader.get());

    // Tell the shader how big a texel is, so `uRadius` is expressed in texels
    // rather than in a normalised unit whose meaning changes with window size.
    //
    // CRITICAL: the shader must be BOUND while the uniforms are set.
    // GLShader::setUniform() is just glUniform1f(), which writes to whichever
    // program is currently active. Called without binding, it writes into some
    // other program and our uniforms stay at their default of zero -- and a blur
    // radius of zero makes all nine taps sample the SAME texel, so the average is
    // the original image and nothing changes on screen. That is exactly what was
    // measured: the mechanism ran, the shader was applied, and the picture was
    // identical. pushShader/popShader bind and restore.
    //
    // NOTE: this uses the logical frame size. On a display with scale != 1 the
    // offscreen texture is larger by that factor, so the blur would be
    // proportionally smaller than intended. The output here is scale 1, so it is
    // exact; making it scale-aware is a refinement for when one exists.
    const QSize size = w->frameGeometry().size().toSize();
    if (size.width() > 0 && size.height() > 0) {
        // The title bar height, measured rather than assumed: it is the distance
        // from the top of the frame to the top of the client area. This works for
        // ANY decoration theme, where a hard-coded value would only suit ours.
        // Measured on the KdeMacOS theme: 28 logical pixels.
        qreal barHeight = 0.0;
        if (w->hasDecoration()) {
            barHeight = w->clientGeometry().top() - w->frameGeometry().top();
        }
        // A window with client-side decoration (Zen Browser, most Electron apps)
        // reports frameGeometry() == clientGeometry(), so the difference is zero
        // and there is nothing to cover. KWin does not expose that region, so it
        // cannot be located without guessing -- and a guess was TRIED and removed:
        // it blurred a band on Zen Browser that the user did not want, on a window
        // whose own title bar cannot be measured. Better to do nothing than to
        // blur content on a guess.

        // The uniforms are NOT set here. The shader is a SINGLE object shared by
        // every window, so writing per-window values at add time means the last
        // window to be added wins: uTitleBarHeight would hold another window's
        // bar height, and every focus change would overwrite it. That is why the
        // material flickered away and came back when switching windows.
        // They are set in apply(), which runs per window on every paint.

        static int loggedBar = 0;
        if (loggedBar < 6) {
            ++loggedBar;
            // expanded= and shadowMargin= are here because they are the numbers the
            // material's geometry depends on and they CANNOT be reasoned out: the
            // redirected texture is expandedGeometry()*scale, so every size the
            // shader uses is only exact if the decoration's shadow margins are zero.
            // This theme sets Shadow=true and ships no shadow.svg, which may or may
            // not mean "no shadow" -- so it is logged, not assumed. (The capture line
            // logs the texture size too, so the two together settle it either way.)
            const RectF expandido = w->expandedGeometry();
            const RectF marco = w->frameGeometry();
            qInfo() << "[macos-glass] title bar band:" << w->caption()
                    << "frame=" << marco
                    << "client=" << w->clientGeometry()
                    << "expanded=" << expandido
                    << "shadowMargin=" << QPointF(marco.x() - expandido.x(),
                                                  marco.y() - expandido.y())
                    << "barHeight=" << barHeight;
        }
    }
}

void MacosGlassEffect::slotWindowDeleted(EffectWindow *w)
{
    qInfo() << "[macos-glass] UNREDIRECT (window deleted)" << w->caption().left(20);
    unredirect(w);
}

bool MacosGlassEffect::captureBackground(const RenderTarget &renderTarget,
                                         const RenderViewport &viewport, EffectWindow *w)
{
    if (!m_active || !w->isNormalWindow() || !w->hasDecoration()) {
        return false;
    }
    // No shader means apply() returns before drawing the band, so a capture would be
    // work whose result nobody reads.
    if (!m_shader) {
        return false;
    }
    // Reading from a QImage render target is not possible with a framebuffer blit.
    GLFramebuffer *sourceFbo = renderTarget.framebuffer();
    if (!sourceFbo) {
        return false;
    }
    // CAPTURE THE **EXPANDED** GEOMETRY, NOT THE FRAME, and this is not a detail.
    //
    // KWin redirects the window into a texture of expandedGeometry() * scale
    // (offscreeneffect.cpp, OffscreenData::maybeRender) -- the frame PLUS the
    // decoration's shadow margins -- and the shader's vTexCoord runs 0..1 across
    // that whole texture. Capturing only the frame would therefore map a frame-sized
    // texture onto expanded-sized coordinates: the desktop would be sampled shifted
    // by the top/left shadow margin and scaled by expanded/frame. The band would show
    // the wrong part of the background, and it would look like a uv or flip bug.
    //
    // snapToPixels is KWin's own rounding to the device grid, the same call
    // maybeRender uses, so the captured region is the texture's region and not
    // approximately it.
    const Rect region = snapToPixels(w->expandedGeometry(), viewport.scale()).toRect();
    if (region.isEmpty()) {
        return false;
    }

    // RISK, handled rather than hoped for: expandedGeometry() of a MAXIMISED window is
    // the whole screen plus its shadow, and a window dragged past the edge goes
    // outside it. A blit with an out-of-bounds source is undefined behaviour, so the
    // source is clamped to the render target's logical rect. What is left of the
    // destination is then offset by the same amount, which is why the two are
    // computed separately.
    const Rect source = region.intersected(viewport.renderRect().toRect());
    if (source.isEmpty()) {
        return false;
    }

    // DEVICE pixels, not logical ones: at scale != 1 the texture must be larger than
    // the logical geometry. mapToRenderTargetTexture is KWin's own
    // logical-to-texture transform, so this is not arithmetic done by hand.
    const Rect regionDevice = viewport.mapToRenderTargetTexture(region);
    const QSize size = regionDevice.size();
    if (size.isEmpty()) {
        return false;
    }

    if (!m_background || m_backgroundSize != size) {
        m_background = GLTexture::allocate(GL_RGBA8, size);
        if (!m_background) {
            m_backgroundFbo.reset();
            m_backgroundSize = QSize();
            qWarning() << "[macos-glass] cannot allocate the capture texture" << size;
            return false;
        }
        m_background->setFilter(GL_LINEAR);
        m_background->setWrapMode(GL_CLAMP_TO_EDGE);
        m_backgroundFbo = std::make_unique<GLFramebuffer>(m_background.get());
        if (!m_backgroundFbo->valid()) {
            m_backgroundFbo.reset();
            m_background.reset();
            m_backgroundSize = QSize();
            qWarning() << "[macos-glass] the capture framebuffer is not valid";
            return false;
        }
        m_backgroundSize = size;
        qInfo() << "[macos-glass] capture texture" << size
                << "for" << w->caption().left(20);
    }

    const Rect sourceDevice = viewport.mapToRenderTargetTexture(source);
    const Rect destination(sourceDevice.topLeft() - regionDevice.topLeft(), sourceDevice.size());

    // blitFromFramebuffer reads from the CURRENT framebuffer. It already is the
    // source while the scene is drawn; pushing it says so instead of assuming it.
    GLFramebuffer::pushFramebuffer(sourceFbo);
    const bool ok = m_backgroundFbo->blitFromRenderTarget(renderTarget, viewport, source, destination);
    GLFramebuffer::popFramebuffer();

    if (!ok) {
        // Not fatal and not silent: the shader falls back to the alpha-only band.
        static int avisos = 0;
        if (avisos < 4) {
            ++avisos;
            qWarning() << "[macos-glass] the background blit was refused for"
                       << w->caption().left(20)
                       << "-- blits unsupported on this GL context?";
        }
    }

    // DIAGNOSE the verifier's question, because the answer costs a relogin.
    //
    // Every other instrument here needs a screen, and this one line decides which
    // of two very different problems you are looking at after logging back in:
    //   ok climbing          -> the desktop IS being captured, so a wrong-looking
    //                           band is a COMPOSITE problem (uv, alpha, colour)
    //   refused climbing     -> there is no capture at all and the band is the old
    //                           opaque alpha path; the GL context cannot blit
    // Without it, "the band looks wrong" and "there was never a band" read the same
    // in the journal, and finding out costs another session.
    static int capturasOk = 0;
    static int capturasRechazadas = 0;
    if (ok) {
        ++capturasOk;
    } else {
        ++capturasRechazadas;
    }
    const int intentos = capturasOk + capturasRechazadas;
    if (intentos == 60 || (intentos % 300) == 0) {
        qInfo() << "[macos-glass] capture: ok=" << capturasOk
                << "refused=" << capturasRechazadas;
    }
    return ok;
}

void MacosGlassEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                                  EffectWindow *w, int mask, const Region &deviceRegion,
                                  WindowPaintData &data)
{
    // THE CAPTURE HAPPENS HERE, AND BEFORE THE BASE CLASS RUNS.
    //
    // apply() is where the shader's uniforms live, but it never receives the render
    // target, so it cannot capture anything. At this point the screen still holds
    // the DESKTOP: OffscreenEffect::drawWindow is what paints the window over it.
    //
    // The base class is called on the ONLY path out of this function. That is not
    // decoration: verify-chain.sh checks it, and an early return here is the exact
    // shape of the two black screens this project already paid for (HANDOFF §3).
    m_hasBackground = captureBackground(renderTarget, viewport, w);
    OffscreenEffect::drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

void MacosGlassEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
{
    // DIAGNOSE: is this called at all? If it is not, setTranslucent() never runs
    // and the shader's alpha is ignored -- which is exactly what the measurement
    // shows (opaque over a dark and a light background, difference 3.2).
    static int pre = 0;
    if (pre < 6) {
        ++pre;
        qInfo() << "[macos-glass] prePaintWindow" << w->caption().left(20)
                << "normal=" << w->isNormalWindow() << "active=" << m_active;
    }
    if (m_active && w->isNormalWindow()) {
        // The scene blends a window only if it is told the window is translucent.
        // The shader writing an alpha is not enough on its own.
        data.setTranslucent();
        if (pre <= 6) {
            qInfo() << "[macos-glass] setTranslucent called for" << w->caption().left(20);
        }
    }
    // Continue the chain: prePaintWindow must re-enter it like the others.
    OffscreenEffect::prePaintWindow(view, w, data);
}

void MacosGlassEffect::apply(EffectWindow *w, int mask, WindowPaintData &data, WindowQuadList &quads)
{
    Q_UNUSED(w)
    Q_UNUSED(mask)
    Q_UNUSED(quads)
    // The material is a shader over the redirected texture, so the geometry itself
    // is untouched. M1.3 (refraction) will deform quads here.
    Q_UNUSED(data)

    // RE-ASSERT THE SHADER ON EVERY PAINT.
    //
    // setShader() was called once, when the window was added. The effect then
    // vanished as soon as the window was moved or focus changed: KWin repaints a
    // window on those events, and the paint path does not necessarily keep the
    // shader that was registered at add time. apply() is called by
    // OffscreenEffect::drawWindow on EVERY paint, just before the texture is
    // drawn, so this is the place that keeps it applied.
    //
    // Diagnose counter: if the band disappears while this keeps counting, the
    // shader is being overwritten elsewhere and that is the place to look.
    // Count apply() calls PER WINDOW, and log a periodic summary. The symptom to
    // chase is a window that HAD the material and lost it when another window was
    // created. A single global counter cannot show that: what matters is whether
    // apply() keeps being called for a window that is still on screen.
    static QHash<QString, int> counts;
    static int total = 0;
    const QString key = w->caption();
    ++counts[key];
    ++total;
    if (total == 200 || (total % 300) == 0) {
        QString resumen;
        for (auto it = counts.constBegin(); it != counts.constEnd(); ++it) {
            resumen += QStringLiteral("[%1 x%2] ").arg(it.key().left(14)).arg(it.value());
        }
        qInfo() << "[macos-glass] apply() totals:" << resumen;
    }
    if (!m_shader) {
        return;
    }
    setShader(w, m_shader.get());

    // Uniforms belong here, not in slotWindowAdded: one shader object is shared by
    // all windows, so anything written once at add time is a global that the next
    // window overwrites. Setting them per paint makes each window's band its own.
    const QSize size = w->frameGeometry().size().toSize();
    if (size.width() <= 0 || size.height() <= 0) {
        return;
    }
    qreal barHeight = 0.0;
    if (w->hasDecoration()) {
        barHeight = w->clientGeometry().top() - w->frameGeometry().top();
    }
    if (barHeight < 0.0) {
        barHeight = 0.0;
    }

    ShaderManager::instance()->pushShader(m_shader.get());
    m_shader->setUniform("uRadius", float(m_frostRadius));
    m_shader->setUniform("uTexelSize",
                         QVector2D(1.0f / size.width(), 1.0f / size.height()));
    m_shader->setUniform("uTextureSize",
                         QVector2D(float(size.width()), float(size.height())));
    m_shader->setUniform("uTitleBarHeight", float(barHeight));
    m_shader->setUniform("uGlassAlpha", kGlassAlpha);
    m_shader->setUniform("uBackgroundFlipV", m_backgroundFlipV ? 1.0f : 0.0f);
    m_shader->setUniform("uBackgroundRadius", float(m_backgroundRadius));

    // The captured desktop goes on texture unit 1: unit 0 is the window's own
    // texture, bound by KWin. The texture is NOT unbound afterwards on purpose --
    // apply() runs BEFORE the draw, so unbinding here would leave the draw without
    // its background. Leaving it bound on a unit KWin does not use for the window is
    // the smaller risk, and unit 0 is made active again for whoever draws next.
    const bool conFondo = m_hasBackground && m_background;
    if (conFondo) {
        glActiveTexture(GL_TEXTURE0 + 1);
        m_background->bind();
        m_shader->setUniform("background", 1);
        glActiveTexture(GL_TEXTURE0);
        // The capture's own texel size, so the frost radius is in TEXELS of the
        // texture it samples. Using the window's uTexelSize here would be a 3% lie
        // (frame vs expanded) and there is no reason to accept it.
        if (m_backgroundSize.width() > 0 && m_backgroundSize.height() > 0) {
            m_shader->setUniform("uBackgroundTexel",
                                 QVector2D(1.0f / m_backgroundSize.width(),
                                           1.0f / m_backgroundSize.height()));
        }
    }
    m_shader->setUniform("uHasBackground", conFondo ? 1.0f : 0.0f);
    ShaderManager::instance()->popShader();
}

} // namespace KWin

#include "glass.moc"

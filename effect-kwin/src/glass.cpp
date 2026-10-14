#include "glass.h"

#include <KPluginFactory>
#include <QLoggingCategory>
#include <QString>

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
uniform float uRadius;
uniform vec2 uTexelSize;
uniform vec2 uTextureSize;
uniform float uTitleBarHeight;
uniform float uGlassAlpha;
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
    // Translucent: this is what lets the desktop behind the window show through,
    // and it is the difference between a smudged bar and a glass one.
    fragColor = vec4((sum / 9.0).rgb, uGlassAlpha);
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

    qInfo() << "[macos-glass] reconfigure: frostRadius=" << m_frostRadius;

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
            qInfo() << "[macos-glass] title bar band:" << w->caption()
                    << "frame=" << w->frameGeometry()
                    << "client=" << w->clientGeometry()
                    << "barHeight=" << barHeight;
        }
    }
}

void MacosGlassEffect::slotWindowDeleted(EffectWindow *w)
{
    qInfo() << "[macos-glass] UNREDIRECT (window deleted)" << w->caption().left(20);
    unredirect(w);
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
    ShaderManager::instance()->popShader();
}

} // namespace KWin

#include "glass.moc"

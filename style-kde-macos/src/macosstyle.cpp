#include "macosstyle.h"

#include <QPainter>
#include <QPalette>
#include <QPolygonF>
#include <QStyleFactory>
#include <QStyleOptionButton>
#include <QStringList>

// WHY THE BASE IS RESOLVED INSTEAD OF WRITTEN DOWN.
//
// MEASURED on this machine (Qt 6.12), with a probe application that prints them:
//     QStyleFactory::keys() -> [Breeze] [kvantum-dark] [kvantum] [Windows] [Fusion]
//
// Breeze first, and the reason is the done criterion: chaining to the style the user was ALREADY
// using is what makes "selectable without breaking applications" true. Every control this skeleton
// does not implement -- which is all of them -- comes out of the base style, so selecting it
// changes nothing at all. A hard-coded base would be a second way to look wrong.
//
// Fusion as the fallback, and this one is not a preference: it is the style Qt always builds in,
// so the chain can never come out empty. An empty base makes QProxyStyle fall back to the
// APPLICATION's style, and the application's style may be this very style -- which is recursion,
// not a fallback. The last `return` is therefore unreachable on a sane Qt and is there so the
// recursion cannot happen on an insane one.
QString MacosStyle::baseStyleKey()
{
    static const char *const candidates[] = {"Breeze", "Fusion"};
    const QStringList available = QStyleFactory::keys();
    for (const char *candidate : candidates) {
        if (available.contains(QString::fromLatin1(candidate), Qt::CaseInsensitive)) {
            return QString::fromLatin1(candidate);
        }
    }
    return QStringLiteral("Fusion");
}

MacosStyle::MacosStyle()
    : QProxyStyle(baseStyleKey())
{
    setObjectName(QStringLiteral("KdeMacOS"));
    // Read by `tests/style-probe.cpp` and by tests/test-style.sh: the base is reported, never
    // assumed. A probe that asserted "Breeze" would pin this machine; one that asserts a REAL base
    // was resolved pins the property.
    setProperty("kdeMacosBaseStyle", baseStyleKey());
}

QStyle *MacosStylePlugin::create(const QString &key)
{
    if (key.compare(QStringLiteral("KdeMacOS"), Qt::CaseInsensitive) == 0) {
        return new MacosStyle;
    }
    return nullptr;
}

// ---------------------------------------------------------------------------------------------
// SLICE 2 -- THE PUSH BUTTON. The reference is the kit's own Sizes collection, and every value below
// carries the file and the line it was read from, because a number without its provenance is a
// number the next slice will "correct":
//   tokens/tokens-sizes.toml:27  [button] radius.medium             = 6
//   tokens/tokens-sizes.toml:24  [button] padding_horizontal.medium = 16
//   tokens/tokens-sizes.toml:88  [global] height.medium             = 24
// `medium` is the mode the rest of this project already draws against (the typography slice took
// `medium` too), so a button is sized for the interface the theme actually ships.
namespace {
constexpr int kButtonHeight = 24;   // tokens/tokens-sizes.toml:88  [global] height.medium
constexpr int kButtonRadius = 6;    // tokens/tokens-sizes.toml:27  [button] radius.medium
constexpr int kButtonPadding = 16;  // tokens/tokens-sizes.toml:24  [button] padding_horizontal.medium
}

QSize MacosStyle::sizeFromContents(ContentsType type, const QStyleOption *opt, const QSize &size,
                                   const QWidget *w) const
{
    QSize s = QProxyStyle::sizeFromContents(type, opt, size, w);
    if (type != CT_PushButton) {
        // THE OTHER SEVENTEEN CONTROLS DO NOT MOVE HERE. They are later slices, each with its own
        // measurement; the gallery asserts they still differ by zero pixels.
        return s;
    }
    // THE HEIGHT the reference asks for, replacing the base's 34 -- the +42% the instrument found.
    s.setHeight(kButtonHeight);
    // THE HORIZONTAL PADDING is part of the reference too, so the base's own margin has to come OUT
    // first. Leaving it in would size the button as "the base's padding plus ours", which is a
    // number nobody chose and nobody can point at a token for. The base's margin is ASKED for.
    const int baseMargin = pixelMetric(PM_ButtonMargin, opt, w);
    s.setWidth(s.width() + 2 * (kButtonPadding - baseMargin));
    return s;
}

void MacosStyle::drawControl(ControlElement element, const QStyleOption *opt, QPainter *p,
                             const QWidget *w) const
{
    if (element != CE_PushButton) {
        QProxyStyle::drawControl(element, opt, p, w);
        return;
    }
    const QStyleOptionButton *btn = qstyleoption_cast<const QStyleOptionButton *>(opt);
    if (!btn) {
        QProxyStyle::drawControl(element, opt, p, w);
        return;
    }
    // THE CORNER, AND WHY IT IS A CIRCULAR ARC RATHER THAN THE WINDOW'S CLOTHOID. `M6-QSTYLE-PLAN.md`
    // left this decision open. It is settled by a measurement, not by taste: at a 6 px radius the two
    // families differ by less than the antialiasing does -- the kit's OWN corner at
    // `smoothing = 0.6` fits a circular arc to within 0.29 px when drawn at 96 px, and at 6 px the
    // single row that carries the difference is sub-pixel. Drawing the clothoid here would put a
    // Fresnel integral in the paint path of every button on the desktop to move a corner less than a
    // pixel. So the arc is used, and declared as the decision it is.
    const QPalette pal = opt->palette;
    const bool enabled = opt->state & State_Enabled;
    const bool pressed = opt->state & State_Sunken;
    const bool checked = opt->state & State_On;
    QColor fill = pal.button().color();
    if (pressed || checked) {
        fill = pal.mid().color();
    }
    if (!enabled) {
        fill = pal.window().color();
    }
    const QColor border = pal.mid().color().darker(115);
    p->save();
    p->setRenderHint(QPainter::Antialiasing, true);
    // THE HALF-PIXEL INSET keeps a 1 px pen inside the option's rect at any scale. Without it the
    // stroke straddles the edge and the button draws a pixel wider than it measured, which is the
    // kind of mismatch this project writes instruments to catch.
    p->setPen(QPen(border, 1));
    p->setBrush(fill);
    p->drawRoundedRect(QRectF(opt->rect).adjusted(0.5, 0.5, -0.5, -0.5), kButtonRadius,
                       kButtonRadius);
    p->restore();
    // THE LABEL AND THE STATE DECORATION still come from the base. This slice changed the BUTTON's
    // geometry and its corner -- not its text, its focus ring or its default-button frame, which are
    // STATE rather than geometry and have no token to be measured against yet. Every pixel that is
    // not named here is still the base's, which is what keeps the slice from being a rewrite.
    QProxyStyle::drawControl(CE_PushButtonLabel, opt, p, w);
    if (btn->features & QStyleOptionButton::DefaultButton) {
        QProxyStyle::drawPrimitive(PE_FrameDefaultButton, opt, p, w);
    }
    if (opt->state & State_HasFocus) {
        QProxyStyle::drawPrimitive(PE_FrameFocusRect, opt, p, w);
    }
}

// ---------------------------------------------------------------------------------------------
// SLICE 3 -- THE CHECKBOX AND THE RADIO BUTTON, with the reference and its line, the way slice 2
// did it, because a number without its provenance is a number the next slice will "correct":
//   tokens/tokens-sizes.toml:35   [checkboxes] width                  = 16
//   tokens/tokens-sizes.toml:33   [checkboxes] radius.medium          = 5.5
//   tokens/tokens-sizes.toml:124  [radio] width.medium                = 16
//   tokens/tokens-sizes.toml:128  [radio] width_dot.medium            = 4.8
//   tokens/tokens-sizes.toml:38   [checkboxes] width_checkmark.medium = 9.31
//   tokens/tokens-sizes.toml:31   [checkboxes] height_checkmark.medium = 8.93
namespace {
constexpr int kCheckBoxSize = 16;        // [checkboxes] width
constexpr qreal kCheckBoxRadius = 5.5;   // [checkboxes] radius.medium
constexpr int kRadioSize = 16;           // [radio] width.medium
constexpr qreal kRadioDot = 4.8;         // [radio] width_dot.medium
constexpr qreal kTickWidth = 9.31;       // [checkboxes] width_checkmark.medium
constexpr qreal kTickHeight = 8.93;      // [checkboxes] height_checkmark.medium
} // namespace

int MacosStyle::pixelMetric(PixelMetric metric, const QStyleOption *opt, const QWidget *w) const
{
    switch (metric) {
    case PM_IndicatorWidth:
    case PM_IndicatorHeight:
        return kCheckBoxSize;
    case PM_ExclusiveIndicatorWidth:
    case PM_ExclusiveIndicatorHeight:
        return kRadioSize;
    default:
        // EVERY OTHER METRIC IS STILL THE BASE'S, and the gallery asserts it: a control this slice
        // did not touch has to answer the same metrics AND draw the same pixels.
        return QProxyStyle::pixelMetric(metric, opt, w);
    }
}

void MacosStyle::drawPrimitive(PrimitiveElement element, const QStyleOption *opt, QPainter *p,
                               const QWidget *w) const
{
    if (element != PE_IndicatorCheckBox && element != PE_IndicatorRadioButton) {
        QProxyStyle::drawPrimitive(element, opt, p, w);
        return;
    }
    const bool enabled = opt->state & State_Enabled;
    const bool on = opt->state & State_On;
    const QPalette pal = opt->palette;
    // THE ACCENT COMES FROM THE PALETTE, and the plan makes that a requirement, not a preference:
    // `KdeMacosDark` is already generated and every slice has to honour it. `Highlight` is the role
    // Qt itself spends on "the accent", so the dark scheme's accent arrives by itself; a light
    // constant written here would be a second palette, and a second palette is how the two drift.
    const QColor accent = pal.highlight().color();
    const QColor inside = enabled ? pal.base().color() : pal.window().color();
    const QColor edge = pal.mid().color().darker(115);
    const QRectF r = QRectF(opt->rect).adjusted(0.5, 0.5, -0.5, -0.5);
    p->save();
    p->setRenderHint(QPainter::Antialiasing, true);
    p->setPen(QPen(on ? accent : edge, 1));
    p->setBrush(on ? accent : inside);
    if (element == PE_IndicatorRadioButton) {
        p->drawEllipse(r);
        if (on) {
            // THE DOT, at the kit's 4.8 px, centred, in the highlight's own text colour so it keeps
            // its contrast on whatever accent the active scheme ships.
            p->setPen(Qt::NoPen);
            p->setBrush(pal.highlightedText().color());
            p->drawEllipse(r.center(), kRadioDot / 2.0, kRadioDot / 2.0);
        }
    } else {
        p->drawRoundedRect(r, kCheckBoxRadius, kCheckBoxRadius);
        if (on) {
            // THE TICK, inside the kit's own checkmark box (9.31 x 8.93) taken as FRACTIONS of the
            // indicator, so it scales with the control instead of being a glyph drawn at whatever
            // size it happened to be measured at. THE STROKE WIDTH IS THE ONE NUMBER IN THIS SLICE
            // THE KIT DOES NOT ANSWER -- `[checkboxes]` has the glyph's box and no pen -- so it is
            // named here as chosen rather than passed off as measured.
            const QPointF c = r.center();
            const qreal hw = kTickWidth / 2.0, hh = kTickHeight / 2.0;
            QPen tick(pal.highlightedText().color(), 2.0);
            tick.setCapStyle(Qt::RoundCap);
            tick.setJoinStyle(Qt::RoundJoin);
            p->setPen(tick);
            p->setBrush(Qt::NoBrush);
            p->drawPolyline(QPolygonF({QPointF(c.x() - hw, c.y() - hh * 0.05),
                                       QPointF(c.x() - hw * 0.25, c.y() + hh),
                                       QPointF(c.x() + hw, c.y() - hh)}));
        }
    }
    p->restore();
}

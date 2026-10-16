// style-kde-macos — the M6 QStyle, FIRST SLICE.
//
// WHAT THIS IS. A Qt 6 widget style plugin that Qt can select by the key "KdeMacOS", and whose
// style is a `QProxyStyle` chained to a base style. The plan behind the slice is in
// `docs/M6-QSTYLE-PLAN.md`; the short version is here, next to the code it explains.
//
// WHY IT OVERRODE NOTHING IN SLICE 0, ON PURPOSE. M6's done criterion is "it exists, is installed
// and is selectable WITHOUT BREAKING APPLICATIONS". A skeleton that redraws one button and delegates
// the rest breaks applications in the one place nobody looks, and it cannot be told apart from a
// skeleton that works. So slice 0 implemented no primitive at all: every pixel an application drew
// came from the base style, and selecting it was a no-op by construction. `tests/test-style.sh`
// pinned that absence -- it was the property, not a TODO.
//
// SLICE 2 OVERRIDES EXACTLY TWO THINGS, and this list is the contract: `sizeFromContents` (the
// button's height and horizontal padding) and `drawControl` (its corner, drawn for CE_PushButton).
// Every other primitive still delegates, and `tests/test-style-gallery.sh` asserts that the other
// seventeen controls have not moved a single pixel. An override that is not named here is a change
// nobody measured.
//
// WHY `drawControl` AND NOT `drawPrimitive`: Qt 6 has NO `PE_PushButtonBevel` (measured in
// <QtWidgets/qstyle.h>: the bevel is `CE_PushButtonBevel`, a CONTROL element, with only a
// `SE_PushButtonBevel` sub-element). And the bevel cannot be intercepted at the control element
// either: `QProxyStyle` chains to a SEPARATE base-style object, whose own `drawControl` calls
// dispatch to itself. So the hook is the whole `CE_PushButton`.
#pragma once

#include <QProxyStyle>
#include <QString>
#include <QStylePlugin>

// The style itself. `drawComplexControl`, `subElementRect`, `standardIcon` and `styleHint` are
// still NOT overridden: each needs its own slice and its own measurement, and `tests/test-style.sh`
// still expects those to be absent -- it names the landed ones AND the absent ones, so an override
// nobody measured cannot appear quietly.
class MacosStyle : public QProxyStyle
{
    Q_OBJECT
public:
    MacosStyle();

    // The base style this one chains to, resolved from what Qt actually offers. Public and static
    // so the probe can report which base was chosen instead of the test guessing.
    static QString baseStyleKey();

    // SLICE 2 -- the push button's geometry comes from `tokens/tokens-sizes.toml`, not from taste.
    QSize sizeFromContents(ContentsType type, const QStyleOption *opt, const QSize &size,
                           const QWidget *w) const override;
    void drawControl(ControlElement element, const QStyleOption *opt, QPainter *p,
                     const QWidget *w) const override;

    // SLICE 3 -- the checkbox and the radio button. `pixelMetric` answers the indicator's size (the
    // kit says 16 where the base answered 20, the +25% the instrument measured) and `drawPrimitive`
    // draws the two indicators, so the accent of the "on" state is READ FROM THE PALETTE and the
    // dark scheme arrives by itself instead of a light constant being copied here.
    int pixelMetric(PixelMetric metric, const QStyleOption *opt = nullptr,
                    const QWidget *w = nullptr) const override;
    void drawPrimitive(PrimitiveElement element, const QStyleOption *opt, QPainter *p,
                       const QWidget *w) const override;
};

// The plugin Qt's QStyleFactory finds and calls. The IID must be the one Qt itself declares --
// `QStyleFactoryInterface_iid`, defined in <QStylePlugin> -- and the `Keys` array in
// metadata.json is the list of names `QStyleFactory::create()` matches against.
class MacosStylePlugin : public QStylePlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QStyleFactoryInterface_iid FILE "metadata.json")
public:
    QStyle *create(const QString &key) override;
};

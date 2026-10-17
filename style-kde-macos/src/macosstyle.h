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

// The selection's option is only a reference in the declaration below, so the include is in the .cpp
// and this is enough here.
class QStyleOptionViewItem;

// The style itself. `subElementRect`, `standardIcon` and `styleHint` are still NOT overridden: each
// needs its own slice and its own measurement, and `tests/test-style.sh` still expects those to be
// absent -- it names the landed ones AND the absent ones, so an override nobody measured cannot
// appear quietly.
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

    // SLICE 4 -- the slider. `pixelMetric` answers the knob's thickness and length from the kit (16
    // and 20, where the base answered 20 and 20) and `drawComplexControl` draws CC_Slider, because a
    // slider is a COMPLEX control: its groove and its handle are sub-controls, and the base's own
    // `subControlRect` picks up the new metrics by itself, so the geometry needs no second copy.
    void drawComplexControl(ComplexControl control, const QStyleOptionComplex *opt, QPainter *p,
                            const QWidget *w) const override;

    // SLICE 5 -- the menus and the combo.
    //
    // `sizeFromContents(CT_MenuItem)` answers the KIT's item height (24, where the base drew 29:
    // the +21% the instrument measured). It is the kit's figure and NOT a macOS measurement, and the
    // token says so out loud -- no capture in `muestras/` has an open menu, so the reference could
    // not be checked against Apple and the test PINS that it is unchecked rather than letting it
    // read as verified.
    //
    // `subControlRect(CC_ComboBox, SC_ComboBoxArrow)` answers the chevron's box, which IS measured:
    // 20 x 20 px (`tokens/tokens-controls-measured.toml` `chevron_box_px`), and it agrees with the
    // kit's `[combo_button] width_button.medium = 24` minus its own `inset.medium = 2` on both
    // sides. Two sources, one number.
    //
    // THE TABS ARE DELIBERATELY NOT HERE. Slice 1 declared `tabbar` one of the controls with NO
    // reference in the kit (the nearest thing, `[segmented]`, is a different control), and this
    // slice does not invent a figure for it. `tests/test-style-gallery.sh` still expects `tabbar` to
    // differ by zero pixels, so the omission is a property and not an oversight.
    QRect subControlRect(ComplexControl control, const QStyleOptionComplex *opt, SubControl sc,
                         const QWidget *w) const override;

    // SLICE 6 -- the item view's selection, and it is a DRAWING change rather than a metric one: the
    // geometry comes from the item's own rect and from the measured radii, so the metrics stay the
    // base's and `tests/test-style-gallery.sh` declares it in its own list (`PIXEL_ONLY`). It is the
    // one state with a source: `muestras/Untitled8.png` shows the Finder's icon view drawing TWO
    // layers -- a 144 px cell with radius 14 and an accent pill behind the label -- where the
    // sidebar draws ONE grey row whose text does not change.
    //
    // FOCUS AND DISABLED ARE NOT HERE, and it is the rule of the house rather than an oversight: no
    // capture has a keyboard-only focus ring (the accent pill IS the selected item's indicator) and
    // NO control in either capture is disabled, so there is no source to measure and none is
    // invented; the base keeps drawing them and the token records the absence in words.

    // SLICE 7 -- THE TRACKING, the one thing in the plan that `kdeglobals` cannot carry: the fonts
    // M4 applies have their size in POINTS and a `QFont` has no letter-spacing there.
    //
    // WHY `polish(QWidget *)` IS THE HOOK. Qt DOES have tracking (`QFont::setLetterSpacing`), but a
    // style cannot set it where the TEXT is drawn: the base style draws every label, and a
    // `QProxyStyle` chains to a separate base object whose calls dispatch to itself (the same fact
    // slice 2 met at the button's bevel). What a style CAN do is adjust the font of each widget as
    // it is polished, which is the "font work per widget" the plan names as one of the two routes.
    //
    // AND THE ROLE IS NOT NEEDED, which is why this is a whole-widget rule rather than a whitelist:
    // the token's `[tracking]` table is keyed by the TEXT SIZE (13 -> em1000 -6, 11 -> 6), not by
    // the text style, so the font's size determines the tracking. A style that cannot know it is
    // drawing a menu item does not need to: it needs the size, and it has it. The value comes from
    // `tracking_table.h`, generated from the token so the two cannot disagree.
    void polish(QWidget *w) override;

private:
    void drawSelectedItemViewItem(const QStyleOptionViewItem &item, QPainter *p,
                                  const QWidget *w) const;
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

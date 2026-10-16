// style-kde-macos — the M6 QStyle, FIRST SLICE.
//
// WHAT THIS IS. A Qt 6 widget style plugin that Qt can select by the key "KdeMacOS", and whose
// style is a `QProxyStyle` chained to a base style. The plan behind the slice is in
// `docs/M6-QSTYLE-PLAN.md`; the short version is here, next to the code it explains.
//
// WHY IT OVERRIDES NOTHING YET, ON PURPOSE. M6's done criterion is "it exists, is installed and
// is selectable WITHOUT BREAKING APPLICATIONS". A skeleton that redraws one button and delegates
// the rest breaks applications in the one place nobody looks, and it cannot be told apart from a
// skeleton that works. So this class implements no primitive at all: every pixel an application
// draws still comes from the base style, and selecting it is therefore a no-op by construction.
// `tests/test-style.sh` asserts that absence -- it is the property, not a TODO.
//
// The primitives, each with its own measurement, are the next slices: see the plan.
#pragma once

#include <QProxyStyle>
#include <QString>
#include <QStylePlugin>

// The style itself. NO `drawPrimitive`, `drawControl`, `pixelMetric`, `sizeFromContents`,
// `subElementRect`, `standardIcon` or `styleHint` override belongs here until its slice lands: the
// test counts them and expects zero.
class MacosStyle : public QProxyStyle
{
    Q_OBJECT
public:
    MacosStyle();

    // The base style this one chains to, resolved from what Qt actually offers. Public and static
    // so the probe can report which base was chosen instead of the test guessing.
    static QString baseStyleKey();
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

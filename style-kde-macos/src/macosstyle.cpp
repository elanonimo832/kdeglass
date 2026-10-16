#include "macosstyle.h"

#include <QStyleFactory>
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

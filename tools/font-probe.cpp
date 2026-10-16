// font-probe — what Qt 6 ACTUALLY sees in the font strings kdeglobals carries.
//
// WHY THIS EXISTS (M4 amendment). M4 first wrote the macOS sizes into the PIXEL field of the font
// string (`Inter,-1,13,...`). `QFont` holds a size in POINTS **or** in PIXELS, never both, so with a
// pixel size `pointSize()` is -1 — and applications that re-apply it print, in the user's session:
//
//     QFont::setPointSize: Point size <= 0 (-1), must be greater than 0
//
// Measured: that message appears with `QT_STYLE_OVERRIDE=Breeze` too, so it is NOT the QStyle
// (style-kde-macos/); it is the font. This probe is the instrument that settles the question:
//
//   * `pointSizeF() > 0`  -> nothing can be handed a -1.
//   * the metrics (height and advance) MUST equal the reference's, or turning px into pt moved the
//     render and the point of the change is lost.
//
// THE REFERENCE IS THE SAME FONT IN THE OLD PIXEL FORM, given as a string, because the size alone is
// not enough: `[WM] activeFont` is BOLD and `toolBarFont` is 11 px, so a single yardstick would
// compare different fonts and "fail" honestly-wrong. Passing the string keeps the family, the size
// AND the weight identical, and isolates the ONE thing being tested: the unit.
//
// At this machine's font DPI (96, and there is no `forceFontDPI` key: measured) a point is 96/72 px,
// so `setPointSizeF(9.75)` and `setPixelSize(13)` are the SAME font — this probe proves it instead
// of asserting it.
//
// Built by tests/test-typography.sh with the same Qt 6 the desktop runs.

#include <QCoreApplication>
#include <QGuiApplication>
#include <QFont>
#include <QFontMetrics>
#include <QString>
#include <QStringList>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);

    QString referencia;
    QStringList cadenas;

    const QStringList args = QCoreApplication::arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QLatin1String("--reference") && i + 1 < args.size()) {
            referencia = args[++i];
        } else {
            cadenas << args[i];
        }
    }
    if (referencia.isEmpty()) {
        std::fprintf(stderr,
                     "usage: font-probe --reference <pixel-form-font-string> <font-string>...\n");
        return 2;
    }

    const QString muestra = QStringLiteral("The quick brown fox jumps over the lazy dog");
    QFont ref;
    ref.fromString(referencia);
    QFontMetrics rm(ref);
    std::printf("REFERENCE %s height=%d advance=%d\n", qPrintable(referencia), rm.height(),
                rm.horizontalAdvance(muestra));

    for (const QString &cadena : cadenas) {
        QFont f;
        f.fromString(cadena);
        QFontMetrics fm(f);
        std::printf("FONT %s pointSize=%d pointSizeF=%.2f pixelSize=%d height=%d advance=%d\n",
                    qPrintable(cadena), f.pointSize(), f.pointSizeF(), f.pixelSize(), fm.height(),
                    fm.horizontalAdvance(muestra));
    }
    return 0;
}

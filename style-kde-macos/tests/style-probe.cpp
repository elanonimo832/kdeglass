// The M6 first-slice probe: it answers the slice's three questions in ONE process that exits
// non-zero when any of them is false.
//
//   1. is the plugin there?        QStyleFactory::keys() must list KdeMacOS
//   2. is it selectable?           QStyleFactory::create("KdeMacOS") must return a style
//   3. does it draw, WITHOUT changing what the application looked like?
//                                  the SAME widget is rendered twice, once under the base style and
//                                  once under ours, and the two images are compared PIXEL BY PIXEL
//
// Question 3 is deliberately stronger than "it painted something", and the first version of this
// probe made that mistake: it counted non-white pixels and reported `19800 of 19800`, because the
// WIDGET'S OWN BACKGROUND covers the whole canvas. That number would have been green for a style
// that painted nothing at all. Comparing against the base style answers the question the done
// criterion actually asks -- "selectable WITHOUT BREAKING APPLICATIONS" -- because a skeleton that
// delegates every primitive must produce the IDENTICAL image, and the day a slice implements one,
// the difference is the measurement that slice owes.
//
// It runs under the OFFSCREEN platform: no screen, no session, no user. `tests/test-style.sh`
// drives it.
#include <QApplication>
#include <QCheckBox>
#include <QColor>
#include <QImage>
#include <QPixmap>
#include <QStyle>
#include <QStyleFactory>
#include <QVariant>
#include <QWidget>

#include <cstdio>

namespace {

// One render of a fixed widget under a given style. The style is passed in already created: who
// owns it is QApplication::setStyle's business, and it deletes the previous one.
QImage renderUnder(QStyle *style)
{
    QApplication::setStyle(style);

    QWidget window;
    window.resize(220, 90);
    // THE WIDGET IN THIS WINDOW IS ONE *NO* SLICE HAS TOUCHED, and that is what makes the probe's
    // claim still testable: it asserts that delegating every primitive is a no-op, and a control a
    // slice has already redrawn cannot test that. Slice 2 changed the push button, so the button
    // MOVED to `primitive-gallery.cpp` -- where it is measured per widget and against its token --
    // and this probe is left on the checkbox, where "identical to the base" is still exactly true.
    // The button did not simply disappear: where it went is this comment.
    QCheckBox check(QStringLiteral("Check"), &window);
    check.setGeometry(10, 50, 130, 25);

    // The canvas is white and the widget does NOT fill its background, so the pixels that differ
    // from white are the CONTROLS: a render that silently skipped them would leave the canvas white
    // and be caught by the comparison below.
    QPixmap canvas(220, 90);
    canvas.fill(Qt::white);
    window.render(&canvas);
    return canvas.toImage();
}

long paintedPixels(const QImage &image)
{
    long painted = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (image.pixelColor(x, y) != QColor(Qt::white)) {
                ++painted;
            }
        }
    }
    return painted;
}

} // namespace

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    // 1. The keys Qt reports: what a selection is matched against. A style whose metadata Keys are
    //    wrong is a style that exists and cannot be selected.
    QByteArray keys;
    for (const QString &key : QStyleFactory::keys()) {
        keys += ' ';
        keys += key.toUtf8();
    }
    std::printf("KEYS:%s\n", keys.constData());

    // 2. Selectable. A null here means Qt found the plugin and not the key, or did not find the
    //    plugin at all -- the two are told apart by the KEYS line.
    QStyle *ours = QStyleFactory::create(QStringLiteral("KdeMacOS"));
    if (!ours) {
        std::printf("CREATE: NULL\n");
        return 3;
    }
    std::printf("CREATE: ok\n");

    // 3a. WHICH base was chained to, reported so the test pins "a real base was resolved" rather
    //     than this machine's particular answer.
    const QString baseKey = ours->property("kdeMacosBaseStyle").toString();
    std::printf("BASE: %s\n", baseKey.toUtf8().constData());

    // 3b. The comparison. The base render goes FIRST, because setStyle takes ownership and deletes
    //     the style it replaces, so the images have to be taken before the styles are swapped away.
    const QImage baseImage = renderUnder(QStyleFactory::create(baseKey));
    const QImage ourImage = renderUnder(ours);

    const long basePainted = paintedPixels(baseImage);
    const long ourPainted = paintedPixels(ourImage);
    std::printf("PAINTED: base=%ld ours=%ld\n", basePainted, ourPainted);

    if (baseImage.size() != ourImage.size()) {
        std::printf("DIFF: sizes differ\n");
        return 4;
    }
    long different = 0;
    for (int y = 0; y < baseImage.height(); ++y) {
        for (int x = 0; x < baseImage.width(); ++x) {
            if (baseImage.pixelColor(x, y) != ourImage.pixelColor(x, y)) {
                ++different;
            }
        }
    }
    std::printf("DIFF: %ld of %d\n", different, baseImage.width() * baseImage.height());

    // A skeleton that delegates every primitive must be a no-op, and a no-op is exactly this zero.
    // If it ever stops being zero without a slice behind it, this is the assertion that catches it.
    if (different != 0) {
        return 5;
    }
    // And a style that painted NOTHING would also be identical to a base that painted nothing, so
    // the base has to have painted the controls.
    if (basePainted <= 0) {
        std::printf("BASE PAINTED NOTHING\n");
        return 6;
    }
    return 0;
}

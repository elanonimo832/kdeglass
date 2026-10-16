// M6, slice 1 — THE PRIMITIVE INSTRUMENT.
//
// WHAT IT IS FOR. `docs/M6-QSTYLE-PLAN.md` says a primitive is only changed with its measurement in
// front, and this is that measurement. Slice 0 shipped a skeleton whose claim was `DIFF: 0` for ONE
// widget; this generalises it to a GALLERY and adds the half a pixel difference cannot give: what Qt
// ASKS each control for. Slice 2 has to move a number, and it cannot move a number that was never
// taken.
//
// THE THREE THINGS IT REPORTS PER PRIMITIVE, and why each one exists:
//
//   WIDGET <name> PAINTED base=<n> ours=<n> DIFF <d> of <t>
//     The per-widget pixel difference between the base style and ours. Per WIDGET and not one
//     number for a collage: a collage hides the one control that changed. `PAINTED` is the
//     anti-cheat: two BLANK canvases also differ by zero, so a difference is only evidence if both
//     renders painted something. The first version of the slice-0 probe counted non-white pixels
//     and reported `19800 of 19800` -- the widget's own background -- which would have been green
//     for a style that painted NOTHING. Hence the magenta canvas: no widget paints (255,0,255) by
//     accident, so "painted" is "differs from the canvas" and an empty render counts zero.
//
//   METRIC <name> sizeHint=WxH | pixelMetric(PM_X)=v | sizeFromContents(CT_X)=WxH |
//                 subControlRect(CC_X,SC_Y)=x,y,w,h
//     What the BASE style answers, so the next slice can say "we changed it" with the before and
//     the after. A style is largely a set of sizes, and these are the sizes.
//
//   METRICDIFF <name> <n>
//     How many of those metrics differ between ours and the base. Zero today, for the same reason
//     the pixels are zero: the skeleton delegates. A primitive whose metrics move while its pixels
//     do not (or the other way round) is a change nobody measured, and this line is where it shows.
//
// IT DRAWS OUR OWN EVIDENCE. `--render <png>` composes the gallery (base panel and our panel, each
// widget labelled) so the slice can be LOOKED at; the image is drawn by this program, never a
// screenshot of anybody's desktop. `--baseline <file>` writes the METRIC lines, which is the table
// the following slices diff against.
//
// It runs under the OFFSCREEN platform: no screen, no session, no user. `tests/test-style-gallery.sh`
// drives it, and its widget list is the CONTRACT with that test.
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QHeaderView>
#include <QImage>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QPainter>
#include <QPixmap>
#include <QProgressBar>
#include <QPushButton>
#include <QRadioButton>
#include <QScrollBar>
#include <QSlider>
#include <QStyle>
#include <QStyleFactory>
#include <QStyleOption>
#include <QStyleOptionButton>
#include <QStyleOptionComboBox>
#include <QStyleOptionHeader>
#include <QStyleOptionMenuItem>
#include <QStyleOptionProgressBar>
#include <QStyleOptionSlider>
#include <QStyleOptionTab>
#include <QStyleOptionViewItem>
#include <QTabBar>
#include <QTableWidget>
#include <QWidget>

#include <cstdio>
#include <functional>
#include <memory>
#include <vector>

namespace {

// ------------------------------------------------------------------------------------------------
// The canvas. Magenta is the point: it is not a colour any style paints, so "differs from the
// canvas" means "the widget painted here", and a widget that painted nothing leaves the canvas
// untouched and is caught instead of being compared as a blank against a blank.
const QColor kCanvas(255, 0, 255);
constexpr int kMargin = 4;

QWidget *makePushButton(QWidget *p) { auto *w = new QPushButton(QStringLiteral("OK"), p); return w; }
QWidget *makeDefaultButton(QWidget *p)
{
    auto *w = new QPushButton(QStringLiteral("OK"), p);
    w->setDefault(true);
    w->setAutoDefault(true);
    return w;
}
QWidget *makeDisabledButton(QWidget *p)
{
    auto *w = new QPushButton(QStringLiteral("OK"), p);
    w->setEnabled(false);
    return w;
}
QWidget *makeCheckBox(QWidget *p) { return new QCheckBox(QStringLiteral("Check"), p); }
QWidget *makeCheckedCheckBox(QWidget *p)
{
    auto *w = new QCheckBox(QStringLiteral("Check"), p);
    w->setChecked(true);
    return w;
}
QWidget *makeDisabledCheckBox(QWidget *p)
{
    auto *w = new QCheckBox(QStringLiteral("Check"), p);
    w->setEnabled(false);
    return w;
}
QWidget *makeRadio(QWidget *p) { return new QRadioButton(QStringLiteral("Radio"), p); }
QWidget *makeCheckedRadio(QWidget *p)
{
    auto *w = new QRadioButton(QStringLiteral("Radio"), p);
    w->setChecked(true);
    return w;
}
QWidget *makeSlider(QWidget *p)
{
    auto *w = new QSlider(Qt::Horizontal, p);
    w->setRange(0, 100);
    w->setValue(40);
    return w;
}
QWidget *makeScrollBar(QWidget *p)
{
    auto *w = new QScrollBar(Qt::Vertical, p);
    w->setRange(0, 100);
    w->setValue(40);
    return w;
}
QWidget *makeComboBox(QWidget *p)
{
    auto *w = new QComboBox(p);
    w->addItem(QStringLiteral("One"));
    w->addItem(QStringLiteral("Two"));
    return w;
}
QWidget *makeTabBar(QWidget *p)
{
    auto *w = new QTabBar(p);
    w->addTab(QStringLiteral("One"));
    w->addTab(QStringLiteral("Two"));
    w->setCurrentIndex(0);
    return w;
}
QWidget *makeMenuBar(QWidget *p)
{
    auto *w = new QMenuBar(p);
    w->addMenu(QStringLiteral("File"));
    w->addMenu(QStringLiteral("Edit"));
    return w;
}
// A MENU THAT RENDERS OFFSCREEN, because a real QMenu does not: MEASURED `PAINTED base=0` even
// after `show()`, since a popup's painting depends on the platform's popup handling and the offscreen
// platform has none. The alternative was a row named "menu" that measured nothing while looking like
// a measurement -- exactly what this file exists to prevent. So the gallery draws the menu's OWN
// primitives through the style: PE_PanelMenu for the panel and CE_MenuItem per row. It is the same
// code path a slice would have to change, and it is deterministic.
class MenuLikeWidget : public QWidget
{
public:
    explicit MenuLikeWidget(QWidget *p) : QWidget(p) { resize(180, 92); }
    // A size hint, because a plain QWidget answers -1x-1 and the render size is derived from it: the
    // first version of this row was rendered at the 140x30 minimum and reported `sizeHint=-1x-1`,
    // which is a measurement of the wrong question.
    QSize sizeHint() const override { return QSize(180, 92); }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        QStyleOptionMenuItem panel;
        panel.initFrom(this);
        panel.rect = rect();
        style()->drawPrimitive(QStyle::PE_PanelMenu, &panel, &painter, this);
        const QStringList rows = {QStringLiteral("Open"), QStringLiteral("Save"),
                                  QStringLiteral("Disabled")};
        int y = 3;
        for (int i = 0; i < rows.size(); ++i) {
            QStyleOptionMenuItem item;
            item.initFrom(this);
            item.rect = QRect(2, y, width() - 4, 22);
            item.text = rows.at(i);
            item.menuItemType = QStyleOptionMenuItem::Normal;
            if (i == 2) {
                // There is NO `MenuItemType::Disabled` (checked in the Qt header): a disabled item
                // is a Normal one with State_Enabled cleared.
                item.state.setFlag(QStyle::State_Enabled, false);
            }
            item.checkType = QStyleOptionMenuItem::NotCheckable;
            style()->drawControl(QStyle::CE_MenuItem, &item, &painter, this);
            y += 22;
        }
    }
};
QWidget *makeMenu(QWidget *p) { return new MenuLikeWidget(p); }
QWidget *makeLineEdit(QWidget *p) { return new QLineEdit(QStringLiteral("Text"), p); }

// The focus ring is a STATE, and offscreen nothing ever gives a widget the keyboard focus, so
// waiting for one would have produced a row named "focused" that is a plain line edit. Forcing the
// option's state is what makes the row exercise the focus path at all -- and it is honest: what the
// row measures is the style's answer to State_HasFocus, which is exactly what a slice will change.
class FocusedLineEdit : public QLineEdit
{
public:
    explicit FocusedLineEdit(QWidget *p) : QLineEdit(QStringLiteral("Text"), p) { selectAll(); }

protected:
    void initStyleOption(QStyleOptionFrame *option) const override
    {
        QLineEdit::initStyleOption(option);
        option->state |= QStyle::State_HasFocus;
        option->state |= QStyle::State_KeyboardFocusChange;
        option->state |= QStyle::State_Active;
    }
};
QWidget *makeFocusedLineEdit(QWidget *p) { return new FocusedLineEdit(p); }

QWidget *makeProgressBar(QWidget *p)
{
    auto *w = new QProgressBar(p);
    w->setRange(0, 100);
    w->setValue(40);
    return w;
}
QWidget *makeListWithSelection(QWidget *p)
{
    auto *w = new QListWidget(p);
    w->addItem(QStringLiteral("One"));
    w->addItem(QStringLiteral("Two"));
    w->addItem(QStringLiteral("Three"));
    w->setCurrentRow(1); // the SELECTION state: a slice that redraws it has to see it chosen
    return w;
}
QWidget *makeTableHeader(QWidget *p)
{
    auto *w = new QTableWidget(2, 2, p);
    w->setHorizontalHeaderLabels({QStringLiteral("A"), QStringLiteral("B")});
    return w;
}

// ------------------------------------------------------------------------------------------------
// Names for the enums. QStyle has no name lookup, so the table is written out -- and only for what
// this gallery asks, which is why it is short.
const char *pmName(QStyle::PixelMetric pm)
{
    switch (pm) {
    case QStyle::PM_ButtonMargin: return "PM_ButtonMargin";
    case QStyle::PM_ButtonDefaultIndicator: return "PM_ButtonDefaultIndicator";
    case QStyle::PM_ButtonShiftHorizontal: return "PM_ButtonShiftHorizontal";
    case QStyle::PM_ButtonShiftVertical: return "PM_ButtonShiftVertical";
    case QStyle::PM_DefaultFrameWidth: return "PM_DefaultFrameWidth";
    case QStyle::PM_IndicatorWidth: return "PM_IndicatorWidth";
    case QStyle::PM_IndicatorHeight: return "PM_IndicatorHeight";
    case QStyle::PM_ExclusiveIndicatorWidth: return "PM_ExclusiveIndicatorWidth";
    case QStyle::PM_ExclusiveIndicatorHeight: return "PM_ExclusiveIndicatorHeight";
    case QStyle::PM_CheckBoxLabelSpacing: return "PM_CheckBoxLabelSpacing";
    case QStyle::PM_RadioButtonLabelSpacing: return "PM_RadioButtonLabelSpacing";
    case QStyle::PM_SliderThickness: return "PM_SliderThickness";
    case QStyle::PM_SliderLength: return "PM_SliderLength";
    case QStyle::PM_SliderControlThickness: return "PM_SliderControlThickness";
    case QStyle::PM_ScrollBarExtent: return "PM_ScrollBarExtent";
    case QStyle::PM_ScrollBarSliderMin: return "PM_ScrollBarSliderMin";
    case QStyle::PM_ComboBoxFrameWidth: return "PM_ComboBoxFrameWidth";
    case QStyle::PM_TabBarTabHSpace: return "PM_TabBarTabHSpace";
    case QStyle::PM_TabBarTabVSpace: return "PM_TabBarTabVSpace";
    case QStyle::PM_TabBarTabOverlap: return "PM_TabBarTabOverlap";
    case QStyle::PM_TabBarBaseOverlap: return "PM_TabBarBaseOverlap";
    case QStyle::PM_MenuBarHMargin: return "PM_MenuBarHMargin";
    case QStyle::PM_MenuBarVMargin: return "PM_MenuBarVMargin";
    case QStyle::PM_MenuBarItemSpacing: return "PM_MenuBarItemSpacing";
    case QStyle::PM_MenuBarPanelWidth: return "PM_MenuBarPanelWidth";
    case QStyle::PM_MenuHMargin: return "PM_MenuHMargin";
    case QStyle::PM_MenuVMargin: return "PM_MenuVMargin";
    case QStyle::PM_MenuPanelWidth: return "PM_MenuPanelWidth";
    case QStyle::PM_SmallIconSize: return "PM_SmallIconSize";
    case QStyle::PM_ProgressBarChunkWidth: return "PM_ProgressBarChunkWidth";
    case QStyle::PM_HeaderMargin: return "PM_HeaderMargin";
    case QStyle::PM_HeaderMarkSize: return "PM_HeaderMarkSize";
    case QStyle::PM_HeaderGripMargin: return "PM_HeaderGripMargin";
    case QStyle::PM_HeaderDefaultSectionSizeHorizontal: return "PM_HeaderDefaultSectionSizeHorizontal";
    case QStyle::PM_FocusFrameHMargin: return "PM_FocusFrameHMargin";
    case QStyle::PM_FocusFrameVMargin: return "PM_FocusFrameVMargin";
    case QStyle::PM_LayoutLeftMargin: return "PM_LayoutLeftMargin";
    default: return nullptr;
    }
}

// NOT every control is a COMPLEX control, and which ones are is a MEASURED fact of this Qt (read
// out of <QtWidgets/qstyle.h>), not a guess: Qt 6 has `CC_Slider`, `CC_ScrollBar` and `CC_ComboBox`,
// and it has NO `CC_PushButton`, `CC_CheckBox`, `CC_RadioButton` or `CC_TabBar`. Their geometry is
// asked for with `subElementRect(SE_...)` instead. That is why this gallery reports BOTH families:
// a table with only one of them would have silently left the button -- the most visible control --
// with no rectangle at all.
// A SUB-CONTROL ONLY MEANS SOMETHING WITH ITS COMPLEX CONTROL, and that is a fact of the enum, not a
// style preference: Qt REUSES the values 0x1/0x2/0x4/0x8 in every group, so `SC_SliderGroove`,
// `SC_ScrollBarAddLine` and `SC_ComboBoxFrame` are all 0x1. A `switch (sc)` alone therefore does not
// compile -- the cases collide -- and a table keyed on the sub-control alone would print the WRONG
// NAME for two of the three. Hence the pair.
const char *scName(QStyle::ComplexControl cc, QStyle::SubControl sc)
{
    if (sc == QStyle::SC_None) {
        return "SC_None";
    }
    switch (cc) {
    case QStyle::CC_Slider:
        switch (sc) {
        case QStyle::SC_SliderGroove: return "SC_SliderGroove";
        case QStyle::SC_SliderHandle: return "SC_SliderHandle";
        case QStyle::SC_SliderTickmarks: return "SC_SliderTickmarks";
        default: return nullptr;
        }
    case QStyle::CC_ScrollBar:
        switch (sc) {
        case QStyle::SC_ScrollBarSlider: return "SC_ScrollBarSlider";
        case QStyle::SC_ScrollBarGroove: return "SC_ScrollBarGroove";
        case QStyle::SC_ScrollBarAddLine: return "SC_ScrollBarAddLine";
        case QStyle::SC_ScrollBarSubLine: return "SC_ScrollBarSubLine";
        case QStyle::SC_ScrollBarAddPage: return "SC_ScrollBarAddPage";
        case QStyle::SC_ScrollBarSubPage: return "SC_ScrollBarSubPage";
        default: return nullptr;
        }
    case QStyle::CC_ComboBox:
        switch (sc) {
        case QStyle::SC_ComboBoxFrame: return "SC_ComboBoxFrame";
        case QStyle::SC_ComboBoxEditField: return "SC_ComboBoxEditField";
        case QStyle::SC_ComboBoxArrow: return "SC_ComboBoxArrow";
        case QStyle::SC_ComboBoxListBoxPopup: return "SC_ComboBoxListBoxPopup";
        default: return nullptr;
        }
    default: return nullptr;
    }
}

const char *seName(QStyle::SubElement se)
{
    switch (se) {
    case QStyle::SE_PushButtonBevel: return "SE_PushButtonBevel";
    case QStyle::SE_PushButtonContents: return "SE_PushButtonContents";
    case QStyle::SE_PushButtonFocusRect: return "SE_PushButtonFocusRect";
    case QStyle::SE_CheckBoxIndicator: return "SE_CheckBoxIndicator";
    case QStyle::SE_CheckBoxContents: return "SE_CheckBoxContents";
    case QStyle::SE_CheckBoxFocusRect: return "SE_CheckBoxFocusRect";
    case QStyle::SE_CheckBoxClickRect: return "SE_CheckBoxClickRect";
    case QStyle::SE_RadioButtonIndicator: return "SE_RadioButtonIndicator";
    case QStyle::SE_RadioButtonContents: return "SE_RadioButtonContents";
    case QStyle::SE_RadioButtonFocusRect: return "SE_RadioButtonFocusRect";
    case QStyle::SE_RadioButtonClickRect: return "SE_RadioButtonClickRect";
    case QStyle::SE_SliderFocusRect: return "SE_SliderFocusRect";
    case QStyle::SE_ComboBoxFocusRect: return "SE_ComboBoxFocusRect";
    case QStyle::SE_LineEditContents: return "SE_LineEditContents";
    case QStyle::SE_ProgressBarGroove: return "SE_ProgressBarGroove";
    case QStyle::SE_ProgressBarContents: return "SE_ProgressBarContents";
    case QStyle::SE_ProgressBarLabel: return "SE_ProgressBarLabel";
    case QStyle::SE_TabBarTabText: return "SE_TabBarTabText";
    case QStyle::SE_HeaderLabel: return "SE_HeaderLabel";
    case QStyle::SE_HeaderArrow: return "SE_HeaderArrow";
    case QStyle::SE_ItemViewItemText: return "SE_ItemViewItemText";
    case QStyle::SE_ItemViewItemFocusRect: return "SE_ItemViewItemFocusRect";
    default: return nullptr;
    }
}

const char *ccName(QStyle::ComplexControl cc)
{
    switch (cc) {
    case QStyle::CC_Slider: return "CC_Slider";
    case QStyle::CC_ScrollBar: return "CC_ScrollBar";
    case QStyle::CC_ComboBox: return "CC_ComboBox";
    default: return nullptr;
    }
}

const char *ctName(QStyle::ContentsType ct)
{
    switch (ct) {
    case QStyle::CT_PushButton: return "CT_PushButton";
    case QStyle::CT_CheckBox: return "CT_CheckBox";
    case QStyle::CT_RadioButton: return "CT_RadioButton";
    case QStyle::CT_ComboBox: return "CT_ComboBox";
    case QStyle::CT_MenuBarItem: return "CT_MenuBarItem";
    case QStyle::CT_MenuItem: return "CT_MenuItem";
    case QStyle::CT_LineEdit: return "CT_LineEdit";
    case QStyle::CT_ProgressBar: return "CT_ProgressBar";
    case QStyle::CT_TabBarTab: return "CT_TabBarTab";
    default: return nullptr;
    }
}

// ------------------------------------------------------------------------------------------------
// The gallery's contract with `tests/test-style-gallery.sh`: the same names, the same list.
struct Primitive {
    const char *name;
    QWidget *(*make)(QWidget *);
    std::vector<QStyle::PixelMetric> pixels;
    std::vector<std::pair<QStyle::ComplexControl, QStyle::SubControl>> subs;
    std::vector<QStyle::SubElement> elements;
    std::vector<QStyle::ContentsType> contents;
};

const std::vector<Primitive> &primitives()
{
    static const std::vector<Primitive> list = {
        {"pushbutton", makePushButton,
         {QStyle::PM_ButtonMargin, QStyle::PM_DefaultFrameWidth, QStyle::PM_FocusFrameHMargin},
         {},
         {QStyle::SE_PushButtonBevel, QStyle::SE_PushButtonContents, QStyle::SE_PushButtonFocusRect},
         {QStyle::CT_PushButton}},
        {"pushbutton-default", makeDefaultButton,
         {QStyle::PM_ButtonMargin, QStyle::PM_ButtonDefaultIndicator},
         {},
         {QStyle::SE_PushButtonBevel, QStyle::SE_PushButtonContents},
         {QStyle::CT_PushButton}},
        {"pushbutton-disabled", makeDisabledButton,
         {QStyle::PM_ButtonMargin},
         {},
         {QStyle::SE_PushButtonBevel, QStyle::SE_PushButtonContents},
         {QStyle::CT_PushButton}},
        {"checkbox", makeCheckBox,
         {QStyle::PM_IndicatorWidth, QStyle::PM_IndicatorHeight, QStyle::PM_CheckBoxLabelSpacing},
         {},
         {QStyle::SE_CheckBoxIndicator, QStyle::SE_CheckBoxContents, QStyle::SE_CheckBoxFocusRect,
          QStyle::SE_CheckBoxClickRect},
         {QStyle::CT_CheckBox}},
        {"checkbox-checked", makeCheckedCheckBox,
         {QStyle::PM_IndicatorWidth, QStyle::PM_IndicatorHeight},
         {},
         {QStyle::SE_CheckBoxIndicator, QStyle::SE_CheckBoxContents},
         {QStyle::CT_CheckBox}},
        {"checkbox-disabled", makeDisabledCheckBox,
         {QStyle::PM_IndicatorWidth, QStyle::PM_IndicatorHeight},
         {},
         {QStyle::SE_CheckBoxIndicator, QStyle::SE_CheckBoxContents},
         {QStyle::CT_CheckBox}},
        {"radio", makeRadio,
         {QStyle::PM_ExclusiveIndicatorWidth, QStyle::PM_ExclusiveIndicatorHeight,
          QStyle::PM_RadioButtonLabelSpacing},
         {},
         {QStyle::SE_RadioButtonIndicator, QStyle::SE_RadioButtonContents,
          QStyle::SE_RadioButtonFocusRect},
         {QStyle::CT_RadioButton}},
        {"radio-checked", makeCheckedRadio,
         {QStyle::PM_ExclusiveIndicatorWidth, QStyle::PM_ExclusiveIndicatorHeight},
         {},
         {QStyle::SE_RadioButtonIndicator, QStyle::SE_RadioButtonContents},
         {QStyle::CT_RadioButton}},
        {"slider", makeSlider,
         {QStyle::PM_SliderThickness, QStyle::PM_SliderLength, QStyle::PM_SliderControlThickness},
         {{QStyle::CC_Slider, QStyle::SC_SliderGroove}, {QStyle::CC_Slider, QStyle::SC_SliderHandle}},
         {QStyle::SE_SliderFocusRect},
         {}},
        {"scrollbar", makeScrollBar,
         {QStyle::PM_ScrollBarExtent, QStyle::PM_ScrollBarSliderMin},
         {{QStyle::CC_ScrollBar, QStyle::SC_ScrollBarSlider},
          {QStyle::CC_ScrollBar, QStyle::SC_ScrollBarGroove},
          {QStyle::CC_ScrollBar, QStyle::SC_ScrollBarAddLine}},
         {},
         {}},
        {"combobox", makeComboBox,
         {QStyle::PM_ComboBoxFrameWidth},
         {{QStyle::CC_ComboBox, QStyle::SC_ComboBoxFrame},
          {QStyle::CC_ComboBox, QStyle::SC_ComboBoxEditField},
          {QStyle::CC_ComboBox, QStyle::SC_ComboBoxArrow}},
         {QStyle::SE_ComboBoxFocusRect},
         {QStyle::CT_ComboBox}},
        {"tabbar", makeTabBar,
         {QStyle::PM_TabBarTabHSpace, QStyle::PM_TabBarTabVSpace, QStyle::PM_TabBarTabOverlap},
         {},
         {QStyle::SE_TabBarTabText},
         {QStyle::CT_TabBarTab}},
        {"menubar", makeMenuBar,
         {QStyle::PM_MenuBarHMargin, QStyle::PM_MenuBarVMargin, QStyle::PM_MenuBarItemSpacing},
         {},
         {},
         {QStyle::CT_MenuBarItem}},
        {"menu", makeMenu,
         {QStyle::PM_MenuHMargin, QStyle::PM_MenuVMargin, QStyle::PM_MenuPanelWidth},
         {},
         {},
         {QStyle::CT_MenuItem}},
        {"lineedit", makeLineEdit,
         {QStyle::PM_DefaultFrameWidth, QStyle::PM_FocusFrameHMargin},
         {},
         {QStyle::SE_LineEditContents},
         {QStyle::CT_LineEdit}},
        {"lineedit-focused", makeFocusedLineEdit,
         {QStyle::PM_DefaultFrameWidth, QStyle::PM_FocusFrameHMargin},
         {},
         {QStyle::SE_LineEditContents},
         {QStyle::CT_LineEdit}},
        {"progressbar", makeProgressBar,
         {QStyle::PM_ProgressBarChunkWidth, QStyle::PM_DefaultFrameWidth},
         {},
         {QStyle::SE_ProgressBarGroove, QStyle::SE_ProgressBarContents, QStyle::SE_ProgressBarLabel},
         {QStyle::CT_ProgressBar}},
        {"listview-selected", makeListWithSelection,
         {QStyle::PM_SmallIconSize, QStyle::PM_FocusFrameHMargin},
         {},
         {QStyle::SE_ItemViewItemText, QStyle::SE_ItemViewItemFocusRect},
         {}},
        {"tableheader", makeTableHeader,
         {QStyle::PM_HeaderMargin, QStyle::PM_HeaderMarkSize,
          QStyle::PM_HeaderDefaultSectionSizeHorizontal},
         {},
         {QStyle::SE_HeaderLabel, QStyle::SE_HeaderArrow},
         {}},
    };
    return list;
}

// ------------------------------------------------------------------------------------------------
// One render of one widget under the application's CURRENT style. The geometry is fixed here and not
// laid out, because a layout that changes with the style would move the pixels for a reason that is
// not the primitive.
QImage renderOne(QWidget *(*make)(QWidget *), const QSize &size)
{
    QWidget window;
    QWidget *w = make(&window);
    w->resize(size);
    w->move(kMargin, kMargin);
    window.resize(size.width() + 2 * kMargin, size.height() + 2 * kMargin);
    QPixmap canvas(window.size());
    canvas.fill(kCanvas);
    window.render(&canvas);
    return canvas.toImage();
}

long differingPixels(const QImage &a, const QImage &b)
{
    if (a.size() != b.size()) {
        return -1;
    }
    long n = 0;
    for (int y = 0; y < a.height(); ++y) {
        for (int x = 0; x < a.width(); ++x) {
            if (a.pixelColor(x, y) != b.pixelColor(x, y)) {
                ++n;
            }
        }
    }
    return n;
}

// THE ANTI-CHEAT IS A COMPARISON, NOT A COLOUR COUNT, and the first version of this file proved why
// the hard way: it filled the canvas with magenta and counted "pixels that are not magenta", which
// reported `PAINTED base=6216 of 6216` for every widget -- the WINDOW'S OWN BACKGROUND covers the
// whole canvas, so the number was the canvas area and would have been green for a style that painted
// no control at all. It is the same trap the slice-0 probe recorded, repeated by the file that
// quotes it.
//
// What is counted instead is what the CONTROL contributes beyond an EMPTY widget of the same size:
// the same window is rendered twice, once with the control and once with a blank child, and the
// pixels that differ are the control's own drawing. A widget that painted nothing differs from the
// blank in zero pixels, which is the answer this needs to be able to give.
QImage renderBlank(const QSize &size)
{
    QWidget window;
    QWidget *blank = new QWidget(&window);
    blank->resize(size);
    blank->move(kMargin, kMargin);
    window.resize(size.width() + 2 * kMargin, size.height() + 2 * kMargin);
    QPixmap canvas(window.size());
    canvas.fill(kCanvas);
    window.render(&canvas);
    return canvas.toImage();
}

// The option a subControlRect needs. `initFrom` gives it the widget's geometry and state, which is
// what makes the rectangles comparable; the two feature flags are the ones that change a PUSH
// BUTTON's sub-controls, so they are set where they mean something.
//
// The return type is `QStyleOptionComplex`, not `QStyleOption`: `subControlRect` takes a COMPLEX
// option, and the generic one is not a complex control's option at all -- so it returns null and the
// caller SKIPS it, instead of pretending to measure a rectangle nothing asked for.
std::unique_ptr<QStyleOptionComplex> optionFor(QStyle::ComplexControl cc, QWidget *w)
{
    switch (cc) {
    case QStyle::CC_Slider:
    case QStyle::CC_ScrollBar: {
        auto o = std::make_unique<QStyleOptionSlider>();
        o->initFrom(w);
        if (auto *s = qobject_cast<QSlider *>(w)) {
            o->minimum = s->minimum();
            o->maximum = s->maximum();
            o->sliderPosition = s->sliderPosition();
            o->sliderValue = s->value();
            o->orientation = s->orientation();
        } else if (auto *sb = qobject_cast<QScrollBar *>(w)) {
            o->minimum = sb->minimum();
            o->maximum = sb->maximum();
            o->sliderPosition = sb->sliderPosition();
            o->sliderValue = sb->value();
            o->orientation = sb->orientation();
            o->pageStep = sb->pageStep();
            o->singleStep = sb->singleStep();
        }
        return o;
    }
    case QStyle::CC_ComboBox: {
        auto o = std::make_unique<QStyleOptionComboBox>();
        o->initFrom(w);
        if (auto *c = qobject_cast<QComboBox *>(w)) {
            o->currentText = c->currentText();
        }
        return o;
    }
    default:
        return nullptr;
    }
}

// The option a subElementRect needs. Buttons, checkboxes and radio buttons are NOT complex controls
// in Qt 6, so their geometry lives only on this side -- and the option has to carry their STATE, or
// the rectangle reported for "checked", "disabled" and "default" is the rectangle of a plain button.
std::unique_ptr<QStyleOption> elementOptionFor(QWidget *w)
{
    if (auto *b = qobject_cast<QPushButton *>(w)) {
        auto o = std::make_unique<QStyleOptionButton>();
        o->initFrom(w);
        o->features = b->isDefault() ? QStyleOptionButton::DefaultButton : QStyleOptionButton::None;
        o->text = b->text();
        o->state.setFlag(QStyle::State_Sunken, b->isDown());
        return o;
    }
    if (auto *c = qobject_cast<QCheckBox *>(w)) {
        auto o = std::make_unique<QStyleOptionButton>();
        o->initFrom(w);
        o->state.setFlag(QStyle::State_On, c->isChecked());
        o->text = c->text();
        return o;
    }
    if (auto *r = qobject_cast<QRadioButton *>(w)) {
        auto o = std::make_unique<QStyleOptionButton>();
        o->initFrom(w);
        o->state.setFlag(QStyle::State_On, r->isChecked());
        o->text = r->text();
        return o;
    }
    if (auto *p = qobject_cast<QProgressBar *>(w)) {
        auto o = std::make_unique<QStyleOptionProgressBar>();
        o->initFrom(w);
        o->minimum = p->minimum();
        o->maximum = p->maximum();
        o->progress = p->value();
        return o;
    }
    // The three below are the same lesson as the menu's sizeHint: a sub-element rect is computed FROM
    // the option's rectangle, so an option without one reports `0,0,0,0` and the table reads as if
    // the style had nothing to say. The rectangle is the piece of the widget the sub-element belongs
    // to, which is what the style is being asked about.
    if (auto *tb = qobject_cast<QTabBar *>(w)) {
        auto o = std::make_unique<QStyleOptionTab>();
        o->initFrom(w);
        o->rect = tb->tabRect(0);
        o->text = tb->tabText(0);
        o->position = QStyleOptionTab::Beginning;
        return o;
    }
    if (auto *lv = qobject_cast<QListWidget *>(w)) {
        auto o = std::make_unique<QStyleOptionViewItem>();
        o->initFrom(w);
        if (lv->count() > 1 && lv->item(1)) {
            o->rect = lv->visualItemRect(lv->item(1));
        }
        return o;
    }
    if (auto *t = qobject_cast<QTableWidget *>(w)) {
        auto o = std::make_unique<QStyleOptionHeader>();
        o->initFrom(w);
        const int h = t->horizontalHeader() ? t->horizontalHeader()->height() : 0;
        o->rect = QRect(0, 0, t->columnWidth(0), h > 0 ? h : 24);
        o->section = 0;
        o->text = QStringLiteral("A");
        o->position = QStyleOptionHeader::Beginning;
        return o;
    }
    auto o = std::make_unique<QStyleOption>();
    o->initFrom(w);
    return o;
}

QString rectText(const QRect &r)
{
    return QStringLiteral("%1,%2,%3,%4").arg(r.x()).arg(r.y()).arg(r.width()).arg(r.height());
}

// WHAT GOES INTO `sizeFromContents` IS PART OF THE MEASUREMENT. The call is "given a content of
// this size, how big is the whole control", so handing it the WIDGET's sizeHint measures nothing:
// for CT_MenuItem it returned `109x129`, which is the whole menu, not an item. The content sizes
// below are a text-sized box, which is what these calls are asking about -- and the number a slice
// will compare with the kit's 24 px menu height.
QSize contentsInput(QStyle::ContentsType ct, QWidget *w)
{
    switch (ct) {
    case QStyle::CT_MenuItem:
    case QStyle::CT_MenuBarItem:
    case QStyle::CT_TabBarTab:
        return QSize(80, 16);
    default:
        return w->sizeHint();
    }
}

// The option `sizeFromContents` needs. Several content types read the OPTION and not only the
// widget: CT_MenuItem asks for the item's TYPE, and asking with a null option measures nothing while
// printing a number. The generic widget option is the fallback for the types that only look at the
// widget.
std::unique_ptr<QStyleOption> contentsOptionFor(QStyle::ContentsType ct, QWidget *w)
{
    if (ct == QStyle::CT_MenuItem || ct == QStyle::CT_MenuBarItem) {
        auto o = std::make_unique<QStyleOptionMenuItem>();
        o->initFrom(w);
        o->text = QStringLiteral("File");
        o->menuItemType = QStyleOptionMenuItem::Normal;
        o->checkType = QStyleOptionMenuItem::NotCheckable;
        return o;
    }
    if (ct == QStyle::CT_TabBarTab) {
        auto o = std::make_unique<QStyleOptionTab>();
        o->initFrom(w);
        o->text = QStringLiteral("Tab");
        return o;
    }
    return elementOptionFor(w);
}

// Every metric this gallery records for one primitive, as "key=value" lines. The SAME function is
// called for the base and for ours, and the two lists are compared LINE BY LINE: same order, same
// keys, so a difference is a value and never a reordering.
QStringList metricsFor(QStyle *style, const Primitive &p, QWidget *w)
{
    QStringList out;
    out << QStringLiteral("sizeHint=%1x%2").arg(w->sizeHint().width()).arg(w->sizeHint().height());
    for (QStyle::PixelMetric pm : p.pixels) {
        const char *name = pmName(pm);
        if (!name) {
            continue;
        }
        out << QStringLiteral("pixelMetric(%1)=%2").arg(QLatin1String(name)).arg(style->pixelMetric(pm, nullptr, w));
    }
    for (QStyle::ContentsType ct : p.contents) {
        const char *name = ctName(ct);
        if (!name) {
            continue;
        }
        auto opt = contentsOptionFor(ct, w);
        const QSize s = style->sizeFromContents(ct, opt.get(), contentsInput(ct, w), w);
        out << QStringLiteral("sizeFromContents(%1)=%2x%3").arg(QLatin1String(name)).arg(s.width()).arg(s.height());
    }
    for (const auto &[cc, sc] : p.subs) {
        const char *ccn = ccName(cc);
        const char *scn = scName(cc, sc);
        if (!ccn || !scn) {
            continue;
        }
        auto opt = optionFor(cc, w);
        if (!opt) {
            continue; // no complex option for this control: nothing to ask
        }
        const QRect r = style->subControlRect(cc, opt.get(), sc, w);
        out << QStringLiteral("subControlRect(%1,%2)=%3")
                   .arg(QLatin1String(ccn), QLatin1String(scn), rectText(r));
    }
    for (QStyle::SubElement se : p.elements) {
        const char *name = seName(se);
        if (!name) {
            continue;
        }
        auto opt = elementOptionFor(w);
        const QRect r = style->subElementRect(se, opt.get(), w);
        out << QStringLiteral("subElementRect(%1)=%2").arg(QLatin1String(name), rectText(r));
    }
    return out;
}

QSize sizeFor(const Primitive &p)
{
    QWidget parent;
    std::unique_ptr<QWidget> w(p.make(&parent));
    return w->sizeHint().expandedTo(QSize(140, 30));
}

} // namespace

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    QString renderPath;
    QString baselinePath;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == QLatin1String("--render") && i + 1 < argc) {
            renderPath = QString::fromLocal8Bit(argv[++i]);
        } else if (a == QLatin1String("--baseline") && i + 1 < argc) {
            baselinePath = QString::fromLocal8Bit(argv[++i]);
        }
    }

    std::unique_ptr<QStyle> probe(QStyleFactory::create(QStringLiteral("KdeMacOS")));
    if (!probe) {
        std::printf("CREATE: NULL\n");
        return 3;
    }
    const QString baseKey = probe->property("kdeMacosBaseStyle").toString();
    probe.reset();

    // ---- the metrics, base against ours, per primitive -----------------------------------------
    // One application style at a time, because sizeHint() and the widget's own state ask the
    // APPLICATION's style: measuring them under a style that is not set would report the other one.
    struct Row {
        QStringList base;
        QStringList ours;
        int differing = 0;
    };
    std::vector<Row> metrics(primitives().size());
    long metricDifferences = 0;

    for (int pass = 0; pass < 2; ++pass) {
        std::unique_ptr<QStyle> style(QStyleFactory::create(
            pass == 0 ? baseKey : QStringLiteral("KdeMacOS")));
        if (!style) {
            std::printf("METRICS: could not create the %s style\n", pass == 0 ? "base" : "ours");
            return 4;
        }
        QApplication::setStyle(style.release()); // the application owns it from here
        QStyle *current = QApplication::style();
        QWidget parent;
        for (size_t i = 0; i < primitives().size(); ++i) {
            const Primitive &p = primitives()[i];
            std::unique_ptr<QWidget> w(p.make(&parent));
            QStringList lines = metricsFor(current, p, w.get());
            if (pass == 0) {
                metrics[i].base = lines;
            } else {
                metrics[i].ours = lines;
                for (int k = 0; k < lines.size() && k < metrics[i].base.size(); ++k) {
                    if (lines[k] != metrics[i].base[k]) {
                        ++metrics[i].differing;
                        ++metricDifferences;
                    }
                }
            }
        }
    }

    // ---- the pixels, per widget ----------------------------------------------------------------
    QHash<QString, long> paintedBase;
    QHash<QString, long> paintedOurs;
    QHash<QString, long> diffs;
    QHash<QString, QImage> imageBase;
    QHash<QString, QImage> imageOurs;
    long changedWidgets = 0;

    for (int pass = 0; pass < 2; ++pass) {
        std::unique_ptr<QStyle> style(QStyleFactory::create(
            pass == 0 ? baseKey : QStringLiteral("KdeMacOS")));
        QApplication::setStyle(style.release());
        for (const Primitive &p : primitives()) {
            const QSize size = sizeFor(p);
            const QImage img = renderOne(p.make, size);
            // What the CONTROL drew, over an empty widget of its own size -- see renderBlank above.
            const long painted = differingPixels(img, renderBlank(size));
            const QString key = QLatin1String(p.name);
            if (pass == 0) {
                imageBase.insert(key, img);
                paintedBase.insert(key, painted);
            } else {
                imageOurs.insert(key, img);
                paintedOurs.insert(key, painted);
            }
        }
    }

    for (const Primitive &p : primitives()) {
        const QString key = QLatin1String(p.name);
        const long d = differingPixels(imageBase.value(key), imageOurs.value(key));
        diffs.insert(key, d);
        if (d != 0) {
            ++changedWidgets;
        }
    }

    // ---- the report ----------------------------------------------------------------------------
    std::printf("BASE: %s\n", baseKey.toUtf8().constData());
    std::printf("PRIMITIVES: %d\n", int(primitives().size()));

    for (size_t i = 0; i < primitives().size(); ++i) {
        const Primitive &p = primitives()[i];
        const QString key = QLatin1String(p.name);
        const QImage &bi = imageBase.value(key);
        const long total = long(bi.width()) * bi.height();
        std::printf("WIDGET %s PAINTED base=%ld ours=%ld DIFF %ld of %ld\n", p.name,
                    paintedBase.value(key), paintedOurs.value(key), diffs.value(key), total);
    }
    for (size_t i = 0; i < primitives().size(); ++i) {
        const Primitive &p = primitives()[i];
        for (const QString &line : metrics[i].base) {
            std::printf("METRIC %s %s\n", p.name, line.toUtf8().constData());
        }
        std::printf("METRICDIFF %s %d\n", p.name, metrics[i].differing);
    }

    if (!baselinePath.isEmpty()) {
        FILE *f = std::fopen(baselinePath.toLocal8Bit().constData(), "w");
        if (!f) {
            std::printf("BASELINE: could not write %s\n", baselinePath.toUtf8().constData());
            return 8;
        }
        std::fprintf(f, "# M6 slice 1: the BASE style's metrics per primitive, the \"before\" every\n");
        std::fprintf(f, "# following slice diffs against. Written by primitive-gallery --baseline.\n");
        std::fprintf(f, "BASE %s\n", baseKey.toUtf8().constData());
        for (size_t i = 0; i < primitives().size(); ++i) {
            for (const QString &line : metrics[i].base) {
                std::fprintf(f, "METRIC %s %s\n", primitives()[i].name, line.toUtf8().constData());
            }
        }
        std::fclose(f);
    }

    // ---- our own evidence ----------------------------------------------------------------------
    if (!renderPath.isEmpty()) {
        const int cols = 4;
        const int cellW = 220;
        const int cellH = 110;
        const int labelH = 18;
        const int rows = int((primitives().size() + cols - 1) / cols);
        const int panelW = cols * cellW;
        const int panelH = labelH + rows * cellH;
        const int titleH = 24;
        QImage sheet(panelW * 2, panelH + titleH + labelH, QImage::Format_RGB32);
        sheet.fill(QColor(250, 250, 250));
        QPainter painter(&sheet);
        painter.setPen(Qt::black);
        painter.drawText(QRect(0, 0, panelW, titleH), Qt::AlignCenter,
                         QStringLiteral("base: %1").arg(baseKey));
        painter.drawText(QRect(panelW, 0, panelW, titleH), Qt::AlignCenter,
                         QStringLiteral("ours: KdeMacOS (every primitive delegated)"));
        for (size_t i = 0; i < primitives().size(); ++i) {
            const Primitive &p = primitives()[i];
            const QString key = QLatin1String(p.name);
            const int col = int(i) % cols;
            const int row = int(i) / cols;
            const int x0 = col * cellW;
            const int y0 = titleH + labelH + row * cellH;
            for (int panel = 0; panel < 2; ++panel) {
                const int x = panel * panelW + x0;
                const QImage &img = panel == 0 ? imageBase.value(key) : imageOurs.value(key);
                painter.drawImage(x + 6, y0 + 6, img);
                painter.drawText(QRect(x + 6, y0 + cellH - 16, cellW - 12, 14),
                                 Qt::AlignLeft, key);
            }
        }
        // The line under the panels is the whole claim of the slice, in the image itself: a gallery
        // that looked identical without SAYING why would be a picture of nothing changing.
        painter.drawText(QRect(0, sheet.height() - labelH, sheet.width(), labelH), Qt::AlignCenter,
                         QStringLiteral("%1 primitives - pixel differences: %2 - metric differences: %3")
                             .arg(primitives().size())
                             .arg(changedWidgets)
                             .arg(metricDifferences));
        painter.end();
        if (!sheet.save(renderPath)) {
            std::printf("RENDER: could not write %s\n", renderPath.toUtf8().constData());
            return 9;
        }
    }

    // ---- the verdict ---------------------------------------------------------------------------
    // A non-zero here is not a bug in the tool: it is the tool saying the no-op property no longer
    // holds, which is exactly what a slice implementing a primitive must account for, in the test,
    // WITH its measurement.
    if (changedWidgets != 0) {
        std::printf("CHANGED: %ld\n", changedWidgets);
        return 5;
    }
    if (metricDifferences != 0) {
        std::printf("METRICS CHANGED: %ld\n", metricDifferences);
        return 6;
    }
    // And the anti-cheat: a gallery where NOTHING painted would compare two empty canvases and
    // report the same zero.
    long paintedAny = 0;
    for (const Primitive &p : primitives()) {
        paintedAny += paintedBase.value(QLatin1String(p.name));
    }
    if (paintedAny <= 0) {
        std::printf("NOTHING PAINTED\n");
        return 7;
    }
    return 0;
}

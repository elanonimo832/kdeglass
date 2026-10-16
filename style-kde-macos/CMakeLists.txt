# style-kde-macos — the M6 QStyle, FIRST SLICE (a skeleton that compiles, installs and is selectable).
#
# THE TWO THINGS THIS FILE KNOWS THAT ARE NOT OBVIOUS. Both were MEASURED with a probe plugin on
# this machine (Qt 6.12), and both are the difference between a plugin Qt finds and one it ignores
# in silence:
#
# 1. QStyleFactory DOES NOT SCAN the plugin path: it scans its `styles/` SUBDIRECTORY. A plugin
#    built at `build/kdemacosstyle.so` is invisible; at `build/styles/kdemacosstyle.so` Qt finds it
#    and lists it in QStyleFactory::keys(). That is why CMAKE_LIBRARY_OUTPUT_DIRECTORY points at
#    `styles`.
#
# 2. `qt_add_plugin` in this Qt takes NO `SOURCES` keyword. Its keyword lists are STATIC/SHARED and
#    CLASS_NAME/OUTPUT_NAME/PLUGIN_TYPE/OUTPUT_TARGETS, so `SOURCES src/x.cpp` is parsed as a source
#    file called "SOURCES" and the configure step fails with "Cannot find source file:
#    <build>/SOURCES". The sources are passed as plain arguments, as below.
#
# The project's other C++ component is `effect-kwin/`, and this follows its shape: a `build.sh` that
# configures and builds, the plugin built by CMake, and no installation here (the repository's
# `install.sh` owns that, and it is the one with a rollback).
cmake_minimum_required(VERSION 3.20)
project(kdemacosstyle VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# See note 1 above: the `styles` subdirectory is not cosmetic, it is how Qt finds a style plugin.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/styles")
if(NOT CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)

# See note 2 above: the sources go as plain arguments, NOT after a `SOURCES` keyword.
qt_add_plugin(kdemacosstyle CLASS_NAME MacosStylePlugin src/macosstyle.cpp)
target_include_directories(kdemacosstyle PRIVATE src)
target_link_libraries(kdemacosstyle PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets)
# No `lib` prefix: the file name is what a human has to read in a directory listing, and Qt derives
# nothing from it (the style is selected by the metadata Keys, not by the file name).
set_target_properties(kdemacosstyle PROPERTIES PREFIX "" OUTPUT_NAME "kdemacosstyle")

# The probe IS the test of the slice: it creates the style through the factory, sets it on an
# application and renders a widget under the offscreen platform. Built as part of the component so
# `tests/test-style.sh` has something to RUN, not just something to read.
add_executable(style-probe tests/style-probe.cpp)
target_link_libraries(style-probe PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets)

# Slice 1: the PRIMITIVE INSTRUMENT. The probe above answers "does it change anything" for ONE
# widget; this renders a gallery and reports, per primitive, the pixel difference against the base
# style, what Qt asks that control for (pixelMetric, sizeFromContents, subControlRect, sizeHint),
# and whether OUR metrics differ from the base's. It is what the following slices diff against, and
# it is built here so `tests/test-style-gallery.sh` has something to run.
add_executable(primitive-gallery tests/primitive-gallery.cpp)
target_link_libraries(primitive-gallery PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets)

# The user-level path, which is the one the repository's installer uses: it never escalates and
# never writes outside $HOME. Qt does NOT search it by itself (MEASURED: the library paths are
# QT_PLUGIN_PATH, then /usr/lib/qt6/plugins, then the application's directory), so the installer
# also sets QT_PLUGIN_PATH for the session -- see ../../install.sh.
install(TARGETS kdemacosstyle LIBRARY DESTINATION lib/qt6/plugins/styles)

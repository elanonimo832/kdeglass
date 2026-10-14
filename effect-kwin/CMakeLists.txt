# Project KWin effect: macOS-style material.
#
# REQUIREMENTS (all present except the Vulkan stub, explained below):
#   cmake, ninja, extra-cmake-modules, and the KWin/KF6 headers.
#
# NOTES ON WHAT IT COST TO FIGURE OUT (so the path is not repeated):
#
# 1. KWinConfig.cmake requires ECM and Vulkan. Vulkan is only needed to SATISFY
#    find_package: this effect neither includes nor uses Vulkan, and the runtime is
#    already there. Instead of installing vulkan-headers (42 MiB), Vulkan_INCLUDE_DIR
#    points to a stub. See _stub/vulkan/.
#
# 2. The plugin metadata is provided by the KWIN_EFFECT_FACTORY_SUPPORTED macro in
#    glass.cpp itself, via Q_PLUGIN_METADATA. It must NOT be passed through CMake.
#    Without it, QPluginLoader answers "is not a Qt plugin" (which happened to us
#    when compiling by hand).
#
# 3. kcoreaddons_add_plugin only accepts SOURCES, INSTALL_NAMESPACE and STATIC.
#
# 4. The install path is critical. See the comment at the install() call.
cmake_minimum_required(VERSION 3.20)
project(macosglass2 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(ECM 6.26 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})
include(KDEInstallDirs)

find_package(KWin REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Qml)
find_package(KF6CoreAddons REQUIRED)

# CRITICAL: kcoreaddons_add_plugin builds a STATIC library if BUILD_SHARED_LIBS is
# false, and a KWin plugin must be a shared module. Without this a .a is produced
# and KWin cannot load it.
set(BUILD_SHARED_LIBS ON)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins")
if(NOT CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

# The metadata must sit next to the code so that rcc picks it up.
configure_file(src/metadata.json ${CMAKE_BINARY_DIR}/metadata.json COPYONLY)

# kcoreaddons_add_plugin REQUIRES this to be defined.
kcoreaddons_add_plugin(macosglass2
    INSTALL_NAMESPACE kwin/effects
    SOURCES
        src/glass.cpp
        src/qtmetadata.qrc
)

target_include_directories(macosglass2 PRIVATE src ${CMAKE_BINARY_DIR})
target_link_libraries(macosglass2 PRIVATE
    KWin::kwin
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Qml
)

# CRITICAL: without this, CMake produces `libmacosglass2.so` and KWin derives the
# pluginId from the FILE NAME -> "libmacosglass2". The effect is enabled in kwinrc as
# "macosglass2", so KWin would never find it. The `lib` prefix breaks the identifier.
set_target_properties(macosglass2 PROPERTIES PREFIX "" OUTPUT_NAME "macosglass2")

# CRITICAL PATH: KWin::PluginEffectLoader looks in "kwin/effects/plugins" (verified
# in its source code: m_pluginSubDirectory = "kwin/effects/plugins"). Installing in
# "kwin/effects" leaves the .so one level up and KWin does NOT see it, silently.
install(TARGETS macosglass2
        LIBRARY DESTINATION lib/qt6/plugins/kwin/effects/plugins)

# NOTE: no separate metadata.json is installed. A C++ effect carries its metadata
# EMBEDDED in the .so (placed there by KWIN_EFFECT_FACTORY_SUPPORTED + rcc). If a
# metadata.json is also left in share/kwin/effects/<id>/, KWin takes it for a
# SCRIPTED effect and fails with "invalid X-Plasma-API field".

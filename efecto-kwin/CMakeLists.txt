# Efecto KWin del proyecto: material estilo macOS.
#
# REQUISITOS (todos presentes salvo el stub de Vulkan, que se explica abajo):
#   cmake, ninja, extra-cmake-modules, y los headers de KWin/KF6.
#
# NOTAS DE LO QUE COSTO AVERIGUAR (para no repetir el camino):
#
# 1. KWinConfig.cmake exige ECM y Vulkan. Vulkan solo hace falta para SATISFACER
#    el find_package: este efecto no incluye ni usa Vulkan, y el runtime ya esta.
#    En vez de instalar vulkan-headers (42 MiB), se apunta Vulkan_INCLUDE_DIR a
#    un stub. Ver _stub/vulkan/.
#
# 2. La metadata del plugin la aporta el macro KWIN_EFFECT_FACTORY_SUPPORTED del
#    propio glass.cpp, via Q_PLUGIN_METADATA. NO hay que pasarla por CMake.
#    Sin ella, QPluginLoader responde "is not a Qt plugin" (nos paso compilando
#    a mano).
#
# 3. kcoreaddons_add_plugin SOLO acepta SOURCES, INSTALL_NAMESPACE y STATIC.

cmake_minimum_required(VERSION 3.20)
project(macosglass2 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# IMPRESCINDIBLE: kcoreaddons_add_plugin construye una biblioteca ESTATICA si
# BUILD_SHARED_LIBS es falso, y un plugin de KWin tiene que ser un modulo
# compartido. Sin esto se genera un .a y KWin no puede cargarlo.
set(BUILD_SHARED_LIBS ON)

include(ECMFindModuleHelpers OPTIONAL)
find_package(ECM 6.26 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})
include(KDEInstallDirs)

find_package(KWin REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Qml)
find_package(KF6CoreAddons REQUIRED)

# kcoreaddons_add_plugin EXIGE que esto este definido.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins")
if(NOT CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
endif()

# La metadata tiene que existir junto al codigo para que el rcc la recoja.
configure_file(src/metadata.json ${CMAKE_BINARY_DIR}/metadata.json COPYONLY)

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

# CRITICO: sin esto, CMake genera `libmacosglass.so` y KWin deriva el pluginId del
# nombre del fichero -> "libmacosglass". Pero el efecto se activa en kwinrc como
# "macosglass", asi que KWin no lo encuentra. El prefijo `lib` rompe el identificador.
set_target_properties(macosglass2 PROPERTIES PREFIX "" OUTPUT_NAME "macosglass2")

# El macro instala el .so, pero se fija la ruta para que caiga en la de KWin.
# RUTA CRITICA: KWin::PluginEffectLoader busca en "kwin/effects/plugins" (verificado
# en su codigo fuente: m_pluginSubDirectory = "kwin/effects/plugins"). Instalar en
# "kwin/effects" deja el .so un nivel arriba y KWin NO lo ve, sin ningun mensaje.
install(TARGETS macosglass2
        LIBRARY DESTINATION lib/qt6/plugins/kwin/effects/plugins)
# OJO: NO se instala metadata.json aparte. Un efecto C++ lleva la metadata
# EMBEBIDA en el .so (la pone KWIN_EFFECT_FACTORY_SUPPORTED + el rcc). Si ademas
# se deja un metadata.json en share/kwin/effects/<id>/, KWin lo toma por un efecto
# SCRIPTED y falla con "invalid X-Plasma-API field".

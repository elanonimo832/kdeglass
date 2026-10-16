#!/usr/bin/env python3
"""
generate-global-theme.py — Builds the Plasma GLOBAL theme (LookAndFeel) and its PlasmaStyle

WHAT IT DOES
    Writes the two KDE packages that turn the loose pieces this project already generates
    (the colour scheme, the window decoration, the KWin effect) into ONE thing the user can
    pick in System Settings -> Global Theme:

        output/look-and-feel/KdeMacOS/metadata.json      KPackageStructure: Plasma/LookAndFeel
        output/look-and-feel/KdeMacOS/contents/defaults  the file that applies the parts
        output/desktoptheme/KdeMacOS/metadata.json       X-Plasma-API: 5.0
        output/desktoptheme/KdeMacOS/colors              the PlasmaStyle's own palette
        output/desktoptheme/KdeMacOS/plasmarc

THE IMPORTANT ARCHITECTURAL DECISIONS

  1. THE VERSION IS READ, NOT WRITTEN. `KPlugin.Version` is taken from
     output/aurorae/KdeMacOS/metadata.desktop, which the decoration generator writes. One
     number, one place: a version typed twice drifts, and the test checks the two agree.

  2. IT DOES NOT INVENT PARTS THIS PROJECT DOES NOT SHIP. The icons (M5), the widget style
     (M6) and the cursor are set to KDE's own defaults, which exist on any Plasma install,
     so applying the theme cannot leave the user without icons. When M5/M6 ship theirs, this
     file is the only place that changes.

  3. IT DOES NOT TOUCH WHAT IS NOT OURS. No wallpaper and no splash of our own: the theme
     applies its parts and leaves the rest as the user had it. A global theme that resets
     the wallpaper to announce itself is a theme that breaks something on purpose.

  4. NO DATE IN THE OUTPUT. The colour schemes carry a "# Date:" header and are therefore
     only reproducible on the same day. These files are declarative, so they are the same
     bytes tomorrow: the reproducibility test in tests/test-global-theme.sh is real and not
     a same-day formality.

USAGE
    python3 generate-global-theme.py [output/]
    (with no argument it writes to the output/ next to this script, which is what the test
    calls, so that "regenerate and compare" regenerates for real.)
"""

from __future__ import annotations

import json
import os
import shutil
import sys

ID = "KdeMacOS"
NOMBRE = "KdeMacOS"
DESCRIPCION = "macOS-style desktop: measured from the kit's tokens, no Apple material"
LICENCIA = "GPLv3"
AUTOR = "kdeglass (generated from the kit's tokens)"
ESQUEMA_CLARO = "KdeMacosLight"
DECORACION = "__aurorae__svg__KdeMacOS"
EFECTO = "macosglass2"
# What we do not ship yet: KDE's own defaults, which exist everywhere. M5 replaces the icons
# and M6 the widget style; until then naming ours here would leave the user without them.
ICONOS = "breeze"
ESTILO = "Breeze"
CURSOR = "breeze_cursors"
SPLASH = "org.kde.breeze.desktop"

# ---------------------------------------------------------------------------
# M4 -- THE TYPE SCALE. Three measured facts decide these lines. The probe was a small Qt 6.12
# program run against this machine, and the numbers are recorded in docs/HANDOFF.md (M4):
#
#   * THE UNIT IS PIXELS. macOS draws a "13 pt" style at 13 px, and it has NO Dynamic Type: the
#     scale is fixed (the HIG says so, and the ROADMAP repeats it). KDE renders POINTS at its font
#     DPI -- 96 here, with no `forceFontDPI` key set -- so 13 pt would render 13 * 96/72 = 17.3 px,
#     a third larger than macOS. macOS's number therefore goes in the PIXEL field and the point
#     field stays -1. `QFont::fromString` round-trips it (measured: pixelSize=13 back).
#   * THE WEIGHT IS THE LEGACY 0..99 CODE. `QFont::fromString` reads `400` as **900 (Black)**: the
#     modern Qt/CSS weights all saturate at Black. Measured table: 0->100, 12->200, 25->300,
#     50->400, 57->500, 63->600, 75->700, 81->800, 87->900. Writing Qt's own `toString()` output
#     (400 for Normal) paints every label black -- tests/test-typography.sh forbids it by name.
#   * THE TRACKING HAS NO DESTINATION, and this is not an omission: kdeglobals has no
#     letter-spacing key. 64 of the 80 typography tokens are tracking values, so they cannot be
#     applied here at all; they need QSS/widget-level styling (M6). The other 7 of the 80 are
#     styles with no KDE role (large_title, title_1..3, callout, footnote, caption_1): kdeglobals
#     has about seven font keys and they do not map one-to-one onto the HIG's eleven styles.
# ---------------------------------------------------------------------------
FAMILIA = "Inter"   # SF Pro is Apple's and is NOT redistributable; Inter is SIL OFL.
FAMILIA_MONO = "Noto Sans Mono"   # macOS's SF Mono has no HIG size token: a DECLARED fallback.
# Install the family with:   sudo pacman -S inter-font      (Arch/CachyOS: extra/inter-font 4.1-1)
# If it is absent, fontconfig substitutes its own default (measured on this machine: Noto Sans) and
# the generated file is still correct: it asks for the family the project chose, and says so here.
PESO_LEGACY = {100: 0, 200: 12, 300: 25, 400: 50, 500: 57, 600: 63, 700: 75, 800: 81, 900: 87}

# WHICH macOS STYLE GOES TO WHICH KDE ROLE. kdeglobals has about seven font keys and the HIG has
# eleven styles, so this is a MAPPING with a reason per line, not a translation:
#   font                  the interface's base text   -> Body (the HIG's most common style)
#   menuFont              menus                       -> Body (macOS menus are body-sized)
#   toolBarFont           toolbar labels              -> Subheadline (the less prominent style)
#   smallestReadableFont  the smallest legible text   -> Caption 2 (the HIG's smallest)
#   [WM] activeFont       the window title, focused   -> Headline (the emphasised body)
#   [WM] inactiveFont     the window title, inactive  -> Body
# `fixed` is NOT here: macOS gives no monospaced size token, so it is a declared fallback.
ROLES_M4 = {
    ("General", "font"): "body",
    ("General", "menuFont"): "body",
    ("General", "toolBarFont"): "subheadline",
    ("General", "smallestReadableFont"): "caption_2",
    ("WM", "activeFont"): "headline",
    ("WM", "inactiveFont"): "body",
}


def fuente(tamano_px: int, peso_css: int, familia: str = FAMILIA) -> str:
    """One kdeglobals font string: `family,pointSize,pixelSize,styleHint,weight,...`.

    The point size is -1 ON PURPOSE: the size goes in PIXELS (measured -- see the M4 block above),
    and the weight is the LEGACY code (also measured: 400 would be read as Black).
    """
    return f"{familia},-1,{tamano_px},5,{PESO_LEGACY[peso_css]},0,0,0,0,0"


def leer_estilos(raiz: str) -> dict:
    """The macOS styles, READ from the tokens: the generator does not restate the numbers."""
    import tomllib
    ruta = os.path.join(raiz, "tokens", "tokens-typography_macos.toml")
    with open(ruta, "rb") as f:
        return tomllib.load(f)["estilos"]


def bloque_fuentes(estilos: dict) -> dict[str, str]:
    """The `[kdeglobals]` font keys M4 applies, per GROUP, derived from the tokens.

    Nothing here is hard-coded from the HIG: the sizes and the weights come from the token file,
    which is why tests/test-typography.sh can cross-check the generated file against it.
    """
    por_grupo: dict[str, list[str]] = {}
    for (grupo, clave), estilo in ROLES_M4.items():
        tamano = int(estilos[estilo]["tamano"])
        peso = int(estilos[estilo]["peso"])
        por_grupo.setdefault(grupo, []).append(f"{clave}={fuente(tamano, peso)}")
    # The monospaced family: Body's size, Regular. A DECLARED fallback (the HIG gives no token).
    por_grupo.setdefault("General", []).append(
        f"fixed={fuente(int(estilos['body']['tamano']), 400, FAMILIA_MONO)}"
    )
    return {g: "\n".join(l) for g, l in por_grupo.items()}


def leer_version(destino: str) -> str:
    """The project's version, read from the decoration's metadata: one number, one place."""
    ruta = os.path.join(destino, "aurorae", ID, "metadata.desktop")
    if not os.path.isfile(ruta):
        raise SystemExit(
            f"missing {ruta}: run generate-macos-decoration.py first, it owns the version"
        )
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.startswith("X-KDE-PluginInfo-Version="):
                return linea.split("=", 1)[1].strip()
    raise SystemExit(f"{ruta} declares no X-KDE-PluginInfo-Version")


def metadatos(version: str, estructura: str, descripcion: str) -> dict:
    """The KPlugin block KDE reads to list the package."""
    return {
        "KPackageStructure": estructura,
        "KPlugin": {
            "Authors": [{"Name": AUTOR}],
            "Category": "",
            "Description": descripcion,
            "EnabledByDefault": True,
            "Id": ID,
            "License": LICENCIA,
            "Name": NOMBRE,
            "Version": version,
            "Website": "",
        },
    }


def metadatos_plasma_style(version: str, descripcion: str) -> dict:
    """A desktop theme also declares the API it is written against (measured: 5.0)."""
    d = metadatos(version, "Plasma/DesktopTheme", descripcion)
    return {"X-Plasma-API": "5.0", **d}


def escribir_json(ruta: str, datos: dict) -> None:
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(datos, f, indent=4, ensure_ascii=False, sort_keys=True)
        f.write("\n")


def escribir_defaults(ruta: str, estilos: dict) -> None:
    """KDE's `contents/defaults`: the sections are [file][group], not plain INI.

    M4 adds the font keys HERE, in the block that already existed: the type scale reaches KDE
    through the GLOBAL THEME, so there is no second package to install and nothing to keep in sync.
    """
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    fuentes = bloque_fuentes(estilos)
    texto = f"""# Applied by System Settings -> Global Theme -> {NOMBRE}.
# GENERATED by tools/generate-global-theme.py. DO NOT EDIT BY HAND.
#
# Every name here is checked to EXIST by tests/test-global-theme.sh: a global theme that
# points at a component nobody has is the way a theme "breaks something".

[kdeglobals][KDE]
widgetStyle={ESTILO}

[kdeglobals][General]
ColorScheme={ESQUEMA_CLARO}
{fuentes["General"]}

[kdeglobals][WM]
{fuentes["WM"]}

[kdeglobals][Icons]
Theme={ICONOS}

[plasmarc][Theme]
name={ID}

[kcminputrc][Mouse]
cursorTheme={CURSOR}

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.aurorae.v2
theme={DECORACION}

[kwinrc][Plugins]
{EFECTO}Enabled=true

[ksplashrc][KSplash]
Theme={SPLASH}
"""
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)


def escribir_plasmarc(ruta: str) -> None:
    """The PlasmaStyle's defaults. NO WALLPAPER on purpose: see decision 3 in the docstring."""
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    texto = """# GENERATED by tools/generate-global-theme.py. DO NOT EDIT BY HAND.
# No wallpaper and no splash here: the theme does not reset what it does not own.

[AdaptiveTransparency]
enabled=true
"""
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)


def copiar_esquema(destino: str) -> None:
    """The PlasmaStyle's own palette IS the light scheme: copied, so there is one source."""
    origen = os.path.join(destino, "color-schemes", f"{ESQUEMA_CLARO}.colors")
    if not os.path.isfile(origen):
        raise SystemExit(f"missing {origen}: run generate-kde-schemes.py first")
    shutil.copyfile(origen, os.path.join(destino, "desktoptheme", ID, "colors"))


# The tokens live at the PROJECT root, not under the output directory: the generator READS them.
RAIZ_PROYECTO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    destino = sys.argv[1] if len(sys.argv) > 1 else os.path.join(RAIZ_PROYECTO, "output")
    os.makedirs(destino, exist_ok=True)

    version = leer_version(destino)
    lnf = os.path.join(destino, "look-and-feel", ID)
    dt = os.path.join(destino, "desktoptheme", ID)

    escribir_json(os.path.join(lnf, "metadata.json"),
                  metadatos(version, "Plasma/LookAndFeel", DESCRIPCION))
    escribir_defaults(os.path.join(lnf, "contents", "defaults"), leer_estilos(RAIZ_PROYECTO))
    escribir_json(os.path.join(dt, "metadata.json"),
                  metadatos_plasma_style(version, DESCRIPCION))
    escribir_plasmarc(os.path.join(dt, "plasmarc"))
    copiar_esquema(destino)

    print(f"version {version} read from the decoration's metadata")
    print(f"  -> {lnf}/metadata.json + contents/defaults")
    print(f"  -> {dt}/metadata.json + colors + plasmarc")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
generate-kde-schemes.py — Genera los esquemas de color de KDE (.colors) desde los tokens

QUE HACE
    Coge los tokens de color medidos del kit de macOS 27 y construye dos esquemas de
    color de KDE Plasma, claro y oscuro, en el formato INI que espera KDE en
    ~/.local/share/color-schemes/.

LA DECISION ARQUITECTONICA IMPORTANTE
    Los tokens del kit NO son colores planos: son el patron de VELO de Apple. El texto
    no es gris, es negro o blanco con alfa decreciente (0.85, 0.5, 0.25...). KDE, en
    cambio, exige colores OPACOS en sus esquemas: no admite alfa.

    Por eso hay que COMPONER: cada color de texto se calcula poniendo el velo sobre el
    fondo concreto del grupo al que pertenece. Eso es lo que se hace aqui, y es lo que
    mantiene la fidelidad: un texto secundario sobre la ventana no da el mismo resultado
    que sobre un panel, igual que en macOS.

    El alfa se conserva en el TOML de origen, asi que la composicion es reproducible y
    auditable; no se pierde informacion en el camino.

USO
    python3 generate-kde-schemes.py tokens/tokens-colors.toml output/
"""

from __future__ import annotations

import os
import sys
import tomllib
from datetime import date

# Los modos se llaman asi en tokens-colors.toml (vienen del export de Figma).
CLARO, OSCURO = "light", "dark"


# --------------------------------------------------------------------------
# Utilidades de color
# --------------------------------------------------------------------------
def hex_a_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def componer(velo_hex: str, alfa: float, fondo: tuple[int, int, int]) -> tuple[int, int, int]:
    """Pone un velo (color + alfa) sobre un fondo opaco. Composicion 'source over'."""
    r, g, b = hex_a_rgb(velo_hex)
    return (
        round(r * alfa + fondo[0] * (1 - alfa)),
        round(g * alfa + fondo[1] * (1 - alfa)),
        round(b * alfa + fondo[2] * (1 - alfa)),
    )


def rgb(c: tuple[int, int, int]) -> str:
    """Formato de KDE: tres enteros separados por comas."""
    return f"{c[0]},{c[1]},{c[2]}"


def oscurecer(c: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, round(v * factor)) for v in c)  # type: ignore[return-value]


def aclarar(c: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(min(255, round(v + (255 - v) * factor)) for v in c)  # type: ignore[return-value]


# --------------------------------------------------------------------------
# Lectura de tokens
# --------------------------------------------------------------------------
def leer_tokens(ruta: str) -> dict:
    with open(ruta, "rb") as f:
        return tomllib.load(f)


def nodo_token(tok: dict, seccion: str, clave: str) -> dict:
    """Localiza el nodo de un token, admitiendo secciones con puntos."""
    nodo = tok
    for parte in seccion.split("."):
        nodo = nodo[parte]
    return nodo[clave]


def color(tok: dict, seccion: str, clave: str, modo: str) -> tuple[tuple[int, int, int], float]:
    """Devuelve ((r,g,b), alfa) de un token para un modo.

    `seccion` admite ruta con puntos (p. ej. "misc.table") porque en TOML las
    tablas anidadas se leen como diccionarios anidados, no con la clave completa.
    """
    t = nodo_token(tok, seccion, clave)
    # Los tokens cuyo valor es IDENTICO en ambos modos se guardan sin subclaves
    # (una sola pareja hex/alfa). Se detecta por la ausencia de la clave del modo.
    if modo not in t:
        t = {"hex": t["hex"], "alfa": t["alfa"]}
    else:
        t = t[modo]
    return hex_a_rgb(t["hex"]), float(t["alfa"])


# --------------------------------------------------------------------------
# Construccion de un esquema
# --------------------------------------------------------------------------
def construir_esquema(tok: dict, modo: str) -> dict[str, dict[str, str]]:
    """Calcula todos los grupos del esquema para un modo (claro u oscuro)."""

    def velo(seccion: str, clave: str, fondo: tuple[int, int, int]) -> tuple[int, int, int]:
        """Aplica el velo de un token (color + su alfa) sobre un fondo opaco."""
        t = nodo_token(tok, seccion, clave)
        if modo in t:
            t = t[modo]
        return componer(t["hex"], float(t["alfa"]), fondo)

    # --- fondos base ---
    fondo_ventana, _ = color(tok, "window_bg", "window_bg", modo)
    # El kit no define un "fondo de vista" distinto del de ventana: en macOS la
    # jerarquia se hace con el material, no con otro blanco/negro. KDE si necesita
    # distinguirlos, asi que la vista se separa un punto en la direccion del modo.
    fondo_vista = fondo_ventana if modo == CLARO else oscurecer(fondo_ventana, 0.82)
    # El boton lleva el relleno secundario del kit encima del fondo: es el "bezel".
    fondo_boton = velo("fill", "secondary", fondo_ventana)
    # La cabecera (barra de titulo) lleva la mitad del relleno primario.
    fondo_cabecera = componer(
        tok["fill"]["primary"][modo]["hex"],
        float(tok["fill"]["primary"][modo]["alfa"]) * 0.5,
        fondo_ventana,
    )
    # El grupo complementario es el panel de mas contraste (barras laterales oscuras).
    fondo_complementario = (
        velo("fill", "primary", fondo_ventana) if modo == CLARO
        else aclarar(fondo_ventana, 0.04)
    )

    def texto(fondo: tuple[int, int, int], nivel: str = "primary") -> tuple[int, int, int]:
        return velo("label", nivel, fondo)

    # --- acentos ---
    acento, _ = color(tok, "accent", "blue", modo)
    acento_vibrante, _ = color(tok, "accent_vibrant", "blue", modo)
    rojo, _ = color(tok, "accent", "red", modo)
    verde, _ = color(tok, "accent", "green", modo)
    naranja, _ = color(tok, "accent", "orange", modo)
    morado, _ = color(tok, "accent", "purple", modo)
    enlace = aclarar(acento, 0.15) if modo == OSCURO else acento

    # --- seleccion: fondo de acento con texto blanco, como en macOS ---
    fondo_seleccion, _ = color(tok, "misc.table", "bg_selected_active", modo)

    # --- alternos de lista ---
    alterno = velo("fill", "primary", fondo_vista)

    # El texto sobre la seleccion es SIEMPRE blanco: el kit lo declara en
    # `label / white` (#FFFFFF, alfa 1) en ambos modos.
    texto_seleccion, _ = color(tok, "label", "white", modo)

    def grupo(fondo: tuple[int, int, int], alterno_fondo=None) -> dict[str, str]:
        return {
            "BackgroundAlternate": rgb(alterno_fondo or alterno),
            "BackgroundNormal": rgb(fondo),
            "DecorationFocus": rgb(acento),
            "DecorationHover": rgb(acento_vibrante),
            "ForegroundActive": rgb(acento),
            "ForegroundInactive": rgb(texto(fondo, "tertiary")),
            "ForegroundLink": rgb(enlace),
            "ForegroundNegative": rgb(rojo),
            "ForegroundNeutral": rgb(naranja),
            "ForegroundNormal": rgb(texto(fondo, "primary")),
            "ForegroundPositive": rgb(verde),
            "ForegroundVisited": rgb(morado),
        }

    fondo_cabecera_inactiva = (
        oscurecer(fondo_cabecera, 0.97) if modo == CLARO else aclarar(fondo_cabecera, 0.06)
    )

    esquema: dict[str, dict[str, str]] = {}
    esquema["Colors:Window"] = grupo(fondo_ventana, alterno)
    esquema["Colors:View"] = grupo(fondo_vista, alterno)
    esquema["Colors:Button"] = grupo(fondo_boton, fondo_boton)
    esquema["Colors:Header"] = grupo(fondo_cabecera, fondo_cabecera)
    esquema["Colors:Header][Inactive"] = grupo(fondo_cabecera_inactiva, fondo_cabecera_inactiva)
    esquema["Colors:Complementary"] = grupo(fondo_complementario, fondo_complementario)
    esquema["Colors:Tooltip"] = grupo(fondo_cabecera, fondo_cabecera)
    esquema["Colors:Selection"] = {
        "BackgroundAlternate": rgb(oscurecer(fondo_seleccion, 0.9)),
        "BackgroundNormal": rgb(fondo_seleccion),
        "DecorationFocus": rgb(acento),
        "DecorationHover": rgb(acento_vibrante),
        "ForegroundActive": rgb(texto_seleccion),
        "ForegroundInactive": rgb(componer("#FFFFFF", 0.55, fondo_seleccion)),
        "ForegroundLink": rgb(componer("#FFFFFF", 0.9, fondo_seleccion)),
        "ForegroundNegative": rgb(componer("#FFFFFF", 0.95, fondo_seleccion)),
        "ForegroundNeutral": rgb(componer("#FFFFFF", 0.95, fondo_seleccion)),
        "ForegroundNormal": rgb(texto_seleccion),
        "ForegroundPositive": rgb(componer("#FFFFFF", 0.95, fondo_seleccion)),
        "ForegroundVisited": rgb(componer("#FFFFFF", 0.8, fondo_seleccion)),
    }
    return esquema


# --------------------------------------------------------------------------
# Efectos y secciones generales
# --------------------------------------------------------------------------
def efectos(modo: str) -> dict[str, dict[str, str]]:
    """Los grupos ColorEffects. Valores de Breeze, que es la convencion de KDE:
    no hay equivalente en el kit de macOS porque macOS no tiene este concepto."""
    return {
        "ColorEffects:Disabled": {
            "Color": "56,56,56" if modo == OSCURO else "112,111,110",
            "ColorAmount": "0",
            "ColorEffect": "0",
            "ContrastAmount": "0.65",
            "ContrastEffect": "1",
            "IntensityAmount": "0.1",
            "IntensityEffect": "2",
        },
        "ColorEffects:Inactive": {
            "ChangeSelectionColor": "true",
            "Color": "112,111,110",
            "ColorAmount": "0.025",
            "ColorEffect": "2",
            "ContrastAmount": "0.1",
            "ContrastEffect": "2",
            "Enable": "false",
            "IntensityAmount": "0",
            "IntensityEffect": "0",
        },
    }


def general(modo: str) -> dict[str, dict[str, str]]:
    """ColorScheme y shadeSortColumn los pone el instalador; aqui van los fijos."""
    return {
        "General": {"shadeSortColumn": "true"},
        "KDE": {"contrast": "4"},
        # El color de la sombra de ventana activa/inactiva. Usa la sombra medida en
        # tokens-forma-efectos.toml (dos capas); aqui KDE solo acepta un color.
        "WM": {
            "activeBackground": "0,0,0",
            "activeBlend": "0,0,0",
            "activeForeground": "255,255,255",
            "inactiveBackground": "0,0,0",
            "inactiveBlend": "0,0,0",
            "inactiveForeground": "255,255,255",
        },
    }


def escribir(ruta: str, nombre: str, esquema: dict, modo: str) -> None:
    lineas = [
        f"# Esquema de color de KDE: {nombre}",
        "#",
        "# GENERADO por tools/generate-kde-schemes.py desde",
        "# tokens/tokens-colors.toml. NO EDITAR A MANO.",
        f"# Modo: {'claro' if modo == CLARO else 'oscuro'}",
        f"# Fecha: {date.today().isoformat()}",
        "#",
        "# Los colores de texto estan COMPUESTOS: el kit de macOS usa blanco/negro con",
        "# alfa decreciente (el patron de velo) y KDE exige colores opacos. Cada valor",
        "# de texto es el velo correspondiente aplicado sobre el fondo de su grupo.",
        "",
    ]
    orden = [
        "General", "KDE", "WM",
        "ColorEffects:Disabled", "ColorEffects:Inactive",
        "Colors:Window", "Colors:View", "Colors:Button", "Colors:Selection",
        "Colors:Tooltip", "Colors:Complementary", "Colors:Header",
        "Colors:Header][Inactive",
    ]
    for g in orden:
        if g not in esquema:
            continue
        lineas.append(f"[{g}]")
        for k in sorted(esquema[g]):
            lineas.append(f"{k}={esquema[g][k]}")
        lineas.append("")

    with open(ruta, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    origen, destino = sys.argv[1], sys.argv[2]
    os.makedirs(destino, exist_ok=True)

    tok = leer_tokens(origen)
    print(f"Tokens leidos de {origen}")

    for modo, nombre in ((CLARO, "KdeMacosLight"), (OSCURO, "KdeMacosDark")):
        esq = construir_esquema(tok, modo)
        esq.update(efectos(modo))
        esq.update(general(modo))
        # ColorScheme debe apuntar al nombre del fichero para que KDE lo reconozca
        esq.setdefault("General", {})["ColorScheme"] = nombre
        ruta = os.path.join(destino, f"{nombre}.colors")
        escribir(ruta, nombre, esq, modo)
        print(f"  -> {ruta} ({len(esq)} grupos)")

    return 0


if __name__ == "__main__":
    sys.exit(main())

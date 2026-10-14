#!/usr/bin/env python3
"""
generate-kde-schemes.py — Generates the KDE color schemes (.colors) from the tokens

WHAT IT DOES
    Takes the measured color tokens from the macOS 27 kit and builds two KDE Plasma
    color schemes, light and dark, in the INI format KDE expects in
    ~/.local/share/color-schemes/.

THE IMPORTANT ARCHITECTURAL DECISION
    The kit tokens are NOT flat colors: they are Apple's VEIL pattern. Text is not
    gray, it is black or white with decreasing alpha (0.85, 0.5, 0.25...). KDE, on the
    other hand, demands OPAQUE colors in its schemes: it does not accept alpha.

    That is why we must COMPOSE: each text color is computed by putting the veil over
    the specific background of the group it belongs to. That is what is done here, and
    it is what keeps the fidelity: a secondary text over the window does not give the
    same result as over a panel, just as in macOS.

    The alpha is kept in the source TOML, so the composition is reproducible and
    auditable; no information is lost along the way.

USAGE
    python3 generate-kde-schemes.py tokens/tokens-colors.toml output/
"""

from __future__ import annotations

import os
import sys
import tomllib
from datetime import date

# The modes are named this way in tokens-colors.toml (they come from the Figma export).
CLARO, OSCURO = "light", "dark"


# --------------------------------------------------------------------------
# Color utilities
# --------------------------------------------------------------------------
def hex_a_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def componer(velo_hex: str, alfa: float, fondo: tuple[int, int, int]) -> tuple[int, int, int]:
    """Puts a veil (color + alpha) over an opaque background. 'Source over' composition."""
    r, g, b = hex_a_rgb(velo_hex)
    return (
        round(r * alfa + fondo[0] * (1 - alfa)),
        round(g * alfa + fondo[1] * (1 - alfa)),
        round(b * alfa + fondo[2] * (1 - alfa)),
    )


def rgb(c: tuple[int, int, int]) -> str:
    """KDE format: three integers separated by commas."""
    return f"{c[0]},{c[1]},{c[2]}"


def oscurecer(c: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, round(v * factor)) for v in c)  # type: ignore[return-value]


def aclarar(c: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(min(255, round(v + (255 - v) * factor)) for v in c)  # type: ignore[return-value]


# --------------------------------------------------------------------------
# Token reading
# --------------------------------------------------------------------------
def leer_tokens(ruta: str) -> dict:
    with open(ruta, "rb") as f:
        return tomllib.load(f)


def nodo_token(tok: dict, seccion: str, clave: str) -> dict:
    """Locates a token's node, allowing dotted sections."""
    nodo = tok
    for parte in seccion.split("."):
        nodo = nodo[parte]
    return nodo[clave]


def color(tok: dict, seccion: str, clave: str, modo: str) -> tuple[tuple[int, int, int], float]:
    """Returns ((r,g,b), alpha) of a token for a mode.

    `seccion` allows a dotted path (e.g. "misc.table") because in TOML nested
    tables are read as nested dictionaries, not with the full key.
    """
    t = nodo_token(tok, seccion, clave)
    # Tokens whose value is IDENTICAL in both modes are stored without subkeys
    # (a single hex/alpha pair). It is detected by the absence of the mode key.
    if modo not in t:
        t = {"hex": t["hex"], "alfa": t["alfa"]}
    else:
        t = t[modo]
    return hex_a_rgb(t["hex"]), float(t["alfa"])


# --------------------------------------------------------------------------
# Building a scheme
# --------------------------------------------------------------------------
def construir_esquema(tok: dict, modo: str) -> dict[str, dict[str, str]]:
    """Computes all the scheme groups for a mode (light or dark)."""

    def velo(seccion: str, clave: str, fondo: tuple[int, int, int]) -> tuple[int, int, int]:
        """Applies a token's veil (color + its alpha) over an opaque background."""
        t = nodo_token(tok, seccion, clave)
        if modo in t:
            t = t[modo]
        return componer(t["hex"], float(t["alfa"]), fondo)

    # --- base backgrounds ---
    fondo_ventana, _ = color(tok, "window_bg", "window_bg", modo)
    # The kit does not define a "view background" different from the window one: in
    # macOS the hierarchy is made with material, not with another white/black. KDE does
    # need to tell them apart, so the view is shifted one notch in the mode's direction.
    fondo_vista = fondo_ventana if modo == CLARO else oscurecer(fondo_ventana, 0.82)
    # The button carries the kit's secondary fill over the background: it is the "bezel".
    fondo_boton = velo("fill", "secondary", fondo_ventana)
    # The header (title bar) carries half of the primary fill.
    fondo_cabecera = componer(
        tok["fill"]["primary"][modo]["hex"],
        float(tok["fill"]["primary"][modo]["alfa"]) * 0.5,
        fondo_ventana,
    )
    # The complementary group is the highest-contrast panel (dark sidebars).
    fondo_complementario = (
        velo("fill", "primary", fondo_ventana) if modo == CLARO
        else aclarar(fondo_ventana, 0.04)
    )

    def texto(fondo: tuple[int, int, int], nivel: str = "primary") -> tuple[int, int, int]:
        return velo("label", nivel, fondo)

    # --- accents ---
    acento, _ = color(tok, "accent", "blue", modo)
    acento_vibrante, _ = color(tok, "accent_vibrant", "blue", modo)
    rojo, _ = color(tok, "accent", "red", modo)
    verde, _ = color(tok, "accent", "green", modo)
    naranja, _ = color(tok, "accent", "orange", modo)
    morado, _ = color(tok, "accent", "purple", modo)
    enlace = aclarar(acento, 0.15) if modo == OSCURO else acento

    # --- selection: accent background with white text, as in macOS ---
    fondo_seleccion, _ = color(tok, "misc.table", "bg_selected_active", modo)

    # --- list alternates ---
    alterno = velo("fill", "primary", fondo_vista)

    # The text over the selection is ALWAYS white: the kit declares it in
    # `label / white` (#FFFFFF, alpha 1) in both modes.
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
# Effects and general sections
# --------------------------------------------------------------------------
def efectos(modo: str) -> dict[str, dict[str, str]]:
    """The ColorEffects groups. Breeze values, which is the KDE convention:
    there is no equivalent in the macOS kit because macOS has no such concept."""
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
    """ColorScheme and shadeSortColumn are set by the installer; here go the fixed ones."""
    return {
        "General": {"shadeSortColumn": "true"},
        "KDE": {"contrast": "4"},
        # The color of the active/inactive window shadow. Uses the shadow measured in
        # tokens-forma-efectos.toml (two layers); here KDE only accepts one color.
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
    print(f"Tokens read from {origen}")

    for modo, nombre in ((CLARO, "KdeMacosLight"), (OSCURO, "KdeMacosDark")):
        esq = construir_esquema(tok, modo)
        esq.update(efectos(modo))
        esq.update(general(modo))
        # ColorScheme must point to the file name so that KDE recognizes it
        esq.setdefault("General", {})["ColorScheme"] = nombre
        ruta = os.path.join(destino, f"{nombre}.colors")
        escribir(ruta, nombre, esq, modo)
        print(f"  -> {ruta} ({len(esq)} groups)")

    return 0


if __name__ == "__main__":
    sys.exit(main())

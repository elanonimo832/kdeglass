#!/usr/bin/env python3
"""
generate-gtk-css.py — Generates the GTK CSS from the same tokens

WHY IT IS GENERATED AND NOT WRITTEN BY HAND
    A hand-written GTK theme falls out of sync with the tokens within the first week.
    Here the values come from tokens-colors.toml and tokens-forma-efectos.toml, which
    in turn came from Figma and from the HIG. A token change -> regenerated CSS.

WHAT IT GENERATES
    output/gtk-3.0/kde-macos.css
    output/gtk-4.0/kde-macos.css
    output/gtk-3.0/colors.css        (only the colors, for reuse)
    output/gtk-4.0/colors.css

REALISTIC EXPECTATIONS (the analysis says so, §3.3)
    This is a GTK THEME, not a QStyle. It covers color, typography, radii and borders:
    what GTK CSS allows. It does NOT change structure, layout or animations, because
    GTK does not expose them. And there are apps that ignore it entirely:
      - those that link libadwaita without opt-in
      - Flatpak ones that bundle their own theme
      - Electron/Chromium with embedded CSS
    The list of exceptions is in ANALYSIS.md.

USAGE
    python3 generate-gtk-css.py tokens/ output/
"""

from __future__ import annotations

import os
import sys
import tomllib

CLARO, OSCURO = "light", "dark"


def leer(ruta: str) -> dict:
    with open(ruta, "rb") as f:
        return tomllib.load(f)


def rgb(hexv: str) -> tuple[int, int, int]:
    h = hexv.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgba(hexv: str, alfa: float) -> str:
    r, g, b = rgb(hexv)
    return f"rgba({r}, {g}, {b}, {alfa:g})"


def solido(hexv: str) -> str:
    return hexv.upper()


def node(tok: dict, seccion: str, clave: str) -> dict:
    n = tok
    for p in seccion.split("."):
        n = n[p]
    return n[clave]


def val(tok: dict, seccion: str, clave: str, modo: str) -> tuple[str, float]:
    """(hex, alpha) of a token for a mode, tolerating tokens without subkeys."""
    t = node(tok, seccion, clave)
    if modo in t:
        t = t[modo]
    return t["hex"], float(t["alfa"])


def variables_color(tok: dict, modo: str) -> dict[str, str]:
    """The variables the rules will use. Here is the translation of concepts."""
    def v(sec, cl, m=None):
        return val(tok, sec, cl, m or modo)

    fondo, _ = v("window_bg", "window_bg")
    texto, a_texto = v("label", "primary")
    texto2, a_texto2 = v("label", "secondary")
    texto3, a_texto3 = v("label", "tertiary")
    acento, _ = v("accent", "blue")
    acento_v, _ = v("accent_vibrant", "blue")
    rojo, _ = v("accent", "red")
    verde, _ = v("accent", "green")
    naranja, _ = v("accent", "orange")
    blanco, _ = v("label", "white")
    sel_fondo, _ = v("misc.table", "bg_selected_active")
    relleno1, a1 = v("fill", "primary")
    relleno2, a2 = v("fill", "secondary")
    relleno3, a3 = v("fill", "tertiary")

    # GTK does not compose veils: we must give it rgba() and let it do so. It is the
    # direct translation of Apple's pattern into the CSS model.
    return {
        "--km-bg": solido(fondo),
        "--km-fg": rgba(texto, a_texto),
        "--km-fg-secondary": rgba(texto2, a_texto2),
        "--km-fg-tertiary": rgba(texto3, a_texto3),
        "--km-fg-on-accent": solido(blanco),
        "--km-accent": solido(acento),
        "--km-accent-hover": solido(acento_v),
        "--km-error": solido(rojo),
        "--km-success": solido(verde),
        "--km-warning": solido(naranja),
        # The veils: the heart of macOS's visual language
        "--km-veil-1": rgba(relleno1, a1),
        "--km-veil-2": rgba(relleno2, a2),
        "--km-veil-3": rgba(relleno3, a3),
        # Derived states of the veil, as in macOS (not colors of their own)
        "--km-hover": rgba(relleno1, a1),
        "--km-active": rgba(relleno1, min(1.0, a1 * 1.8)),
        "--km-border": rgba(relleno2, a2),
        "--km-selection-bg": solido(sel_fondo),
        "--km-selection-fg": solido(blanco),
        "--km-bg-alt": rgba(relleno1, a1),
    }


def variables_forma(forma: dict) -> dict[str, str]:
    """Radii and borders, measured in the .fig."""
    r = forma["radio"]
    def cerca(*candidatos):
        for c in candidatos:
            k = f"r{str(c).replace('.','_')}"
            if k in r:
                return f"{r[k]:g}px"
        return None
    return {
        "--km-radius-xs": cerca(2, 3) or "3px",
        "--km-radius-sm": cerca(4) or "4px",
        "--km-radius": cerca(5) or "5px",
        "--km-radius-md": cerca(6) or "6px",
        "--km-radius-lg": cerca(8) or "8px",
        "--km-radius-xl": cerca(12, 10) or "10px",
        "--km-radius-window": cerca(12, 16) or "12px",
        "--km-radius-pill": "9999px",
        "--km-border-width": f"{forma['borde_capilar']['grosor']:g}px",
        "--km-smoothing": f"{forma['squircle']['smoothing']:g}",
    }


def variables_tipografia(tipo: dict) -> dict[str, str]:
    """macOS type scale, from the official HIG."""
    e = tipo["estilos"]
    # NOTE: SF Pro cannot be redistributed. Inter is used, and the family is declared
    # here so it can be changed in a single place.
    return {
        "--km-font": '"Inter", "SF Pro Text", "Noto Sans", sans-serif',
        "--km-font-mono": '"JetBrains Mono", "Roboto Mono", monospace',
        "--km-fs-large-title": f"{e['large_title']['tamano']:g}px",
        "--km-fs-title1": f"{e['title_1']['tamano']:g}px",
        "--km-fs-title2": f"{e['title_2']['tamano']:g}px",
        "--km-fs-title3": f"{e['title_3']['tamano']:g}px",
        "--km-fs-headline": f"{e['headline']['tamano']:g}px",
        "--km-fs-body": f"{e['body']['tamano']:g}px",
        "--km-fs-callout": f"{e['callout']['tamano']:g}px",
        "--km-fs-subheadline": f"{e['subheadline']['tamano']:g}px",
        "--km-fs-footnote": f"{e['footnote']['tamano']:g}px",
        "--km-fs-caption": f"{e['caption_1']['tamano']:g}px",
        "--km-lh-body": f"{e['body']['interlineado']:g}px",
        "--km-weight-normal": str(e["body"]["peso"]),
        "--km-weight-headline": str(e["headline"]["peso"]),
    }


# GTK CSS does not support @media per theme, so two files are generated.
CUERPO = """
/* ==========================================================================
   MACOS DESKTOP LAYER — {modo_nombre}
   GENERADO por tools/generate-gtk-css.py. NO EDITAR A MANO.
   Fuente: tokens/tokens-colors.toml, tokens/tokens-forma-efectos.toml,
           tokens/tokens-tipografia_macos.toml
   Fecha: {fecha}
   ========================================================================== */

{raiz}

* {{
  /* Tipografia */
  font-family: var(--km-font);
  font-size: var(--km-fs-body);
  line-height: var(--km-lh-body);
  color: var(--km-fg);
  /* El "bezel": borde capilar de 1px, la firma de macOS */
  -gtk-secondary-caret-color: var(--km-accent);
}}

window, .background {{
  background-color: var(--km-bg);
  color: var(--km-fg);
}}

/* ---------- Controles: el idioma "bezel" ---------- */
button, .button {{
  background-color: var(--km-veil-2);
  background-image: none;
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-md);
  color: var(--km-fg);
  padding: 3px 12px;
  min-height: 20px;
  box-shadow: 0 1px 1px var(--km-veil-1);
}}

button:hover {{ background-color: var(--km-hover); }}
button:active, button:checked {{ background-color: var(--km-active); }}
button:disabled {{ color: var(--km-fg-tertiary); }}

button.suggested-action, button.default {{
  background-color: var(--km-accent);
  background-image: none;
  border-color: transparent;
  color: var(--km-fg-on-accent);
}}
button.suggested-action:hover {{ background-color: var(--km-accent-hover); }}

button.destructive-action {{
  background-color: var(--km-error);
  color: var(--km-fg-on-accent);
}}

/* ---------- Campos de texto: borde capilar y anillo de foco ---------- */
entry, spinbutton, searchentry {{
  background-color: var(--km-veil-2);
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius);
  color: var(--km-fg);
  padding: 3px 8px;
  min-height: 20px;
}}
/* macOS: al enfocar NO se engrosa el borde, se dibuja un ANILLO de acento */
entry:focus, spinbutton:focus, searchentry:focus {{
  border-color: var(--km-accent);
  box-shadow: 0 0 0 3px var(--km-accent);
}}

/* ---------- Seleccion: fondo de acento, texto blanco ---------- */
*:selected, row:selected, .view:selected {{
  background-color: var(--km-selection-bg);
  color: var(--km-selection-fg);
}}
selection {{ background-color: var(--km-selection-bg); color: var(--km-selection-fg); }}

/* ---------- Listas y barras laterales: seleccion por fila, sin "pildora" ---------- */
list, listview, treeview, .view {{
  background-color: var(--km-bg);
  color: var(--km-fg);
}}
row:hover, list row:hover {{ background-color: var(--km-hover); }}
row:nth-child(even) {{ background-color: var(--km-bg-alt); }}

/* ---------- Cabeceras ---------- */
headerbar, .titlebar {{
  background-color: var(--km-bg-alt);
  background-image: none;
  border-bottom: var(--km-border-width) solid var(--km-border);
  box-shadow: none;
}}
headerbar .title {{ font-size: var(--km-fs-headline); font-weight: var(--km-weight-headline); }}

/* ---------- Menus y popovers ---------- */
menu, .menu, popover, popover.background {{
  background-color: var(--km-bg);
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-lg);
  padding: 4px;
}}
menuitem:hover, menu item:hover {{
  background-color: var(--km-accent);
  color: var(--km-fg-on-accent);
}}

/* ---------- Controles de seleccion ---------- */
checkbutton check, checkbox {{
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-sm);
  background-color: var(--km-veil-2);
  min-width: 14px; min-height: 14px;
}}
checkbutton check:checked, checkbox:checked {{
  background-color: var(--km-accent);
  border-color: var(--km-accent);
  color: var(--km-fg-on-accent);
}}
radiobutton radio, radio {{
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-pill);
  background-color: var(--km-veil-2);
  min-width: 14px; min-height: 14px;
}}
radiobutton radio:checked, radio:checked {{
  background-color: var(--km-accent);
  border-color: var(--km-accent);
}}

switch {{
  background-color: var(--km-veil-3);
  border-radius: var(--km-radius-pill);
  border: none;
}}
/* En macOS el interruptor encendido es del color de ACENTO, no verde (eso es iOS) */
switch:checked {{ background-color: var(--km-accent); }}

/* ---------- Pistas de desplazamiento: finas y translucidas ---------- */
scrollbar {{
  background-color: transparent;
  border: none;
}}
scrollbar slider {{
  background-color: var(--km-fg-tertiary);
  border-radius: var(--km-radius-pill);
  min-width: 6px; min-height: 6px;
  border: 2px solid transparent;
  background-clip: padding-box;
}}
scrollbar slider:hover {{ background-color: var(--km-fg-secondary); }}

/* ---------- Separadores: borde capilar ---------- */
separator {{ background-color: var(--km-border); min-width: 1px; min-height: 1px; }}

/* ---------- Barras de progreso y escalas ---------- */
progressbar trough, levelbar trough {{
  background-color: var(--km-veil-3);
  border-radius: var(--km-radius-pill);
  min-height: 6px;
}}
progressbar progress, levelbar block.filled {{
  background-color: var(--km-accent);
  border-radius: var(--km-radius-pill);
}}
scale trough {{ background-color: var(--km-veil-3); border-radius: var(--km-radius-pill); min-height: 4px; }}
scale highlight {{ background-color: var(--km-accent); border-radius: var(--km-radius-pill); }}
scale slider {{
  background-color: #FFFFFF;
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-pill);
  min-width: 16px; min-height: 16px;
  box-shadow: 0 1px 2px var(--km-veil-2);
}}

/* ---------- Pestañas como control segmentado ---------- */
notebook > header tab {{
  background-color: var(--km-veil-2);
  border: var(--km-border-width) solid var(--km-border);
  color: var(--km-fg);
}}
notebook > header tab:checked {{
  background-color: var(--km-accent);
  color: var(--km-fg-on-accent);
}}

/* ---------- Enlaces ---------- */
link, *:link {{ color: var(--km-accent); }}

/* ---------- Tooltips ---------- */
tooltip, tooltip.background {{
  background-color: var(--km-bg);
  border: var(--km-border-width) solid var(--km-border);
  border-radius: var(--km-radius-md);
  color: var(--km-fg);
}}

/* ---------- Accesibilidad: respetar la reduccion de movimiento ---------- */
/* El brief pide animaciones, pero no a costa de la accesibilidad. */
"""


def referencia(nombre: str, version: str) -> str:
    """How a variable is invoked in each version of GTK.

    GTK3 has no CSS variables: it uses @define-color and they are invoked as @name.
    GTK4 uses normal CSS variables: var(--name).
    """
    if version == "gtk-3.0":
        return "@" + nombre[2:].replace("-", "_")
    return f"var({nombre})"


def bloque_variables(vars_: dict[str, str], version: str) -> str:
    """The declaration block, in each GTK version's dialect."""
    if version == "gtk-3.0":
        return "\n".join(
            f"@define-color {k[2:].replace('-', '_')} {v};" for k, v in vars_.items()
        )
    return ":root {\n" + "\n".join(f"  {k}: {v};" for k, v in vars_.items()) + "\n}"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    dir_tokens, destino = sys.argv[1], sys.argv[2]

    col = leer(os.path.join(dir_tokens, "tokens-colors.toml"))
    forma = leer(os.path.join(dir_tokens, "tokens-forma-efectos.toml"))
    tipo = leer(os.path.join(dir_tokens, "tokens-tipografia_macos.toml"))

    from datetime import date
    hoy = date.today().isoformat()

    for version in ("gtk-3.0", "gtk-4.0"):
        for modo, nombre in ((CLARO, "CLARO"), (OSCURO, "OSCURO")):
            d = os.path.join(destino, version)
            os.makedirs(d, exist_ok=True)
            vars_ = {
                **variables_color(col, modo),
                **variables_forma(forma),
                **variables_tipografia(tipo),
            }

            # The body of the rules is written with var(--km-*). It is translated to
            # the dialect according to the version: no fragile replacements on the text.
            cuerpo = CUERPO
            for k in vars_:
                cuerpo = cuerpo.replace(f"var({k})", referencia(k, version))
            cuerpo = cuerpo.format(modo_nombre=nombre, fecha=hoy,
                                   raiz=bloque_variables(vars_, version))

            nombre_archivo = f"kde-macos{'-dark' if modo == OSCURO else ''}.css"
            with open(os.path.join(d, nombre_archivo), "w", encoding="utf-8") as f:
                f.write(cuerpo)

            # colors.css: only the color variables, so that another style sheet
            # can import them without dragging in the widget rules.
            SOLO_COLOR = (
                "bg", "fg", "accent", "veil", "selection",
                "border", "hover", "active", "error", "success", "warning",
            )
            vars_color = {
                k: v for k, v in vars_.items()
                if any(f"--km-{p}" == k or k.startswith(f"--km-{p}-") or f"-{p}" in k
                       for p in SOLO_COLOR)
            }
            with open(os.path.join(d, "colors.css"), "w", encoding="utf-8") as f:
                f.write(f"/* Solo color — {nombre}. GENERADO por generate-gtk-css.py. */\n")
                f.write(bloque_variables(vars_color, version) + "\n")
            print(f"  -> {version}/{nombre_archivo} (+colors.css, {len(vars_color)} variables)")

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
hig-typography.py — Extrae la tipografia de macOS de las HIG oficiales de Apple

FUENTE
    https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json

    La pagina de las HIG es una aplicacion JavaScript, asi que el HTML no trae el
    contenido. Los datos viven en ese JSON (DocC), y ahi estan las tablas completas:
    escalas de todas las plataformas, tamanos por defecto y minimo, y los valores de
    tracking por tamano.

    Es la fuente AUTORIZADA: Apple publica estos numeros, no hay que medirlos ni
    inferirlos. Es lo que faltaba para el eje tipografico.

USO
    python3 hig-typography.py <hig-typography.json> [salida.toml]
"""

from __future__ import annotations

import json
import sys
from datetime import date

FUENTE = "https://developer.apple.com/design/human-interface-guidelines/typography"


def txt(celda) -> str:
    """Texto de una celda: lista de parrafos -> inlineContent -> text."""
    return " ".join(
        ic.get("text", "")
        for p in celda
        for ic in p.get("inlineContent", [])
        if isinstance(ic, dict)
    ).strip()


def tabla(bloque) -> list[list[str]]:
    return [[txt(c) for c in fila] for fila in bloque.get("rows", [])]


def clave_seccion(contenido, i) -> str:
    """Busca el encabezado que precede a la tabla en el indice i."""
    for j in range(i - 1, max(0, i - 8), -1):
        if contenido[j].get("type") == "heading":
            return contenido[j].get("text", "")
    return ""


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    origen = sys.argv[1]
    salida = sys.argv[2] if len(sys.argv) > 2 else "tokens-tipografia_macos.toml"

    d = json.load(open(origen))
    contenido = d["primaryContentSections"][0]["content"]

    plataformas = None      # tamano por defecto/minimo por plataforma
    estilos_macos = None    # tabla de estilos de macOS
    tracking_macos = None   # tracking por tamano de macOS

    for i, blk in enumerate(contenido):
        if blk.get("type") != "table":
            continue
        filas = tabla(blk)
        if not filas:
            continue
        cab = " ".join(filas[0])
        if "Default size" in cab and "Minimum size" in cab:
            plataformas = filas
        if "Line height" in cab and any("Large Title" in f[0] for f in filas):
            estilos_macos = filas
        if filas[0][:1] == ["Size (points)"] and clave_seccion(contenido, i) == "macOS tracking values":
            tracking_macos = filas

    if not estilos_macos:
        print("ERROR: no se encontro la tabla de estilos de macOS.")
        return 1
    if not plataformas:
        print("ERROR: no se encontro la tabla de tamanos por plataforma.")
        return 1

    lineas = []
    n = 0

    # ---- tamano por defecto y minimo ----
    lineas.append("[tamano_base]")
    lineas.append("# Tamano recomendado por Apple para cada plataforma.")
    for fila in plataformas[1:]:
        if len(fila) < 3:
            continue
        plat = fila[0].split(",")[0].strip().lower().replace(" ", "_")
        def pt(s):
            return float(s.replace("pt", "").strip())
        lineas.append(f'{plat} = {{ por_defecto = {pt(fila[1]):g}, minimo = {pt(fila[2]):g} }}')
        n += 1
    lineas.append("")

    # ---- estilos de texto de macOS ----
    pesos = {"Regular": 400, "Medium": 500, "Semibold": 600,
             "Bold": 700, "Heavy": 800, "Black": 900}

    def clave(nombre):
        import re
        return re.sub(r"[^a-z0-9]+", "_", nombre.lower()).strip("_")

    lineas.append("[estilos]")
    lineas.append("# ESTILOS DE TEXTO DE macOS. Tabla oficial de las HIG.")
    lineas.append("# `peso` y `peso_enfatizado` son valores numericos CSS/fontconfig.")
    lineas.append("# `interlineado` es el leading en puntos. `interlineado_escala` su relacion.")
    for fila in estilos_macos[1:]:
        if len(fila) < 5:
            continue
        estilo, peso, tam, inter, enf = fila[:5]
        k = clave(estilo)
        tam_f, inter_f = float(tam), float(inter)
        p1, p2 = pesos.get(peso, "?"), pesos.get(enf, "?")
        lineas.append(f"# {estilo}: {peso} {tam}pt / leading {inter}pt")
        lineas.append(
            f'{k} = {{ tamano = {tam_f:g}, interlineado = {inter_f:g}, '
            f'interlineado_escala = {round(inter_f/tam_f, 3)}, '
            f'peso = {p1}, peso_enfatizado = {p2} }}'
        )
        n += 1
    lineas.append("")

    # ---- tracking de macOS ----
    if tracking_macos:
        lineas.append("[tracking]")
        lineas.append("# Tracking de macOS por tamano, de las HIG.")
        lineas.append("# Valores en 1/1000 em (el estandar de las herramientas) y en puntos.")
        lineas.append("# Necesario para que el texto parezca de macOS: el espaciado entre")
        lineas.append("# letras cambia con el tamano, no es constante.")
        lineas.append("#   em1000 = valor para usar como letter-spacing en CSS/QSS")
        for fila in tracking_macos[1:]:
            if len(fila) < 3 or not fila[0]:
                continue
            tam = float(fila[0])
            try:
                em = float(fila[1].replace("+", ""))
                puntos = float(fila[2].replace("+", ""))
            except ValueError:
                continue
            lineas.append(f'{tam:g} = {{ em1000 = {em:g}, puntos = {puntos:g} }}')
            n += 1
        lineas.append("")

    cabecera = [
        "# tokens-tipografia_macos.toml — GENERADO. No editar a mano.",
        "#",
        "# TIPOGRAFIA DE macOS, extraida de las Human Interface Guidelines oficiales.",
        f"# Fuente: {FUENTE}",
        "# Datos:   https://developer.apple.com/tutorials/data/design/human-interface-guidelines/typography.json",
        f"# Fecha:   {date.today().isoformat()}",
        "#",
        "# Esto CIERRA el hueco de tipografia del proyecto: son valores publicados por",
        "# Apple, no medidos ni inferidos. Cada uno es trazable a las HIG.",
        "#",
        "# AVISO SOBRE LA FUENTE TIPOGRAFICA: macOS usa SF Pro, que Apple NO permite",
        "# redistribuir. El proyecto usara Inter (SIL OFL). Los tamanos, interlineados y",
        "# pesos de este fichero se aplican tal cual; el TRACKING es especifico de SF Pro,",
        "# asi que con otra familia es una aproximacion de partida a ajustar a ojo.",
        "#",
        "# AVISO: macOS NO soporta Dynamic Type (lo dicen las propias HIG). Por eso aqui",
        "# hay UNA sola escala, no doce como en iOS. No hay que buscar variantes.",
        "",
        "[_meta]",
        f'fuente = "{FUENTE}"',
        'plataforma = "macOS"',
        f"tokens = {n}",
        f'fecha_extraccion = "{date.today().isoformat()}"',
        "",
    ]

    with open(salida, "w", encoding="utf-8") as f:
        f.write("\n".join(cabecera + lineas))

    print(f"Escrito {salida}: {n} tokens")
    print(f"  plataformas: {len(plataformas)-1}")
    print(f"  estilos macOS: {len(estilos_macos)-1}")
    print(f"  valores de tracking: {max(0, len(tracking_macos)-1) if tracking_macos else 'NO ENCONTRADOS'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

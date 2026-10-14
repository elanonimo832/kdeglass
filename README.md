# Análisis · capa de escritorio «estilo macOS» para Linux

Carpeta de análisis del brief [`PROYECTO-KDE-MACOS.md`](PROYECTO-KDE-MACOS.md): un
escritorio Linux con el aspecto de macOS **nativo** (QStyle + efecto KWin + tokens), no
un tema.

## Contenido

| Fichero | Qué es |
|---|---|
| [`PROYECTO-KDE-MACOS.md`](PROYECTO-KDE-MACOS.md) | El brief original, tal cual (3551 bytes, `sha256:1f95c523…`). Sin modificar |
| [`ANALISIS.md`](ANALISIS.md) | El análisis: veredicto, correcciones técnicas, omisiones y plan reordenado |
| [`INSTALACION.md`](INSTALACION.md) | Cómo se instala y cómo se aplica: repo, destinos reales, etapas de despliegue y reversión |
| [`REFERENCIAS-DISENO.md`](REFERENCIAS-DISENO.md) | De dónde salen los números: kit oficial de Apple, valores provisionales y cómo medir capturas |
| [`INVENTARIO-FIGMA.md`](INVENTARIO-FIGMA.md) | Qué traen los exports de Figma, qué se extrajo y qué falta |
| [`HUELLAS-FALTANTES.md`](HUELLAS-FALTANTES.md) | Qué datos faltan, por qué no están en Figma y cómo conseguirlos |
| [`fuentes/`](fuentes/) | Respuestas crudas de las fuentes oficiales (HIG de Apple) que respaldan los tokens |
| [`tokens/`](tokens/) | Tokens de macOS extraídos, por eje |
| [`tokens.toml`](tokens.toml) | **El sistema de diseño consolidado** (5 ejes) |
| [`SALIDA.md`](SALIDA.md) | **Entrega del paso 2**: qué se genera, cómo se instala y qué se verificó |
| [`VERIFICACION-PANTALLA.md`](VERIFICACION-PANTALLA.md) | Medición de la captura real: lo aplicado coincide con lo generado |
| [`INCIDENTE.md`](INCIDENTE.md) | **Incidente de pantalla negra**: qué lo causó y cómo recuperarse |
| [`RECUPERAR-KDE.sh`](RECUPERAR-KDE.sh) | Script de recuperación, idempotente y reversible |
| `salida/` | Esquemas de color de KDE y CSS de GTK, generados |
| `instalar.sh` | Instalador idempotente y reversible (no escribe nada sin `--si`) |
| `instalar-decoracion.sh` | Instalador de la decoración de ventana ajustada |
| [`ANEXO-VERIFICACION.md`](ANEXO-VERIFICACION.md) | Qué supuesto del brief se comprobó, con qué evidencia y con qué confianza |
| `README.md` | Este índice |

## Resumen del análisis

**El plan es sólido.** Acierta en el diagnóstico (un tema repinta, no re-arquitectura),
descarta las soluciones equivocadas (temas, `LD_PRELOAD`, fork de Plasma) y el
entregable portable del paso 2 tiene valor por sí solo aunque el QStyle nunca se
termine.

**Cuatro supuestos operativos a corregir antes de escribir código:**

1. **El QStyle no se genera desde tokens.** Se generan colores, CSS, assets y el
   `Tokens.h`; el QStyle en C++ se escribe. Hay que separar generador e implementación.
2. **El QStyle no se activa solo.** El requisito era real, pero al verificar el sistema se
   resolvió **a mejor**: Plasma 6 selecciona el estilo con **una clave en `kdeglobals`**
   (`[KDE] widgetStyle`), y este equipo ya lo demuestra con Kvantum activo. No hace
   falta forzar el estilo por proceso. Ver [`INSTALACION.md`](INSTALACION.md) §1.
3. **`libdecor` no es la vía para GTK4.** Es una biblioteca del cliente, y GTK4 no la usa.
   El porcentaje irreducible de GTK4 es mayor del 10 % estimado.
4. **Redondear esquinas ≠ recortarlas.** Redondear es viable y está respaldado por
   precedentes (LightlyShaders); recortar elimina contenido dibujado en las esquinas.

**Dos omisiones que pesan más que cualquier decisión técnica:**

- **La tipografía.** El brief dedica todo el detalle al material y ninguno a la fuente,
  y sin métricas tipográficas equivalentes el resultado no parecerá macOS.
- **La medición.** No hay definición de «terminado» ni pruebas de regresión visual, que
  en un proyecto puramente estético son el único test con sentido.

**Cambios de orden propuestos:** un paso 0 de infraestructura y medición, el efecto KWin
de esquinas movido del paso 5 al 3 (es el mayor impacto visual por línea de código), y el
HDR explícitamente a v3.

> Detalle completo y tabla de las 12 acciones sobre el brief: [`ANALISIS.md`](ANALISIS.md).

# Roadmap

## El orden de trabajo del encargo original

```
1. Recoger los tokens de Golden Gate en un fichero   <- el primer paso
2. La capa declarativa portable                       <- 1 dia, valor inmediato
3. El generador: tokens -> QStyle + CSS GTK + KWin    <- 1-2 semanas
4. El QStyle completo                                 <- 1-3 meses
5. Efecto KWin (material + recorte de esquinas)       <- encima del 4
```

## Dónde estamos

| Paso del encargo | Estado |
|---|---|
| 1. Tokens | ✅ **hecho** — 859 tokens, con procedencia |
| 2. Capa declarativa portable | 🟡 **casi** — color, GTK y decoración; falta el tema global de Plasma |
| 3. Generador | ✅ **hecho** — reproducible byte a byte |
| 4. QStyle | ⬜ **no empezado** |
| 5. Efecto KWin | 🟡 **a medias** — carga y se engancha; **falta el shader** |

## Hitos

Cada hito tiene un **criterio de hecho** verificable. Un hito no está hecho porque
parezca que funciona: está hecho cuando una prueba lo demuestra y **falla** al romperlo.

---

### M1 — El efecto dibuja el material ⬅ **el siguiente**

El efecto carga y se engancha a la cadena de pintado, pero **no dibuja nada**.
Es lo único grande que falta del paso 5.

Se hará en pasos pequeños, cada uno medido con `efecto-kwin/probar-ya-instalado.sh`:

| Sub-paso | Qué dibuja | Criterio |
|---|---|---|
| M1.1 | Un color plano sobre la ventana | el efecto se ve, y `negro=0%` |
| M1.2 | Difusión del fondo (frost) | el fondo se difumina, medible por contraste |
| M1.3 | Refracción (70) | el borde desvía; medible con un patrón de rejilla |
| M1.4 | Dispersión (20) | el borde se separa en canales; medible en el color |
| M1.5 | Realce especular + borde oscurecido (alfa 20) | coincide con el kit |

**Hecho cuando:** los cinco sub-pasos pasan, el arnés sigue en verde, y hay capturas
en `evidencia/` que lo demuestran.

**Riesgo:** es la parte más delicada (OpenGL sobre el framebuffer de KWin). Un error
puede dejar la pantalla negra. Mitigación: `probar-ya-instalado.sh` descarga siempre,
`verificar-cadena.sh` aborta antes de instalar, y `RECUPERAR-KDE.sh reanimar` recupera
en caliente.

---

### M2 — Recorte de esquinas (squircle)

macOS no usa esquinas redondeadas: usa **squircle** (`cornerSmoothing = 0.6`, medido
en 2244 nodos del kit). KWin tiene `Effect::setShape` y la API de formas.

**Hecho cuando:** las ventanas se recortan con squircle y no con arco de círculo, con
la geometría del kit, y hay comparación visual en `evidencia/`.

---

### M3 — Tema global de Plasma

Falta la capa declarativa completa: `PlasmaStyle`, `LookAndFeel` y las
colecciones que enlazan todo para aplicarlo de una vez.

**Hecho cuando:** existe un paquete de tema global seleccionable en
*Ajustes → Apariencia global*, y aplicarlo no rompe nada.

---

### M4 — Tipografía

Los 80 tokens de tipografía están extraídos (tamaños, pesos, *tracking*), pero
**no aplicados**. Inter sustituye a SF Pro (SIL OFL: SF Pro no es redistribuible).

**Hecho cuando:** las métricas de texto de KDE usan la escala de macOS y hay
comparación de texto renderizado en `evidencia/`.

**Nota:** macOS **no tiene Dynamic Type** (verificado en la HIG). La escala es fija.

---

### M5 — Geometría de iconos

Faltan los radios de squircle de los iconos de carpeta. Hay valores de iOS en el kit,
pero los de macOS **no se han podido confirmar**.

**Hecho cuando:** los iconos de carpeta llevan el squircle correcto, o está
documentado que el valor no es verificable.

---

### M6 — QStyle completo

El paso más grande del encargo (1-3 meses). Un QStyle propio en C++ para que las
aplicaciones Qt nativas se dibujen como macOS, sin depender de Kvantum.

**Hecho cuando:** exista, esté instalado, y sea seleccionable sin romper aplicaciones.

**Nota:** es el único hito que **no** está encima de nada de lo hecho: es trabajo
independiente y grande. Los hitos M1-M5 dan valor sin él.

---

## Lo que falta por verificar (riesgos abiertos)

| Riesgo | Estado |
|---|---|
| El CSS de GTK en una aplicación real | **sin verificar** — es el mayor riesgo abierto de la capa declarativa |
| El esquema `KdeMacosLight` en uso | solo se ha probado el oscuro |
| La decoración con ventanas sin foco | los semáforos deben quedar grises (`#48484A`) |
| Los siete valores numéricos de macOS 27 | **nunca confirmados** independientemente: macOS 27 es pre-release y solo se midió el kit de la comunidad |

## Estado del sistema (2026-10-14)

| Pieza | Estado |
|---|---|
| Decoración `KdeMacOS` | ✅ activa — semáforos a la izquierda, 12 px, 8 px de separación |
| Efecto `macosglass2` | ✅ carga sin romper el render |
| Esquema de color | `BreezeDark` (se cambia a `KdeMacosDark` desde Ajustes) |
| Tokens | ✅ 859, con procedencia |
| Arnés de pruebas | ✅ 68 comprobaciones |

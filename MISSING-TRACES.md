# Huellas que faltan y cómo conseguirlas

> **ACTUALIZACIÓN: el hueco #1 y el #2 están CERRADOS.** Apple publica la tabla completa de
> «macOS built-in text styles» en las Human Interface Guidelines, con tamaños, interlineados,
> pesos y **tracking**. Está extraída en
> [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml) (80 tokens,
> fuente autorizada). Lo que sigue siendo cierto: **no estaba en Figma** y sigue sin estar;
> lo que cambia es que no hacía falta que estuviera.

Cierre del inventario. Qué está resuelto, qué no, **por qué no** y por dónde se puede
conseguir cada cosa que falta. Con la verificación de que el hueco no es un descuido.

- Inventario de lo recibido: [FIGMA-INVENTORY.md](FIGMA-INVENTORY.md)
- Referencias y método: [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md)

---

## 1. No es que no lo encuentres: no está en el export

La conclusión importante, verificada contra los propios ficheros:

> Buscar más en la colección de Variables de Figma no va a dar resultado, porque
> **lo que falta no son variables**. Son **propiedades de nodo**, y la exportación de
> Variables solo viaja con lo declarado como variable.

Comprobado en los datos:

| Comprobación | Resultado |
|---|---|
| Nombres de estilo en `Text Leading` | `Large Title, Title 1-3, Headline, Body, Callout, Subheadline, Footnote, Caption 1-2` → **nomenclatura de iOS**, no de macOS |
| Claves de tamaño en `Sizes` | Solo `Global/Font Size = 13`. **No hay** `Body 13` ni escala de estilos |
| `Sizes` — variantes | Mini, Small, Medium, Large, XL (5) |
| `Dynamic Type` — variantes | 12 escalas (xSmall→AX5) |
| `Text Leading` — variantes | Default, Loose, Tight (3) |

Es decir: el kit **sí tiene un sistema tipográfico completo**, pero es el de iOS. El de
macOS (el que usa la barra de menús, la barra lateral y los controles de escritorio) o
está en otra colección que no se exportó, o vive directamente en los estilos de texto del
documento — y esos **no salen en una exportación de Variables** en ningún caso.

Lo mismo vale para los radios de ventana, las sombras y los bordes capilares: son
propiedades de cada nodo.

---

## 2. Estado final: lo que hay

```
CONSEGUIDO (146 tokens de macOS, validados)     ->  tokens/
  tokens-colors.toml    63   color completo, claro y oscuro, con alfa exacto
  tokens-sizes.toml     65   metricas de todos los controles, por tamano
  tokens-kit.toml       18   material Liquid Glass + rellenos y bordes

REFERENCIA (483 tokens de otros sistemas)       ->  tokens/reference/
  Material 3, Salesforce, iOS, escalas genericas
```

Con esto ya se puede construir la mayor parte del tema:

| Capa del plan | ¿Se puede hacer ya? |
|---|---|
| Esquemas de color de KDE (claro y oscuro) | **Sí**, con los 63 colores medidos |
| Métricas de controles en el QStyle | **Sí**, con los 65 tokens de `Sizes` |
| Efecto KWin de material | **Sí**, con los 11 parámetros de Liquid Glass |
| CSS de GTK | **Sí**, para color |
| Radios de ventana | **No** — falta el dato |
| Escala tipográfica de macOS | **Sí** — 11 estilos, con interlineado, peso y tracking |
| Sombras y bordes capilares | **No** — faltan los efectos |

---

## 3. Lo que falta, una por una

| # | Falta | Por qué falta | Cómo se consigue |
|---|---|---|---|
| 1 | ~~**Escala tipográfica de macOS**~~ | **RESUELTO** con las HIG oficiales | [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml) |
| 2 | ~~**Tamaño de fuente por control**~~ | **RESUELTO**: la escala de macOS incluye los 11 estilos y el tracking | Igual que el anterior |
| 3 | **Radios de ventana, hoja y popover** | Son propiedades de nodo | Capturas de ventanas sobre fondo liso |
| 4 | **Sombras de ventana y de menú** | Son efectos de nodo | Capturas, midiendo el desvanecido |
| 5 | **Borde capilar de 1 px** (color y alfa) | Es un trazo de nodo | Capturas, perfil de intensidad |
| 6 | **Geometría del squircle de icono** | Es un trazado vectorial | Plantilla oficial de iconos, o medir un icono |
| 7 | **Espaciados de layout** | Viven en los nodos | Capturas, midiendo distancias |

Quedan **cinco** huecos, no siete: la tipografía se resolvió por la vía documental en lugar
de la de medición. Ninguno de los cinco restantes bloquea el arranque: los esquemas de color,
las métricas de control, el material y ahora también la tipografía se pueden construir **hoy**.

---

## 4. Cómo conseguir cada hueco

### Vía A · Capturas de pantalla (la más accesible)

**No hace falta un Mac.** Basta con capturas de macOS a **escala 1×**, y en este equipo
ya están las herramientas para medirlas (`magick`, PIL, numpy):

| Hueco | Cómo se mide de una captura |
|---|---|
| Radios de ventana (#3) | Por canal alfa: recuento de píxeles transparentes en la esquina, ajuste a un cuarto de círculo |
| Sombras (#4) | Perfil de intensidad desde el borde hacia fuera; ajuste de la caída |
| Borde capilar (#5) | Corte transversal: ancho y valor del pico |
| Espaciados (#7) | Detección de bordes y medida entre ellos |
| ~~Tipografía (#1, #2)~~ | **Ya no hace falta medirla**: está publicada en las HIG |

Si tienes acceso a un Mac —propio, de alguien, o incluso una máquina virtual— con la lista
de capturas de [DESIGN-REFERENCES.md](DESIGN-REFERENCES.md) §7 ya es suficiente.

### Vía B · El `.fig` completo

`File → Save local copy` en la **app de escritorio** (en el navegador no existe). Trae los
estilos de texto y las propiedades de nodo, que es exactamente lo que falta. El
decodificador está escrito y validado: [tools/figma/README.md](tools/figma/README.md).

### Vía C · Documentación y convención, para el punto 1

El tamaño base ya está medido: **13 pt** para el texto de control estándar. El resto de la
escala de macOS se puede tomar de la convención documentada (título de ventana 13
semibold, títulos grandes 22 y 26, texto pequeño 10-11) **marcando cada valor como no
medido**, para sustituirlo cuando haya capturas. Es aceptable porque la escala tipográfica
es la parte más tolerante: se corrige después sin tocar el QStyle.

---

## 5. Advertencia sobre inventar la tipografía

Hay un riesgo real en rellenar el hueco de tipografía «a ojo» y presentarlo como medido.

El tamaño base **sí** está medido: `Sizes/Global/Font Size = 13`. Pero el interlineado, el
espaciado entre letras y los tamaños de los niveles superiores **no lo están**. Si se
inventan y se dan por buenos, el resultado es un tema que parece correcto en una captura
y no lo es en uso real — y peor, nadie sabrá por qué.

**Regla para el `tokens.toml`:** cada token lleva su procedencia, y los no medidos van
marcados como `procedencia = "convencion"` en lugar de `"medido"` o `"export"`. Es la
misma disciplina que ya se aplica a los colores, y es lo que hace que el fichero sea
auditable dentro de seis meses.

---

## 6. Recomendación

**Empezar ya con lo que está medido**, que es bastante más de lo que parece:

```
PASO 2a · Esquemas de color de KDE (.colors), claro y oscuro
          salen de tokens-colors.toml, que esta completo y medido

PASO 2b · tokens.toml consolidado
          color (medido) + metricas (medido) + material (medido)
          + tipografia (solo el 13 medido, el resto marcado como convencion)

PASO 3  · Efecto KWin de material
          tiene los 11 parametros; es el mayor impacto visual por linea de codigo

PENDIENTE · radios de ventana y tipografia completa
          entran cuando haya capturas, sin bloquear nada de lo anterior
```

La clave es que **nada de lo que falta bloquea lo que ya se puede hacer**. Los huecos
afectan a la forma de la ventana y al texto; el color, las métricas de control y el
material están completos.

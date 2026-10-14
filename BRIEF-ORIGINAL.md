# Brief: capa de escritorio «estilo macOS» para Linux

> Punto de partida para un chat nuevo. Pega esto o apunta al fichero.

## El objetivo

Un escritorio Linux con el aspecto del **macOS actual**, pero **nativo** — no un
tema. La crítica de partida, que es correcta:

- Los temas (WhiteSur y compañía) **repintan, no re-arquitecturan**. No pueden
  cambiar la estructura de los controles, el layout, las animaciones ni el
  comportamiento de la ventana.
- Las apps **GTK** usan siempre lo suyo y desentonan.
- Y al cambiar de sistema **empiezas de cero**.

## La referencia de diseño: **macOS 27 «Golden Gate»**

No Tahoe (macOS 26), que fue el Liquid Glass inicial y **fue muy criticado**
(contraste, legibilidad, esquinas, incoherencia). Golden Gate es **la corrección
de Apple**, y sus correcciones son la lista de tokens:

```
MATERIAL ..... deslizador de translucidez para el usuario (claro/tintado/opaco)
               difusion del contenido complejo, no solo blur
               profundidad = BORDE OSCURECIDO + REFLEJOS ESPECULARES
VENTANAS ..... un radio de esquina UNICO para todas
               menos redondeadas que en Tahoe
               sombras retocadas, barra de titulo unificada
BARRAS LAT ... a ras, NO flotantes; iconos con color
ICONOS ....... esquircle obligatorio, mas capas de vidrio
EXTRA ........ la interfaz usa HDR para dar profundidad
```

## El enfoque acordado (no es un fork de Plasma)

```
1. TOKENS PRIMERO
   Un tokens.json con el sistema de diseno (radios, niveles de translucidez,
   la pareja borde/reflejo, colores de estado). De ahi se GENERAN los tres.

2. QSTYLE PROPIO (C++, plugin)
   Es lo que convierte un tema en "el sistema": metricas, dibujo y estados.
   API documentada, mucho volumen mecanico, acoplamiento bajo.
   -> la parte donde la IA convierte meses en semanas

3. KWIN: LA PARTE NATIVA
   - efecto propio: difusion + reflejo especular + borde oscurecido
   - recorte de esquinas: fuerza el radio en TODAS las apps, GTK incluidas
     (KWin puede recortar la ventana: se hace una vez, no por app)
   - animaciones y gestos: scripts, o fork de KWin solo si no llegan

4. GTK: LO ULTIMO, Y CON EXPECTATIVAS REALISTAS
   - tema CSS generado desde los mismos tokens
   - kde-gtk-config para que KDE se lo diga a GTK
   - libdecor (el mecanismo sancionado: la app cede el dibujo al compositor)
   - NO usar LD_PRELOAD: es deuda que se rompe sola
   - GTK4 empuja lo contrario por diseno: un ~10% no se podra
```

## Restricciones del entorno

```
Nada por AUR. Nada de sudo. Todo en ~/.local y ~/Documents.
Instalacion por script auditable, idempotente y reversible.
El sistema es CachyOS (Arch), KDE Plasma en Wayland.
```

## Portabilidad (la queja mas justa del usuario)

Todo **declarativo** en un repo: un instalador idempotente para que cambiar de
distro sea un comando, no una tarde. Esto vale **aunque nunca se escriba el
QStyle**, y sirve con cualquier tema.

## Orden de trabajo

```
1. Recoger los tokens de Golden Gate en un fichero   <- el primer paso
2. La capa declarativa portable                       <- 1 dia, valor inmediato
3. El generador: tokens -> QStyle + CSS GTK + KWin    <- 1-2 semanas
4. El QStyle completo                                 <- 1-3 meses
5. Efecto KWin (material + recorte de esquinas)       <- encima del 4
```

## Aviso legal, para cuando se publique

Uso personal: sin problema. Si se publica: presentarlo como «inspirado en»,
con aviso, y **sin usar iconos, nombres ni marcas de Apple**. Es lo que hacen
los proyectos que ya existen.

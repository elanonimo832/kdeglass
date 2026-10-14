# KWin effect: macOS-style material

Compositor effect that hooks the edge of windows into KWin's paint chain.
**It does not draw the material yet**: that is the next step.

## Status

| | |
|---|---|
| Loads without breaking rendering | ✅ verified with screenshots (`negro=0.0%`) |
| Hooks into the paint chain | ✅ |
| **Draws the material** | ❌ **pending: the shader** |

## The three commands

```bash
./build.sh              # compiles and verifies the paint chain
./install.sh        # installs and activates (asks for your password)
./test-installed.sh    # live test: loads, measures and UNLOADS on its own
```

`test-installed.sh` is the test bench: it **does not log you out**, it
reinstalls nothing, and it always unloads the effect with `trap EXIT` even if
rendering fails. It takes about 15 seconds.

For the effect to stay loaded **permanently**, log out.

> ⚠️ **NEVER `kwin_wayland --replace`.** On Wayland it starts a second compositor
> that competes for the DRM/GL, kills the OpenGL context of the live KWin and leaves
> the screen **black with the cursor visible**. It happened twice; see `../INCIDENT.md`.

## Recovery

If anything left the screen black:

```bash
bash ~/RECOVER-KDE.sh reanimar     # on the fly, without logging out
```

## The four things that must be respected

All four cost hours. `verify-chain.sh` and the test harness watch over them.

**1. The path.** KWin looks in `<plugins Qt>/kwin/effects/plugins/`, **not** in
`kwin/effects/`. One level higher and KWin does not see it, and **silently**.
*(Source: `PluginEffectLoader`, `m_pluginSubDirectory = "kwin/effects/plugins"`.)*

**2. The file name is the pluginId.** `macosglass.so` → id `macosglass`.
CMake's `lib` prefix breaks it (`PREFIX ""` avoids it).

**3. The paint chain.** `EffectsHandler::paintWindow()` calls **a single**
effect per invocation, and the chain advances because `Effect::paintWindow()` —the
base— re-enters. If an effect overrides it and **does not call the base**, the chain is
cut, `finalPaintWindow()` does not run and **no window is drawn**: the
Plasma desktop background is one more window, so all that is left is black.

Every path through `paintWindow()` has to end like this:

```cpp
effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
```

**4. `supported()`.** It has to genuinely return `true`. If it returns `false`, KWin
discards the effect **without any message**. (The version that used
`effects != nullptr`, the example from the KDE docs, returned `false`.)

## The `macosglass` identifier (why the plugin is called `macosglass2`)

The same code, byte for byte, **works with one id and breaks with another**:

| id | black on screen |
|---|---|
| `bisect` (minimal code) | 0 % ✅ |
| `testglass2` (minimal code) | 0 % ✅ |
| `macosglass` (full code) | **100 %** ❌ |
| `macosglass` (minimal code) | **100 %** ❌ |
| `macosglass2` (full code) | 0 % ✅ |

**I cannot explain why.** The observable state was identical (same metadata, same
`isSupported()`, same path). It is a reproducible observation, not a diagnosis.
Noted for the KWin team in `../INCIDENT.md`.

## Diagnostic tools

```bash
./verify-chain.sh    # is the paint chain intact? (source + binary)
```

They can be compiled by hand if needed (they use the already-installed KWin and KF6
headers; `_stub/vulkan` avoids the 42 MiB of `vulkan-headers`):

| File | What for |
|---|---|
| `src/diagnose.cpp` | reproduces KWin's plugin discovery |
| `src/probe-factory.cpp` | instantiates the factory and asks `isSupported()` |
| `src/verify-load.cpp` | does the same as KWin at startup |

These three answer «why does KWin not load my effect?» in seconds, which is what
would have saved me half the incident.

## The next step: the material shader

Parameters measured in `../tokens.toml` (from the Figma kit):

| Parameter | Value |
|---|---|
| refraction | 70 |
| dispersion | 20 |
| diffusion (frost) | 6 / 16 / 16 |
| light angle | 0 |
| opacity | 25 |
| depth | 30 |
| darkened edge | alpha 20 (black at 8 %) |

It will be drawn with OpenGL over `GLFramebuffer` in `paintWindow()`, in small steps,
each one measured with `test-installed.sh`.

# Project architecture

## What it is

A desktop layer with the look of **native macOS** on top of KDE Plasma 6
(Wayland). It is not a loose theme: the pieces complement each other, all derived
from **a single source of truth** (the tokens measured from Apple's Figma kit).

## Structure

```
.
├── BRIEF-ORIGINAL.md    Original brief. NOT modified.
├── README.md                Project entry point
│
├── docs/                    Process documentation
│   ├── ARCHITECTURE.md      this file
│   ├── METHODOLOGY.md       how we work and why
│   └── ROADMAP.md           what is missing, by milestone, with a "done" criterion
│
├── tokens.toml              CONSOLIDATED source of truth (5 axes)
├── tokens/                  32 collections extracted from the Figma kit
│   ├── tokens-colors.toml       color (primitives)
│   ├── tokens-sizes.toml        metrics
│   ├── tokens-tipografia_*.toml typography
│   ├── tokens-forma-*.toml      shape and effects
│   └── referencia/              13 NON-applicable collections (Material, iOS…)
│
├── tools/            Generators: tokens -> artifacts
│   ├── figma/               extraction from the kit (Node + Python)
│   ├── generate-kde-schemes.py
│   ├── generate-gtk-css.py
│   ├── generate-macos-decoration.py
│   └── consolidate-tokens.py
│
├── output/                  GENERATED artifacts (not edited by hand)
│   ├── color-schemes/       KdeMacosLight/Dark.colors
│   ├── gtk-3.0/ gtk-4.0/    CSS
│   └── aurorae/KdeMacOS/    decoration (traffic lights) + previews
│
├── effect-kwin/             Compositor effect (C++ / OpenGL)
│   ├── src/glass.h/.cpp     the effect
│   ├── src/diagnostico.cpp  diagnostic tools (see their README)
│   ├── _stub/vulkan/        stub to avoid installing 42 MiB of vulkan-headers
│   └── README.md
│
├── tests/                 Verification harness
│   ├── ejecutar.sh          entry point
│   ├── lib.sh               assertions
│   └── prueba-*.sh          per area: artifacts, effect, scripts, documentation
│
├── evidence/               Screenshots of OUR desktop (not Apple's)
└── INCIDENT.md             Black screen incident: story and cause
```

## The data flow

```
   Apple's Figma kit  (NOT versioned: it is Apple material)
              │
              │  tools/figma/       extraction
              ▼
      tokens/  +  tokens.toml              SOURCE OF TRUTH
              │
              │  tools/generar-*.py  generation
              ▼
   output/  (schemes, CSS, decoration)     ARTIFACTS
              │
              │  instalar*.sh               installation
              ▼
        ~/.local/share/...                 SYSTEM
```

**Rule:** the artifacts in `output/` **are not edited by hand**. You change the
token and regenerate. A test checks that regenerating produces an **identical** file.

## Why the tokens are the source of truth

The brief demanded fidelity to macOS. Fidelity is not achieved by copying values by
hand scattered across files: it is achieved by having **one** place from which all of
them come.

Each token carries its **provenance** (which collection of the kit it came from), so
any value can be traced back to its origin. And when a value is corrected, it is
corrected in one place and flows down to every artifact.

## Documented decisions

| Decision | Why |
|---|---|
| Three shape radii (control, window, icon), not one | macOS distinguishes them; the kit provides them separately |
| **Kit** values win over those measured on screen | macOS renders 18/255 dimmer; using the kit keeps the pieces consistent |
| Typography: Inter instead of SF Pro | SF Pro is not redistributable; Inter is SIL OFL |
| Text is black/white with **decreasing alpha**, not grays | It is Apple's veil pattern (85/55/25/10/5/3 %) |
| `_stub/vulkan` instead of `vulkan-headers` | Only the headers are needed to compile; saves 42 MiB |

## What is NOT there

- **The effect's material shader** (diffusion, refraction, dispersion). It is the
  only big thing missing; see `docs/ROADMAP.md`.
- Verification of the GTK CSS in a real application.
- Squircle geometry for the folder icons.

# Archived tests

Tests for designs that have been superseded. They are kept, not deleted, because
each one pins something that was learned the hard way and that a future design
could break again.

## `test-shader.sh` — M1.1, the flat colour patch

M1.1 drew a 48x48 cyan patch with `glScissor` + `glClear` into the window's
framebuffer. M1.2 replaced that mechanism entirely: the effect now derives from
`OffscreenEffect` and blurs the window's own texture with a shader, so there is no
scissor rectangle and no marker colour left to assert.

The lesson it protected is recorded in `docs/ROADMAP.md` under M1.1:

  - `frameGeometry().y()` is already measured from the top of the screen, so
    flipping Y for `glScissor` inverts the vertical movement
  - a screenshot diff is blind to DIRECTION: it counted changed pixels correctly
    and could not see that the patch was anchored wrongly
  - `mapToDeviceCoordinates()` is an identity on a single output at 0,0, scale 1

If a future step returns to raw GL drawing, restore that test from git history:

    git show f7b968c:tests/test-shader.sh

## The M1.1-era live instruments — retired 2026-10-14

Four live instruments were retired here TOGETHER, and the reason is the same in each case:
they could no longer say anything, and a script that cannot say anything is worse than no
script, because it teaches whoever runs it to ignore verdicts.

- **`test-installed.sh`** (with `measure-marker.py`) — looked for the flat 48x48 marker that
  M1.1 drew. M1.2 replaced the marker with the material band, so its verdict was
  meaningless, and the handoff said so for two days while the file stayed in the live
  directory.
- **`test-hot.sh`** and **`calibrate.sh`** — both waited for `CALIB` lines that the effect
  stopped emitting when M1.1's coordinate calibration was replaced by reading KWin's own
  geometry through a scripting plugin (which is what `test-titlebar.sh` does now).
- **`test-diffusion.sh`** (with `measure-diffusion.py`) — measured M1.2's claim, that the
  BAND's local contrast drops with brightness preserved. Since M1.3a the frost lives on the
  captured backdrop and the kernel over the window texture produces the band's tone, so the
  claim it measured is not the claim the design makes. `test-glass.sh` (band follows the
  background) and `measure-titlebar.py` (title bar blurred, client sharp) measure what is
  true now.

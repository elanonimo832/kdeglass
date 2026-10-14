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

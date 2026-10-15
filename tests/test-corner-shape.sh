# M2 (a) -- the SHAPE instrument.
#
# HANDOFF.md section 10c: M2 was built once the wrong way, and the two numbers that were pinned
# (a 4.6229 px bulge and a 0.04 deg gradient) were both true about a curve of the wrong FAMILY.
# The user's eye found it before the arithmetic did. This file guards the instrument that is
# supposed to find it in PIXELS instead: a synthetic corner whose answer is known by construction,
# and a self-test that must DESCRIBE a flat corner rather than fail on it -- the three ways the
# first attempt died are in 10c, and each one has a case here.

EF="$PROJECT/effect-kwin"
INSTRUMENT="$EF/measure-corner.py"

echo "  -- the shape instrument measures pixels, not formulas --"
afirmar_existe "measure-corner.py exists (the shape instrument)" "$INSTRUMENT"
# INDEPENDENCE IS THE POINT: an instrument that calls the model's own curve cannot catch that model
# drifting. It has to carry its own boundary functions and its own arithmetic.
negar "it does not import the model it is meant to check" \
  grep -qE '(^|[^A-Za-z_])import[[:space:]]+simulate|from[[:space:]]+simulate' "$INSTRUMENT"

if timeout 300 python3 "$INSTRUMENT" --self-test >/tmp/corner-selftest.txt 2>&1; then
  ok "the shape instrument's self-test passes ($(grep -c . /tmp/corner-selftest.txt) lines of evidence)"
else
  fallo "the shape instrument's self-test FAILED:"; sed 's/^/      /' /tmp/corner-selftest.txt | head -8
fi

# EVERY failure mode needs a named case, or the self-test can pass while checking nothing. That is
# exactly the M2 mistake: two anchors were pinned, both true by construction, and the SHAPE was not
# checked at all. A case that stops running must be a failure, not a smaller number of passes.
for name_ in circle flat spike frame image_png refuse_empty; do
  afirmar "the self-test exercises '$name_' and it passes" \
    grep -qE "^case=$name_( |$).*verdict=ok" /tmp/corner-selftest.txt
done

# THE FLAT CORNER IS THE ONE THE FIRST ATTEMPT COULD NOT DESCRIBE: a naive row scan that looks for
# the first window pixel reports the same x for every row and cannot tell a flat corner from a
# broken frame. The wrong superellipse of 10c is such a corner. Measured in pixels it must read as
# a long flat run, and the circle must not. Two assertions each, because a missing field greps
# empty, awk reads it as 0, and a single comparison then passes without measuring anything.
circle_flat=$(grep -oE '^case=circle .*flat_run=-?[0-9.]+' /tmp/corner-selftest.txt | grep -oE 'flat_run=-?[0-9.]+' | sed 's/.*=//')
spike_flat=$(grep -oE '^case=spike .*flat_run=-?[0-9.]+' /tmp/corner-selftest.txt | grep -oE 'flat_run=-?[0-9.]+' | sed 's/.*=//')
afirmar "the circle's flat run is measured (the field exists)" grep -qE '^[0-9.]+$' <<< "$circle_flat"
afirmar "and the circle is NOT flat: ${circle_flat:-no data} rows" \
  awk -v v="$circle_flat" 'BEGIN{exit !(v+0 < 3)}'
afirmar "the wrong curve's flat run is measured (the field exists)" grep -qE '^[0-9.]+$' <<< "$spike_flat"
afirmar "and it IS flat: ${spike_flat:-no data} rows" \
  awk -v v="$spike_flat" 'BEGIN{exit !(v+0 > 10)}'

# THE KNOWN VALUES ARE PRINTED as pixel measurements, so a reader can check the instrument against
# closed-form arithmetic instead of trusting it. At y=5 a 20 px circular arc has its boundary at
# x=6.77 in the corner's own frame -- the number 10c's table puts there.
afirmar "the circle's boundary at y=5 is the closed form (6.77)" \
  grep -qE '^case=circle .*x_at_y_5=6\.7[0-9]' /tmp/corner-selftest.txt
# and the wrong curve is reported at x=20.00, the value the user saw as "esquinas arruinadas".
afirmar "the wrong curve's boundary at y=5 is 20.00 (the near-square corner)" \
  grep -qE '^case=spike .*x_at_y_5=20\.0[0-9]' /tmp/corner-selftest.txt

# The KWin effect: invariants that MUST NOT break.
# These are the tests that prevent the black screen from coming back.

EF="$PROY/effect-kwin"
SOURCE="$EF/src/glass.cpp"
SO_BUILD="$EF/build/plugins/kwin/effects/macosglass2.so"
SO_SYSTEM=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

echo "  -- the paint chain (cause of the black screen) --"
# The effect derives from OffscreenEffect, which continues the chain itself:
# its drawWindow() calls effects->drawWindow() when the window is not redirected
# and OffscreenData::paint() when it is. Both paths verified in KWin 6.7's
# src/effect/offscreeneffect.cpp. See tests/test-diffusion.sh for the assertion.
afirmar_existe "src/glass.cpp exists" "$SOURCE"
afirmar_contiene "includes glass.moc (required for the plugin)" "$SOURCE" 'include "glass[.]moc"'
afirmar_codigo "derives from OffscreenEffect" "$EF/src/glass.h" 'public[[:space:]]+OffscreenEffect'

echo "  -- the compiled plugin --"
if [ -f "$SO_BUILD" ]; then
  # The chain is not continued by OUR code any more: OffscreenEffect does it.
  # So the check is that the base class is really linked in, which is what proves
  # the chain will be reached. Searching for EffectsHandler::paintWindow in our
  # own binary was right for M1.1 and is wrong now.
  # No `nm ... | grep -q`: under `set -o pipefail` the early exit of grep -q kills
  # nm with SIGPIPE and the pipeline fails on a match. See tests/test-harness.sh.
  grep -q 'OffscreenEffect' <<< "$(nm -D --undefined-only "$SO_BUILD" 2>/dev/null)" \
    && ok "the compiled .so links OffscreenEffect (which continues the chain)" \
    || fallo "the compiled .so does NOT link OffscreenEffect"
  grep -q 'qt_plugin_instance' <<< "$(nm -D "$SO_BUILD" 2>/dev/null)" \
    && ok "the .so exports qt_plugin_instance" || fallo "qt_plugin_instance is missing"
  grep -q 'KWin/Effect' <<< "$(strings "$SO_BUILD" 2>/dev/null)" \
    && ok "the metadata declares KWin/Effect" || fallo "KPackageStructure KWin/Effect is missing"
else
  fallo "the .so is not compiled (run: ./build.sh)"
fi

echo "  -- the installed plugin --"
if [ -f "$SO_SYSTEM" ]; then
    # The chain is continued by OffscreenEffect, so what proves the
    # installed plugin is safe is that it links it. Searching for our own
    # paintWindow call was the M1.1 criterion and is wrong now.
    nm -D --undefined-only "$SO_SYSTEM" 2>/dev/null | grep -c 'OffscreenEffect' >/dev/null \
      && ok "the installed .so links OffscreenEffect (chain safe)" \
      || fallo "the INSTALLED .so does not link OffscreenEffect"
else
  fallo "macosglass2.so is not installed"
fi

echo "  -- the right path (kwin/effects/plugins, NOT kwin/effects) --"
# KWin::PluginEffectLoader looks in kwin/effects/plugins. Installing one level up
# means KWin never sees it, SILENTLY. This was one of the incident's failures.
afirmar_contiene "the installer uses the /plugins path" "$EF/install.sh" 'kwin/effects/plugins'
negar "no .so left in kwin/effects/ (wrong path)" \
  test -f /usr/lib/qt6/plugins/kwin/effects/macosglass2.so

echo "  -- the identifier --"
# KWin derives the plugin id from the FILE NAME. If it does not match the kwinrc
# key, KWin never finds it. And with the id 'macosglass' the render broke.
afirmar_contiene "the installer installs macosglass2" "$EF/install.sh" 'macosglass2'
negar "the .so with the id that broke the render is gone" \
  test -f /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so

echo "  -- diagnostic scripts --"
for s in "$EF/install.sh" "$EF/build.sh" \
         "$PROY/install.sh" "$PROY/install-decoration.sh" \
         "$PROY/RECOVER-KDE.sh"; do
  [ -f "$s" ] && { bash -n "$s" 2>/dev/null && ok "$(basename "$s"): bash syntax OK" || fallo "$(basename "$s"): BAD bash syntax"; }
done

echo "  -- the chain verifier checks the right thing --"
# It used to look for OUR call to effects->paintWindow(). That was right for M1.1
# and became WRONG in M1.2, where OffscreenEffect continues the chain and our
# binary merely links it. It then printed "chain broken" for a correct effect and
# BLOCKED THE INSTALL. The dangerous thing is not a missing call, it is an
# override that forgets one, so that is what it must check.
afirmar_contiene "the verifier looks for overrides" "$EF/verify-chain.sh" 'does not override'
afirmar_contiene "the verifier checks the base class" "$EF/verify-chain.sh" 'OffscreenEffect'
afirmar_contiene "the verifier checks the base is linked" "$EF/verify-chain.sh" 'undefined-only'
# The installed plugin must NOT set the failure flag: install.sh checks before
# copying, so a stale installed build would block the install that replaces it.
# That circularity blocked a real install, twice.
# What matters is not whether the script MENTIONS a stale installed plugin -- it
# should, as a NOTE -- but whether that mention sets the failure flag. Setting it
# is circular: install.sh checks before copying, so a stale installed build would
# block the install that replaces it. That blocked a real install, twice.
if grep -q 'fallo=1' <<< "$(grep -A2 'NOTE: the installed plugin is an older build' "$EF/verify-chain.sh" 2>/dev/null)"; then
  fallo "a stale installed plugin sets the failure flag (circular, blocks install)"
else
  ok "a stale installed plugin does not set the failure flag"
fi

echo "  -- no script EXECUTES kwin_wayland --replace --"
# It leaves the screen black: on Wayland it starts a second compositor that fights
# for the DRM/GL and kills the live KWin's OpenGL context. We only look at COMMAND
# lines: mentioning it in a comment to warn against it is correct and desirable.
malos=0
for s in "$EF"/*.sh "$PROY"/*.sh; do
  [ -f "$s" ] || continue
  # Only counts when the command is EXECUTED: at line start or after a shell
  # separator. Inside an echo (warning against it) it does not count.
  if grep -qE '(^|[;&|]|\$\(|^[[:space:]]*)[[:space:]]*kwin_wayland[[:space:]]+--replace' \
       <<< "$(grep -vE '^[[:space:]]*#' "$s" 2>/dev/null)"; then
    malos=$((malos+1)); printf '      -> %s\n' "$(basename "$s")"
    grep -nE '(^|[;&|]|\$\(|^[[:space:]]*)[[:space:]]*kwin_wayland[[:space:]]+--replace' "$s" | sed 's/^/         /'
  fi
done
afirmar_igual "no script executes --replace" "0" "$malos"

echo "  -- no pipeline may use 'grep -q' under pipefail --"
# THIS FAILURE HAPPENED THREE TIMES. grep -q exits as soon as it matches and
# closes the pipe; the producer then dies of SIGPIPE, and with `set -o pipefail`
# the pipeline returns that failure even though grep succeeded. The check passes
# or fails depending on timing and data size: it passed here and failed on the
# user's machine, on the same binary. Verifying a fix with such a check is
# impossible, which is how it survived three rounds.
#
# The --diagnose block reproduces the broken form ON PURPOSE, to show the
# contrast, so it is the one allowed place.
malos=$(python3 - "$EF" <<'PYEOF'
import glob, os, re, sys
ef = sys.argv[1]
bad = []
for path in sorted(glob.glob(os.path.join(ef, '*.sh'))):
    text = open(path, encoding='utf-8').read()
    # cut the --diagnose block out: it exists to demonstrate the broken pattern
    end = text.find('  exit 0\nfi', text.find('--diagnose'))
    if end > 0:
        text = text[:text.find('--diagnose')] + text[end + len('  exit 0\nfi'):]
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith('#'):
            continue
        if re.search(r'\|[^|]*grep[^|]*-q', line):
            bad.append(f"{os.path.basename(path)}:{n}: {line.strip()}")
for b in bad:
    print(f"      -> {b}")
print(len(bad))
PYEOF
)
n="${malos##*$'\n'}"
afirmar_igual "no 'grep -q' in a pipeline outside --diagnose" "0" "$n"

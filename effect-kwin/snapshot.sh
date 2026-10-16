#!/usr/bin/env bash
# A photo of a fixed scene WITH the identity of what drew it, in one command.
#
#   ./snapshot.sh                 -> evidence/<when>-<commit>-<md5>.png, plus a .txt beside it
#   ./snapshot.sh --identity      -> print the identity only; touches no screen
#   ./snapshot.sh --self-test     -> check the refusal and the naming with fake plugins; no screen
#
# WHY THIS EXISTS. A whole evening went into bisecting a visual regression -- "the text behind the
# bar is vertical lines instead of frosted" -- by rebuilding and relogging commit by commit, because
# nothing tied a SCREENSHOT to the BUILD that produced it. The user said it plainly: "es una tristeza
# ver como perdimos ese progreso por no tener bien documentado un set de imagenes con cada avance y
# si algo malo pasa poder ver una imagen saber que build fue y volver". This is that set of images.
#
# THE SCENE MUST BE THE SAME EVERY TIME, or two photos cannot be compared. The script cannot know
# what is on your screen, so it records what it can -- the active window's geometry, straight from
# KWin -- and expects the same window in the same place over the same backdrop each time.
#
# IT REFUSES WHEN THE BUILD AND THE INSTALLED PLUGIN DIFFER. The photo would then be of a library
# the source does not describe, and the whole point is to be able to return to the SOURCE that drew
# it. Note WHICH one is recorded: the INSTALLED md5, because that is what actually runs.
#
# THE IDENTITY GOES IN THE FILENAME, so an image can be placed without opening anything:
#   evidence/20261015-1841-5d87f31-a8d8e549.png
#   evidence/20261015-1841-5d87f31-a8d8e549.txt   <- commit, tree, both md5s, geometry, live values
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The self-test re-enters this script with fake plugins; `$0` can be a bare relative name (the
# first version used it and the recursion died with "command not found"), so the path is absolute.
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
ID=macosglass2
BUILD_SO="${DSH_SNAPSHOT_BUILD:-$HERE/build/plugins/kwin/effects/macosglass2.so}"
INSTALLED_SO="${DSH_SNAPSHOT_INSTALLED:-/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so}"
EVIDENCE="${DSH_SNAPSHOT_EVIDENCE:-$HERE/../evidence}"
CAPTURE="${DSH_SNAPSHOT_CAPTURE:-spectacle -b -n -o}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

md5_of() { # md5_of <file> -> the sum, or "missing"
    [ -f "$1" ] && md5sum "$1" | cut -d' ' -f1 || echo missing
}

commit_of() { git -C "$HERE/.." rev-parse --short HEAD 2>/dev/null || echo unknown; }

dirty_of() { # a photo of a dirty tree cannot be returned to by commit alone, so it is recorded
    if [ -n "$(git -C "$HERE/.." status --porcelain 2>/dev/null)" ]; then echo dirty; else echo clean; fi
}

valores() { # the live settings, read-only: tune.sh --show is the one place that formats them
    "$HERE/tune.sh" --show 2>/dev/null | sed -n '/what the effect last reported/,$p'
}

geometria() { # best effort: the active window, from KWin's own scripting, not the stale journal
    local js=/tmp/glass-snapshot-geom.js g
    cat > "$js" <<'JS'
const wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
let best = null;
for (const w of wins) { if (w.normalWindow && w.active) best = w; }
if (best) print(`SG|${best.frameGeometry.x},${best.frameGeometry.y},${best.frameGeometry.width},${best.frameGeometry.height},${best.clientGeometry.y - best.frameGeometry.y}`);
JS
    timeout 20 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" >/dev/null 2>&1
    timeout 10 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
    sleep 1
    g=$(timeout 15 journalctl --user --since '15 sec ago' -o cat 2>/dev/null | grep '^SG|' | grep -v systemd-run | tail -1 | cut -d'|' -f2)
    [ -n "$g" ] && printf 'x,y,w,h,bar = %s\n' "$g" || printf 'unknown (KWin did not report an active window)\n'
}

identidad() {
    printf 'when:      %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
    printf 'commit:    %s (%s)\n' "$(commit_of)" "$(dirty_of)"
    printf 'build:     %s\n' "$(md5_of "$BUILD_SO")"
    printf 'installed: %s   <- what actually runs, and what the filename carries\n' "$(md5_of "$INSTALLED_SO")"
    printf 'geometry:  %s\n' "$(geometria)"
    printf 'values:\n'
    valores
}

# THE SAME TREE, BOTH LIBRARIES, OR NO PHOTO. Checked BEFORE the capture, so a refusal costs nothing
# and leaves no image behind that would later be read as evidence of a build it does not describe.
mismo_so() {
    local b i
    b=$(md5_of "$BUILD_SO"); i=$(md5_of "$INSTALLED_SO")
    [ "$b" != "missing" ] && [ "$i" != "missing" ] && [ "$b" = "$i" ]
}

nombre_base() { # <when>-<commit>-<installed md5, 8>
    printf '%s-%s-%s' "$(date '+%Y%m%d-%H%M%S')" "$(commit_of)" "$(md5_of "$INSTALLED_SO" | cut -c1-8)"
}

if [ "${1:-}" = "--identity" ]; then
    identidad
    exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
    TMP=$(mktemp -d) || exit 1
    trap 'rm -rf "$TMP"' EXIT
    printf 'AAA' > "$TMP/a.so"; printf 'AAA' > "$TMP/same.so"; printf 'BBB' > "$TMP/diff.so"
    printf 'fake' > "$TMP/shot.png"
    fail=0
    # (1) DIFFERENT md5s: it must refuse, say why, and write nothing.
    out=$(DSH_SNAPSHOT_BUILD="$TMP/a.so" DSH_SNAPSHOT_INSTALLED="$TMP/diff.so" \
          DSH_SNAPSHOT_EVIDENCE="$TMP/ev" DSH_SNAPSHOT_CAPTURE="cp $TMP/shot.png" \
          "$SELF" 2>&1); rc=$?
    if [ "$rc" = "0" ]; then echo "FAIL: mismatched plugins were accepted"; fail=1
    elif ! grep -qi 'refus\|no coincide\|differ' <<< "$out"; then
        echo "FAIL: refused without saying why: $out"; fail=1
    elif [ -e "$TMP/ev" ]; then echo "FAIL: a refused run left something behind"; fail=1
    else echo "  a mismatched plugin is refused, with a reason, and writes nothing"; fi
    # (2) SAME md5s: it must write the pair, and the name must carry the commit and the md5.
    DSH_SNAPSHOT_BUILD="$TMP/same.so" DSH_SNAPSHOT_INSTALLED="$TMP/same.so" \
    DSH_SNAPSHOT_EVIDENCE="$TMP/ev" DSH_SNAPSHOT_CAPTURE="cp $TMP/shot.png" \
        "$SELF" >/dev/null 2>&1 || { echo "FAIL: a matching pair was not accepted"; fail=1; }
    png=$(ls "$TMP/ev"/*.png 2>/dev/null | head -1)
    txt=$(ls "$TMP/ev"/*.txt 2>/dev/null | head -1)
    if [ -z "$png" ] || [ -z "$txt" ]; then echo "FAIL: no image and sidecar were written"; fail=1
    else
        echo "  a matching pair writes $(basename "$png") + .txt"
        grep -q "$(md5_of "$TMP/same.so" | cut -c1-8)" <<< "$png" \
            && echo "  the filename carries the INSTALLED md5" \
            || { echo "FAIL: the filename does not carry the md5: $png"; fail=1; }
        grep -q "$(commit_of)" <<< "$png" \
            && echo "  the filename carries the commit" \
            || { echo "FAIL: the filename does not carry the commit: $png"; fail=1; }
        grep -q 'installed:' "$txt" && echo "  the sidecar records what actually runs" \
            || { echo "FAIL: the sidecar does not record the installed library"; fail=1; }
    fi
    [ "$fail" = "0" ] && echo "self-test: ok" || echo "self-test: FAILED"
    exit "$fail"
fi

# ---------------------------------------------------------------------------------------------
if ! mismo_so; then
    cat >&2 <<EOF
refused: the built plugin and the INSTALLED one differ, so a photo now would be of a library the
source does not describe -- and the point of the photo is to be able to return to the source.

  build:     $(md5_of "$BUILD_SO")
  installed: $(md5_of "$INSTALLED_SO")

Run ./install.sh and log back in (the hot reload does not re-read the .so), then try again.
EOF
    exit 1
fi

mkdir -p "$EVIDENCE"
base="$EVIDENCE/$(nombre_base)"
tmp="$base.png.part"
if ! timeout 30 $CAPTURE "$tmp" >/dev/null 2>&1 || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "refused: the capture failed (spectacle could not write the image)" >&2
    exit 1
fi
mv "$tmp" "$base.png"
identidad > "$base.txt"
echo "wrote $base.png"
echo "      $base.txt"

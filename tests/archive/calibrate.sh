#!/usr/bin/env bash
# Coordinate calibration for M1.1. Read-only with respect to KWin: it only reads
# the journal and asks the user to move a window.
#
# Why: the patch moves opposite to its window, so the coordinate mapping is wrong.
# Guessing which KWin method returns global coordinates has failed twice
# (frameGeometry documented ambiguously; the blur pattern did not transfer). This
# reads the actual values and derives the mapping from two known positions.
set -uo pipefail
SAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/calib"; mkdir -p "$SAL"

echo "==============================================================="
echo "  CALIBRATION: move ONE window to two known places"
echo "==============================================================="
echo
echo "The effect logs every patch it draws, with the geometry KWin reports."
echo "I need the SAME window at two different positions, so I can see which"
echo "number changes and in which direction."
echo
read -r -p "  1. Move 'Konsole' to the TOP-LEFT of the screen, then press Enter... " _

# marca de tiempo para separar las fases
T1=$(date '+%Y-%m-%d %H:%M:%S')
sleep 1
read -r -p "  2. Now move it to the BOTTOM-RIGHT, then press Enter... " _
T2=$(date '+%Y-%m-%d %H:%M:%S')
sleep 1

echo
echo "  Reading the journal between the two marks..."
timeout 20 journalctl --user --since "$T1" --until "$T2" -o cat 2>/dev/null \
  | grep 'CALIB' | grep -v systemd-run | tail -4 | sed 's/^/    TOP-LEFT  /'
timeout 20 journalctl --user --since "$T2" -o cat 2>/dev/null \
  | grep 'CALIB' | grep -v systemd-run | tail -4 | sed 's/^/    BOTTOM-RIGHT  /'

echo
echo "  Full log saved to $SAL/calibration.txt"
{
  echo "### TOP-LEFT (since $T1 until $T2)"
  timeout 20 journalctl --user --since "$T1" --until "$T2" -o cat 2>/dev/null | grep CALIB | grep -v systemd-run
  echo "### BOTTOM-RIGHT (since $T2)"
  timeout 20 journalctl --user --since "$T2" -o cat 2>/dev/null | grep CALIB | grep -v systemd-run
} > "$SAL/calibration.txt" 2>/dev/null
echo
echo "  Done. Send me the output above (or the file)."

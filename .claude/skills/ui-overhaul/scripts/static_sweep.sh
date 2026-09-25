#!/usr/bin/env bash
# Phase 1 static sweep, as a script, so a re-audit measures the same thing the
# baseline did. Run from the repo root (Git Bash / Linux):
#   bash .claude/skills/ui-overhaul/scripts/static_sweep.sh [ROOT]
# ROOT defaults to the current directory; point it at an exported old tree
# (`git archive <rev> | tar -x -C <dir>`) to measure a baseline.
# Counts are matching LINES over apps/app/lib + packages/design_system/lib,
# comment lines excluded. "outside theme" excludes
# packages/design_system/lib/src/theme/, where literal values belong.
set -euo pipefail
cd "${1:-.}"
D=(apps/app/lib packages/design_system/lib)

matches() { # matches <regex> [x = exclude theme] — file:line:text, no comments
  local out
  out=$(grep -rnE --include='*.dart' "$1" "${D[@]}" || true)
  out=$(printf '%s\n' "$out" | grep -vE '^[^:]+:[0-9]+:\s*//' || true)
  if [ "${2:-}" = x ]; then out=$(printf '%s\n' "$out" | grep -v 'src/theme/' || true); fi
  printf '%s\n' "$out" | grep . || true
}
count() { matches "$@" | grep -c . || true; }
worst() { # top 3 files outside the theme
  matches "$1" x | cut -d: -f1 | sort | uniq -c | sort -nr | head -3 |
    awk '{n=split($2,p,"/"); printf "%s:%s ", p[n], $1}'
}
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3"; }

COLORS='Colors\.[a-z]'
HEX='Color\(0x'
ALPHA_RAW='withValues\(alpha: [0-9.]|withOpacity\('
WEIGHT='FontWeight\.'
SIZE='fontSize:'
TRACK='letterSpacing:'
COPY='(textTheme\.[a-zA-Z]+|style)[!?]?\.copyWith\('
INSETS='EdgeInsets\.[a-zA-Z]*\([^)]*[1-9]'
BOX='SizedBox\((height|width): [0-9]'
RADIUS='(BorderRadius|Radius)\.circular\([0-9]'
DUR='Duration\(milliseconds'
TAB='tabularFigures|kTabularFigures|\.tabular\b|appText\.(stat|statLarge|quantity|clock|clockSmall|kicker|kickerLarge)\b'

echo '| Signal | Count | Worst files |'
echo '| --- | --- | --- |'
row 'Colors.* (outside theme; `transparent` included)' "$(count "$COLORS" x)" "$(worst "$COLORS")"
row 'Color(0x… (outside theme)' "$(count "$HEX" x)" "$(worst "$HEX")"
row 'Raw numeric alpha (outside theme)' "$(count "$ALPHA_RAW" x)" "$(worst "$ALPHA_RAW")"
row 'FontWeight.* (outside theme)' "$(count "$WEIGHT" x)" "$(worst "$WEIGHT")"
row 'fontSize: (outside theme)' "$(count "$SIZE" x)" "$(worst "$SIZE")"
row 'letterSpacing: (outside theme)' "$(count "$TRACK" x)" "$(worst "$TRACK")"
row 'Text-style copyWith (outside theme)' "$(count "$COPY" x)" "$(worst "$COPY")"
row 'Tabular-figure sites' "$(count "$TAB" x)" ''
row 'ThemeExtension classes' "$(count 'extends ThemeExtension')" ''
row 'AppSpacing uses' "$(count 'AppSpacing\.')" ''
row 'Raw non-zero EdgeInsets number (outside theme)' "$(count "$INSETS" x)" "$(worst "$INSETS")"
row 'Raw SizedBox number (outside theme)' "$(count "$BOX" x)" "$(worst "$BOX")"
row 'Raw (Border)Radius.circular(n) (outside theme)' "$(count "$RADIUS" x)" "$(worst "$RADIUS")"
row 'AppRadii uses' "$(count 'AppRadii\.')" ''
row 'Duration(milliseconds (outside theme)' "$(count "$DUR" x)" "$(worst "$DUR")"
row 'Curves.* (outside theme)' "$(count 'Curves\.' x)" ''
row 'AppMotion uses' "$(count 'AppMotion\.')" ''
row 'Reduced-motion reads (disableAnimationsOf / AppMotion.of / animateScroll)' "$(count 'disableAnimationsOf|AppMotion\.(of|animateScroll)\(')" ''
row 'BoxShadow(' "$(count 'BoxShadow\(')" ''
row 'IconButton( (outside theme)' "$(count 'IconButton(\.[a-zA-Z]+)?\(' x)" ''
row 'Semantics(' "$(count '\bSemantics\(')" ''
THEME=packages/design_system/lib/src/theme
row 'Button themes in ThemeData' "$(cat "$THEME"/*.dart | grep -cE '(filled|outlined|text|elevated|icon|segmented)ButtonTheme:' || true)" ''
row 'Component themes in ThemeData' "$(cat "$THEME"/*.dart | grep -cE '^\s+[a-zA-Z]+Theme: ' || true)" ''

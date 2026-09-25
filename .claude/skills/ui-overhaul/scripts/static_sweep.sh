#!/usr/bin/env bash
# Phase 1 static sweep, as a script, so a re-audit measures the same thing the
# baseline did. Run from the repo root (Git Bash / Linux):
#   bash .claude/skills/ui-overhaul/scripts/static_sweep.sh
# Counts are matching LINES over apps/app/lib + packages/design_system/lib.
# "outside theme" excludes packages/design_system/lib/src/theme/, where literal
# values are supposed to live.
set -euo pipefail
D=(apps/app/lib packages/design_system/lib)

count() { # count <regex> [exclude-theme]
  local out
  out=$(grep -rnE --include='*.dart' "$1" "${D[@]}" || true)
  if [ "${2:-}" = x ]; then out=$(printf '%s\n' "$out" | grep -v 'src/theme/' || true); fi
  printf '%s\n' "$out" | grep -c . || true
}
worst() { # worst <regex> — top 3 files outside the theme
  grep -rcE --include='*.dart' "$1" "${D[@]}" 2>/dev/null | grep -v 'src/theme/' |
    grep -v ':0$' | sort -t: -k2 -nr | head -3 | sed 's|.*/||' | tr '\n' ' '
}
row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3"; }

echo '| Signal | Count | Worst files |'
echo '| --- | --- | --- |'
row 'Colors. (outside theme)' "$(count 'Colors\.[a-z]' x)" "$(worst 'Colors\.[a-z]')"
row 'Color(0x (outside theme)' "$(count 'Color\(0x' x)" "$(worst 'Color\(0x')"
row 'withValues(alpha / withOpacity (outside theme)' "$(count 'withOpacity|withValues\(alpha' x)" "$(worst 'withOpacity|withValues\(alpha')"
row 'FontWeight. (outside theme)' "$(count 'FontWeight\.' x)" "$(worst 'FontWeight\.')"
row 'fontSize: (outside theme)' "$(count 'fontSize:' x)" "$(worst 'fontSize:')"
row 'letterSpacing: (outside theme)' "$(count 'letterSpacing:' x)" "$(worst 'letterSpacing:')"
row 'Text-style copyWith' "$(count '(textTheme\.[a-zA-Z]+|style)[!?]?\.copyWith\(' x)" "$(worst '(textTheme\.[a-zA-Z]+|style)[!?]?\.copyWith\(')"
row 'tabularFigures' "$(count 'tabularFigures')" ''
row 'ThemeExtension' "$(count 'extends ThemeExtension')" ''
row 'AppSpacing uses' "$(count 'AppSpacing\.')" ''
row 'Raw EdgeInsets number (outside theme)' "$(count 'EdgeInsets\.[a-zA-Z]*\([^)]*[0-9]' x)" "$(worst 'EdgeInsets\.[a-zA-Z]*\([^)]*[0-9]')"
row 'Raw SizedBox number' "$(count 'SizedBox\((height|width): [0-9]' x)" "$(worst 'SizedBox\((height|width): [0-9]')"
row 'Raw BorderRadius/Radius.circular(n) (outside theme)' "$(count '(BorderRadius|Radius)\.circular\([0-9]' x)" "$(worst '(BorderRadius|Radius)\.circular\([0-9]')"
row 'AppRadii uses' "$(count 'AppRadii\.')" ''
row 'Duration(milliseconds (outside theme)' "$(count 'Duration\(milliseconds' x)" "$(worst 'Duration\(milliseconds')"
row 'Curves. (outside theme)' "$(count 'Curves\.' x)" ''
row 'AppMotion uses' "$(count 'AppMotion\.')" ''
row 'disableAnimationsOf / AppMotion.of' "$(count 'disableAnimationsOf|AppMotion\.of\(')" ''
row 'BoxShadow(' "$(count 'BoxShadow\(')" ''
row 'IconButton(' "$(count 'IconButton(\.[a-zA-Z]+)?\(')" ''
row 'Semantics(' "$(count '\bSemantics\(')" ''
row 'Button themes in ThemeData' "$(grep -chE '(filled|outlined|text|elevated|icon|segmented)ButtonTheme:' packages/design_system/lib/src/theme/*.dart | awk '{s+=$1} END {print s}')" ''
row 'Component themes in ThemeData' "$(grep -chE '^\s+[a-zA-Z]+Theme: ' packages/design_system/lib/src/theme/*.dart | awk '{s+=$1} END {print s}')" ''

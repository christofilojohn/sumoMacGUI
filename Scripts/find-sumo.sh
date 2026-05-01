#!/usr/bin/env bash
# Locate the `sumo` binary across known macOS install layouts.
# Prints the absolute path on stdout; exits 1 if not found.
set -euo pipefail

candidates=(
  "/Library/Frameworks/EclipseSUMO.framework/Versions/Current/EclipseSUMO/bin/sumo"
  "/opt/homebrew/bin/sumo"
  "/usr/local/bin/sumo"
)

if cmd=$(command -v sumo 2>/dev/null); then
  echo "$cmd"
  exit 0
fi

for c in "${candidates[@]}"; do
  if [[ -x "$c" ]]; then
    echo "$c"
    exit 0
  fi
done

echo "sumo not found. Install from https://eclipse.dev/sumo/ or 'brew tap dlr-ts/sumo && brew install --cask sumo-gui'." >&2
exit 1

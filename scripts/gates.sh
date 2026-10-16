#!/bin/zsh
# The checks every change must pass. They must not leave anything behind in the working tree.
#
#   scripts/gates.sh

set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

before="$(git status --short 2>/dev/null || true)"

swift format lint --strict --recursive Package.swift Sources Tests
swift build --build-tests -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
zsh -n Resources/allow-lid-closed.sh scripts/*.sh

after="$(git status --short 2>/dev/null || true)"
if [[ "$before" != "$after" ]]; then
  echo "The gates changed the working tree:" >&2
  diff <(echo "$before") <(echo "$after") >&2 || true
  exit 1
fi
echo "Gates passed."

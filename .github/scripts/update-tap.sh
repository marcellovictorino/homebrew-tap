#!/bin/bash
# Update, build-check, commit and push each opted-in formula on its own, so a
# formula whose release lookup or build fails does not hold back the others.
# A failed formula is put back as it was and named; the run then exits non-zero.
#
# Run from the tap's root, on main, with a git identity set. Needs what
# update-formulas.sh and check-formulas.sh need.
# Usage: update-tap.sh [Formula/x.rb ...] (default: every formula)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -gt 0 ] || set -- Formula/*.rb

# A failed formula is restored from the last commit and a good one is committed
# whole, so an edit already in the working copy would be lost or published.
if [ -n "$(git status --porcelain -- "$@")" ]; then
  echo "error: uncommitted changes to the formulas; commit or set them aside first:" >&2
  git status --short -- "$@" >&2
  exit 1
fi

failed=()
for f in "$@"; do
  name=$(basename "$f" .rb)
  if ! "$here/update-formulas.sh" "$f"; then
    git checkout -- "$f"
    echo "::error::$name: release lookup failed; formula left unchanged"
    failed+=("$name"); continue
  fi
  git diff --quiet -- "$f" && continue
  if ! "$here/check-formulas.sh" "$f"; then
    git checkout -- "$f"
    echo "::error::$name: updated formula failed its build check; formula left unchanged"
    failed+=("$name"); continue
  fi
  git commit -m "chore($name): update to the latest release" -- "$f"
  git push origin HEAD:main
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "error: not updated: ${failed[*]}" >&2
  exit 1
fi

#!/bin/bash
# Audit, build from source and test formulas as they are in this working copy.
#
# `brew tap` clones only committed files, so the formulas are copied into a
# scratch tap; that way the formula checked is the one on disk, including an
# uncommitted edit from the updater. Usage: check-formulas.sh [Formula/x.rb ...]
# (default: every formula). A formula whose checksum is still the all-zero
# placeholder (release not yet tagged) is audited but not installed or tested.
set -euo pipefail

zeros=0000000000000000000000000000000000000000000000000000000000000000
tap=local/formula-check
[ $# -gt 0 ] || set -- Formula/*.rb
files=("$@")

for f in "${files[@]}"; do [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }; done

brew tap-new --no-git "$tap" >/dev/null
dir=$(brew --repo "$tap")
installed=()
cleanup() {
  [ ${#installed[@]} -eq 0 ] || brew uninstall --force "${installed[@]}" >/dev/null 2>&1 || true
  brew untap "$tap" >/dev/null 2>&1 || true
}
trap cleanup EXIT
mkdir -p "$dir/Formula"
cp "${files[@]}" "$dir/Formula/"
# Homebrew 7 refuses to load an untrusted tap, even a local one.
if brew trust --help >/dev/null 2>&1; then brew trust "$tap" >/dev/null; fi

for f in "${files[@]}"; do
  name=$tap/$(basename "$f" .rb)
  echo "== audit $name"
  brew audit --strict "$name"
  if grep -q "sha256 \"$zeros\"" "$f"; then
    echo "== skip install and test of $name: checksum is the pending placeholder (release not tagged yet)"
    continue
  fi
  echo "== install $name"
  installed+=("$(basename "$f" .rb)")
  brew install --build-from-source "$name"
  echo "== test $name"
  brew test "$name"
done

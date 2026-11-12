#!/bin/bash
# Bring each opted-in formula up to its project's latest GitHub release.
#
# A formula opts in with a first-lines comment: "# updater: OWNER/REPO".
# It must use a ".../archive/refs/tags/vX.Y.Z.tar.gz" url and a sha256 line.
# A "COMMIT = "..."" line, when present, is set to the tag's commit.
# An optional "# template: PATH" comment next to it names a formula file in the
# project's own repository: its content at the release tag (everything but the
# updater and template comments, url, sha256 and COMMIT, which stay the tap's own)
# replaces the tap's copy, so the install and test steps have one source. The
# copy is also repaired when the tap is already on the latest release.
# A "revision N" line is removed: a new release starts again at no revision.
# Only moves forward. Edits the files in place and commits nothing; exits
# non-zero on the first formula whose release cannot be read.
# Needs gh (GH_TOKEN set) and curl.
# Usage: update-formulas.sh [Formula/x.rb ...] (default: every formula)
set -euo pipefail

[ $# -gt 0 ] || set -- Formula/*.rb
err=$(mktemp)
trap 'rm -f "$err"' EXIT

for formula in "$@"; do
  repo=$(sed -n 's/^# updater: \([A-Za-z0-9_.-]*\/[A-Za-z0-9_.-]*\)$/\1/p' "$formula" | head -n1)
  [ -n "$repo" ] || { echo "skip $formula: no updater marker"; continue; }

  # Only "release not found" means no release; any other failure (auth, rate
  # limit, network) must fail the run rather than look like "nothing to do".
  if ! tag=$(gh release view --repo "$repo" --json tagName --jq .tagName 2>"$err"); then
    grep -qi 'release not found' "$err" || { echo "error: cannot read releases of $repo: $(cat "$err")" >&2; exit 1; }
    tag=
  fi
  [ -n "$tag" ] || { echo "skip $formula: $repo has no release"; continue; }
  case $tag in v[0-9]*) ;; *) echo "skip $formula: unexpected tag $tag"; continue ;; esac
  latest=${tag#v}

  current=$(sed -n 's|^ *url ".*/archive/refs/tags/v\(.*\)\.tar\.gz"$|\1|p' "$formula" | head -n1)
  [ -n "$current" ] || { echo "skip $formula: no tag archive url"; continue; }

  revision=
  template=$(sed -n 's/^# template: \([A-Za-z0-9_.\/-]*\)$/\1/p' "$formula" | head -n1)

  if [ "$latest" = "$current" ]; then
    [ -n "$template" ] || { echo "ok   $formula: already $current"; continue; }
  elif [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]; then
    echo "skip $formula: release $latest is older than $current"; continue
  fi

  if [ "$latest" = "$current" ]; then
    # Same release: keep the checksum and commit the formula already has.
    sum=$(sed -n 's|^ *sha256 "\([0-9a-f]\{64\}\)".*|\1|p' "$formula" | head -n1)
    commit=$(sed -n 's|^ *COMMIT = "\([0-9a-f]\{40\}\)".*|\1|p' "$formula" | head -n1)
  else
    archive="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
    sum=$(curl -fsSL "$archive" | shasum -a 256 | cut -d' ' -f1)
    commit=$(gh api "repos/$repo/commits/$tag" --jq .sha)
    [[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "error: bad checksum for $archive" >&2; exit 1; }
    [[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "error: bad commit for $tag" >&2; exit 1; }
  fi

  if [ -n "$template" ]; then
    body=$(mktemp)
    revision=$(grep -E '^ *revision [0-9]+$' "$formula" | head -n1 || true)
    if ! gh api "repos/$repo/contents/$template?ref=$tag" -H "Accept: application/vnd.github.raw" >"$body" 2>"$err" \
       || ! grep -q '^class ' "$body" || ! grep -q '^ *url "' "$body"; then
      echo "error: cannot read a formula template $template of $repo at $tag: $(cat "$err")" >&2
      rm -f "$body"; exit 1
    fi
    { grep -E '^# (updater|template): ' "$formula"; grep -Ev '^# (updater|template): ' "$body"; } > "$formula.new"
    mv "$formula.new" "$formula"; rm -f "$body"
    # A comment on the template's checksum line says it is a placeholder; the tap's line is real.
    sed -i.bak 's|^\( *sha256 "[0-9a-f]\{64\}"\) *#.*|\1|' "$formula"; rm -f "$formula.bak"
  fi

  sed -i.bak \
    -e "s|^\( *url \".*/archive/refs/tags/\)v.*\.tar\.gz\"|\1$tag.tar.gz\"|" \
    -e "s|^\( *sha256 \)\"[0-9a-f]\{64\}\"|\1\"$sum\"|" \
    -e "s|^\( *COMMIT = \)\"[0-9a-f]\{40\}\"|\1\"$commit\"|" \
    "$formula"
  rm -f "$formula.bak"
  if [ "$latest" = "$current" ] && [ -n "${revision:-}" ]; then
    # The tap's revision belongs to this release, not to the template: put it back after the checksum.
    sed -i.bak "/^ *sha256 /a\\
$revision
" "$formula"; rm -f "$formula.bak"
  fi
  if [ "$latest" != "$current" ]; then sed -i.bak '/^ *revision [0-9][0-9]*$/d' "$formula"; rm -f "$formula.bak"; fi
  if [ "$latest" = "$current" ]; then echo "sync $formula: template $template at $tag"; continue; fi
  echo "bump $formula: $current -> $latest ($commit)"
done

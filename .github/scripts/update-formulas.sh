#!/bin/bash
# Bring each opted-in formula up to its project's latest GitHub release.
#
# A formula opts in with a first-lines comment: "# updater: OWNER/REPO".
# It must use a ".../archive/refs/tags/vX.Y.Z.tar.gz" url and a sha256 line.
# A "COMMIT = "..."" line, when present, is set to the tag's commit.
# Only moves forward; also fills a placeholder (all-zero) checksum.
# Needs gh (GH_TOKEN set) and curl. Usage: update-formulas.sh [formula-dir]
set -euo pipefail

dir=${1:-Formula}
zeros=0000000000000000000000000000000000000000000000000000000000000000
changed=0

for formula in "$dir"/*.rb; do
  repo=$(sed -n 's/^# updater: \([A-Za-z0-9_.-]*\/[A-Za-z0-9_.-]*\)$/\1/p' "$formula" | head -n1)
  [ -n "$repo" ] || { echo "skip $formula: no updater marker"; continue; }

  tag=$(gh release view --repo "$repo" --json tagName --jq .tagName 2>/dev/null || true)
  [ -n "$tag" ] || { echo "skip $formula: $repo has no release"; continue; }
  case $tag in v[0-9]*) ;; *) echo "skip $formula: unexpected tag $tag"; continue ;; esac
  latest=${tag#v}

  current=$(sed -n 's|^ *url ".*/archive/refs/tags/v\(.*\)\.tar\.gz"$|\1|p' "$formula" | head -n1)
  [ -n "$current" ] || { echo "skip $formula: no tag archive url"; continue; }
  placeholder=0
  grep -q "sha256 \"$zeros\"" "$formula" && placeholder=1

  if [ "$latest" = "$current" ] && [ $placeholder -eq 0 ]; then
    echo "ok   $formula: already $current"; continue
  fi
  if [ "$latest" != "$current" ] && \
     [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]; then
    echo "skip $formula: release $latest is older than $current"; continue
  fi

  archive="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
  sum=$(curl -fsSL "$archive" | shasum -a 256 | cut -d' ' -f1)
  commit=$(gh api "repos/$repo/commits/$tag" --jq .sha)
  [[ $sum =~ ^[0-9a-f]{64}$ && $sum != "$zeros" ]] || { echo "error: bad checksum for $archive" >&2; exit 1; }
  [[ $commit =~ ^[0-9a-f]{40}$ ]] || { echo "error: bad commit for $tag" >&2; exit 1; }

  sed -i.bak \
    -e "s|^\( *url \".*/archive/refs/tags/\)v.*\.tar\.gz\"|\1$tag.tar.gz\"|" \
    -e "s|^\( *sha256 \)\"[0-9a-f]\{64\}\"|\1\"$sum\"|" \
    -e "s|^\( *COMMIT = \)\"[0-9a-f]\{40\}\"|\1\"$commit\"|" \
    "$formula"
  rm -f "$formula.bak"
  echo "bump $formula: $current -> $latest ($commit)"
  changed=1
done

echo "changed=$changed"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "changed=$changed" >> "$GITHUB_OUTPUT"; fi

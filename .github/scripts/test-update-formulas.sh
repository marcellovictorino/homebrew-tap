#!/bin/bash
# Exercises update-formulas.sh against stubbed gh and curl (no network).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/Formula"

cat > "$work/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "release view --repo o/new "*)   echo v0.6.0 ;;
  "release view --repo o/same "*)  echo v0.5.0 ;;
  "release view --repo o/older "*) echo v0.4.0 ;;
  "release view --repo o/none "*)  echo "release not found" >&2; exit 1 ;;
  "release view --repo o/broken "*) echo "HTTP 401: Bad credentials" >&2; exit 1 ;;
  "api repos/o/new/commits/v0.6.0 "*)  echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  "api repos/o/same/commits/v0.5.0 "*) echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
STUB
printf '#!/bin/bash\nprintf "archive bytes for %%s" "${@: -1}"\n' > "$work/bin/curl"
chmod +x "$work/bin/gh" "$work/bin/curl"

zeros=$(printf '0%.0s' {1..64}); old=$(printf '1%.0s' {1..64}); zc=$(printf '0%.0s' {1..40})
mk() { # name repo version sha
  cat > "$work/Formula/$1.rb" <<RB
# updater: $2
class X < Formula
  url "https://github.com/$2/archive/refs/tags/v$3.tar.gz"
  sha256 "$4"
  COMMIT = "$zc".freeze
end
RB
}
mk new o/new 0.5.0 "$old"
mk same o/same 0.5.0 "$old"
mk placeholder o/same 0.5.0 "$zeros"
mk older o/older 0.5.0 "$old"
mk none o/none 0.5.0 "$old"
cat > "$work/Formula/manual.rb" <<RB
class Manual < Formula
  url "https://github.com/o/new/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$old"
end
RB
cp -R "$work/Formula" "$work/before"

out=$(PATH="$work/bin:$PATH" "$here/update-formulas.sh" "$work/Formula")
echo "$out"

fail() { echo "FAIL: $*" >&2; exit 1; }
want=$(printf 'archive bytes for https://github.com/o/new/archive/refs/tags/v0.6.0.tar.gz' | shasum -a 256 | cut -d' ' -f1)
grep -q "tags/v0.6.0.tar.gz" "$work/Formula/new.rb" || fail "new: url not bumped"
grep -q "sha256 \"$want\"" "$work/Formula/new.rb" || fail "new: checksum not recomputed"
grep -q 'COMMIT = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$work/Formula/new.rb" || fail "new: commit not stamped"
grep -q "sha256 \"$zeros\"" "$work/Formula/placeholder.rb" && fail "placeholder: checksum not filled"
grep -q 'COMMIT = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$work/Formula/placeholder.rb" || fail "placeholder: commit not filled"
for f in same older none manual; do
  cmp -s "$work/Formula/$f.rb" "$work/before/$f.rb" || fail "$f: changed but should not"
done
echo "$out" | grep -q '^changed=1$' || fail "changed output"
# A failed lookup must fail the run, not read as "no release".
mkdir "$work/broken"; mk() { :; }
printf '# updater: o/broken\nurl "https://github.com/o/broken/archive/refs/tags/v0.1.0.tar.gz"\nsha256 "%s"\n' "$old" > "$work/broken/b.rb"
if PATH="$work/bin:$PATH" "$here/update-formulas.sh" "$work/broken" >/dev/null 2>&1; then fail "broken lookup treated as success"; fi
echo "PASS"

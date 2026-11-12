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
  "release view --repo o/tpl "*)   echo v0.6.0 ;;
  "release view --repo o/tplsame "*) echo v0.5.0 ;;
  "release view --repo o/tplgone "*) echo v0.6.0 ;;
  "api repos/o/tpl/commits/v0.6.0 "*) echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  "api repos/o/tplgone/commits/v0.6.0 "*) echo cccccccccccccccccccccccccccccccccccccccc ;;
  "api repos/o/tpl/contents/Formula/x.rb?ref=v0.6.0 "*) cat "$TPL" ;;
  "api repos/o/tplsame/contents/Formula/x.rb?ref=v0.5.0 "*) cat "$TPL" ;;
  "api repos/o/tplgone/contents/Formula/x.rb?ref=v0.6.0 "*) echo "HTTP 404: Not Found" >&2; exit 1 ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
STUB
printf '#!/bin/bash\nprintf "archive bytes for %%s" "${@: -1}"\n' > "$work/bin/curl"
chmod +x "$work/bin/gh" "$work/bin/curl"

old=$(printf '1%.0s' {1..64}); zc=$(printf '0%.0s' {1..40})
mk() { # name repo version sha
  cat > "$work/Formula/$1.rb" <<RB
# updater: $2
class X < Formula
  url "https://github.com/$2/archive/refs/tags/v$3.tar.gz"
  sha256 "$4"
  revision 1
  COMMIT = "$zc".freeze
end
RB
}
mk new o/new 0.5.0 "$old"
mk same o/same 0.5.0 "$old"
mk older o/older 0.5.0 "$old"
mk none o/none 0.5.0 "$old"
cat > "$work/Formula/manual.rb" <<RB
class Manual < Formula
  url "https://github.com/o/new/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$old"
end
RB
# A formula that names a template in its project takes its body from there.
cat > "$work/template.rb" <<RB
class X < Formula
  url "https://github.com/o/tpl/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "$(printf '0%.0s' {1..64})" # placeholder from the template
  COMMIT = "$zc".freeze
  def install; system "new-install"; end
end
RB
export TPL="$work/template.rb"
mkt() { # name repo version
  cat > "$work/Formula/$1.rb" <<RB
# updater: $2
# template: Formula/x.rb
class X < Formula
  url "https://github.com/$2/archive/refs/tags/v$3.tar.gz"
  sha256 "$old"
  revision 1
  COMMIT = "$zc".freeze
  def install; system "old-install"; end
end
RB
}
mkt tpl o/tpl 0.5.0
mkt tplsame o/tplsame 0.5.0
mkt tplgone o/tplgone 0.5.0
cp "$work/Formula/tplgone.rb" "$work/tplgone.before"; mv "$work/Formula/tplgone.rb" "$work/tplgone.rb"
cp -R "$work/Formula" "$work/before"

out=$(PATH="$work/bin:$PATH" "$here/update-formulas.sh" "$work"/Formula/*.rb)
echo "$out"

fail() { echo "FAIL: $*" >&2; exit 1; }
want=$(printf 'archive bytes for https://github.com/o/new/archive/refs/tags/v0.6.0.tar.gz' | shasum -a 256 | cut -d' ' -f1)
grep -q "tags/v0.6.0.tar.gz" "$work/Formula/new.rb" || fail "new: url not bumped"
grep -q "sha256 \"$want\"" "$work/Formula/new.rb" || fail "new: checksum not recomputed"
grep -q 'COMMIT = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$work/Formula/new.rb" || fail "new: commit not stamped"
# A revision marks a formula change on the same release; a new release resets it.
! grep -q 'revision' "$work/Formula/new.rb" || fail "new: revision not removed on a new release"
for f in same older none manual; do
  cmp -s "$work/Formula/$f.rb" "$work/before/$f.rb" || fail "$f: changed but should not"
done
# A failed lookup must fail the run, not read as "no release".
mkdir "$work/broken"; mk() { :; }
printf '# updater: o/broken\nurl "https://github.com/o/broken/archive/refs/tags/v0.1.0.tar.gz"\nsha256 "%s"\n' "$old" > "$work/broken/b.rb"
if PATH="$work/bin:$PATH" "$here/update-formulas.sh" "$work/broken/b.rb" >/dev/null 2>&1; then fail "broken lookup treated as success"; fi

# New release: template body, the tap's own url, checksum and commit, markers kept, revision reset.
f="$work/Formula/tpl.rb"
grep -q 'new-install' "$f" && ! grep -q 'old-install' "$f" || fail "tpl: body not taken from the template"
[ "$(head -n2 "$f")" = "$(printf '# updater: o/tpl\n# template: Formula/x.rb')" ] || fail "tpl: markers lost"
grep -q 'tags/v0.6.0.tar.gz' "$f" || fail "tpl: url not bumped"
grep -q "sha256 \"$(printf 'archive bytes for https://github.com/o/tpl/archive/refs/tags/v0.6.0.tar.gz' | shasum -a 256 | cut -d' ' -f1)\"" "$f" || fail "tpl: checksum not the tap's"
grep -q 'COMMIT = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$f" || fail "tpl: commit not stamped"
! grep -q 'placeholder from the template' "$f" || fail "tpl: the template's placeholder comment leaked"
! grep -q revision "$f" || fail "tpl: revision kept on a new release"
# Same release: body repaired, checksum kept, revision kept.
f="$work/Formula/tplsame.rb"
grep -q 'new-install' "$f" || fail "tplsame: drift not repaired"
grep -q "sha256 \"$old\"" "$f" || fail "tplsame: checksum changed on the same release"
grep -q 'tags/v0.5.0.tar.gz' "$f" || fail "tplsame: url changed"
grep -q 'revision 1' "$f" || fail "tplsame: revision dropped on the same release"
# A template that cannot be read fails the run and leaves the formula as it was.
cp "$work/tplgone.before" "$work/Formula/tplgone.rb"
if PATH="$work/bin:$PATH" "$here/update-formulas.sh" "$work/Formula/tplgone.rb" >/dev/null 2>&1; then fail "unreadable template treated as success"; fi
cmp -s "$work/Formula/tplgone.rb" "$work/tplgone.before" || fail "tplgone: changed despite the failure"
echo "PASS"

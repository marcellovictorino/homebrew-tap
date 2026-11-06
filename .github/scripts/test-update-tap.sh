#!/bin/bash
# Exercises update-tap.sh and check-formulas.sh against stubbed gh, curl and
# brew (no network, no Homebrew changes), in a scratch git repository whose
# origin is a local bare repository.
#
# Why: one formula whose release lookup or build failed used to hold back
# every formula's update, and a formula added before its release was tagged
# passed CI on a placeholder checksum and then could not install.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/tap"

cat > "$work/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "release view --repo o/a "*) echo v0.6.0 ;;
  "release view --repo o/b "*) echo v2.0.0 ;;
  "release view --repo o/badbuild "*) echo v0.6.0 ;;
  "release view --repo o/same "*) echo v0.5.0 ;;
  "release view --repo o/broken "*) echo "HTTP 401: Bad credentials" >&2; exit 1 ;;
  "api repos/o/a/commits/v0.6.0 "*) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  "api repos/o/b/commits/v2.0.0 "*) echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
  "api repos/o/badbuild/commits/v0.6.0 "*) echo cccccccccccccccccccccccccccccccccccccccc ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
STUB
printf '#!/bin/bash\nprintf "archive bytes for %%s" "${@: -1}"\n' > "$work/bin/curl"
# brew: nothing installed; every step succeeds except installing "badbuild".
cat > "$work/bin/brew" <<STUB
#!/bin/bash
echo "brew \$*" >> "$work/brew.log"
case "\$1" in
  --repo) echo "$work/scratch-tap" ;;
  trust) exit 1 ;;
  install) case "\$*" in */badbuild) echo "build failed" >&2; exit 1 ;; esac ;;
esac
exit 0
STUB
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"

old=$(printf '1%.0s' {1..64}); zc=$(printf '0%.0s' {1..40})
cd "$work/tap"
git init -q -b main
git config user.name test; git config user.email test@example.invalid
mkdir Formula
mk() { # name repo version
  printf '# updater: %s\nclass X < Formula\n  url "https://github.com/%s/archive/refs/tags/v%s.tar.gz"\n  sha256 "%s"\n  COMMIT = "%s".freeze\nend\n' \
    "$2" "$2" "$3" "$old" "$zc" > "Formula/$1.rb"
}
mk a o/a 0.5.0
mk b o/b 1.0.0
mk badbuild o/badbuild 0.5.0
mk broken o/broken 0.5.0
mk same o/same 0.5.0
git add -A; git commit -qm start
git init -q --bare "$work/origin.git"
git remote add origin "$work/origin.git"
git push -q origin main
cp -R Formula "$work/before"

fail() { echo "FAIL: $*" >&2; exit 1; }
if out=$("$here/update-tap.sh" 2>&1); then fail "run with failed formulas exited 0"; fi
echo "$out"

# Each updated formula is its own commit, touching only its own file, pushed.
log=$(git --git-dir="$work/origin.git" log --format='%s' main)
[ "$(echo "$log" | head -n2)" = "$(printf 'chore(b): update to the latest release\nchore(a): update to the latest release')" ] \
  || fail "pushed commits: $log"
for n in a b; do
  files=$(git --git-dir="$work/origin.git" log --format= --name-only --grep="^chore($n):" main)
  [ "$files" = "Formula/$n.rb" ] || fail "$n commit touched: $files"
done
grep -q 'tags/v0.6.0.tar.gz' Formula/a.rb || fail "a: not bumped"
grep -q 'tags/v2.0.0.tar.gz' Formula/b.rb || fail "b: not bumped"
# Failed formulas are left as they were, uncommitted, and named.
for n in badbuild broken same; do
  cmp -s "Formula/$n.rb" "$work/before/$n.rb" || fail "$n: changed but should not"
done
[ -z "$(git status --porcelain)" ] || fail "working copy not clean: $(git status --porcelain)"
echo "$out" | grep -q '^error: not updated: badbuild broken$' || fail "failures not named"

# A formula for a release not yet tagged (all-zero checksum) fails the check
# before Homebrew is touched.
: > "$work/brew.log"
sed -i.bak "s/$old/$(printf '0%.0s' {1..64})/" Formula/same.rb
if out=$("$here/check-formulas.sh" Formula/same.rb 2>&1); then fail "placeholder formula passed the check"; fi
echo "$out" | grep -q 'tag the project.s release first' || fail "placeholder message: $out"
[ ! -s "$work/brew.log" ] || fail "brew touched for a placeholder: $(cat "$work/brew.log")"
echo "PASS"

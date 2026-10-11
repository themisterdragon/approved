#!/bin/bash
# Publish build/web to GitHub Pages (main page and /beta/), keeping the last
# few builds' files so old links and cached pages still work.
# usage: tools/publish_web.sh PAGES_CHECKOUT   (a clone of the gh-pages branch)
set -e
cd "$(dirname "$0")/.."
SRC=$PWD/build/web
P=$1
[ -d "$P/.git" ] || { echo "usage: tools/publish_web.sh PAGES_CHECKOUT"; exit 1; }
# the same private word list as the commit check (.git/info/banned-words);
# short words turn up by chance in binary files, so only longer ones here.
# Godot's own engine files (.wasm, its loader .js and audio worklets) are
# skipped: they're the official templates, with Godot's language and
# contributor lists in them; everything of ours (the .pck and pages) is scanned.
WORDS=$(git rev-parse --git-dir)/info/banned-words
if [ -f "$WORDS" ]; then
  hits=$(grep -v '^#' "$WORDS" | sed 's/\\b//g' | awk 'length($0) > 3' | grep -l -a -F -f - $(ls "$SRC"/* | grep -v -E '\.wasm$|game-[0-9a-f]+(\.audio.*)?\.js$') || true)
  [ -z "$hits" ] || { echo "refusing to publish, private words in: $hits"; exit 1; }
fi
for dir in "$P" "$P/beta"; do
  mkdir -p "$dir"
  cp "$SRC"/* "$dir"/
  # keep the newest 3 builds' game-* files
  ls -t "$dir"/game-*.html 2>/dev/null | tail -n +4 | while read old; do rm -f "${old%.html}".*; done
done
cd "$P"
git add -A
git -c user.name=themisterdragon -c user.email=274141300+themisterdragon@users.noreply.github.com commit -q -m "Web build $(cat "$SRC/latest.txt")"
git push -q https://github.com/themisterdragon/approved.git gh-pages
echo "published build $(cat "$SRC/latest.txt")"

#!/bin/bash
# Export the web build to build/web and add the online bridge (web/net.js)
#. The game files are named after
# the build (game-<commit>.*) with a small index.html that opens them, so a
# browser can never mix an old cached game with a new page.
# Publish with tools/publish_web.sh.
set -e
cd "$(dirname "$0")/.."
B=$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . ':!data/build.txt' || echo "+")
echo "$B $(date -u +%Y-%m-%d)" > data/build.txt
rm -rf build/web && mkdir -p build/web
touch build/.gdignore
godot --headless --path . --export-release Web "build/web/game-${B%+}.html" 2>&1 | grep -E "^ERROR" && exit 1
rm -f build/web/*.import
cp web/net.js web/peerjs.min.js build/web/
echo "${B%+}" > build/web/latest.txt
# The front page names no build: it asks latest.txt (fetched fresh, past any
# cache) which one is current, so a cached front page can never point at a
# build that's gone. Publishing keeps the last few builds too.
cat > build/web/index.html <<'HTML'
<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Approved</title>
<body style="background:#0e0f12;color:#e8e1cf;font:20px sans-serif;text-align:center;padding-top:20vh">
<p id="m">Loading Approved...</p>
<script>
fetch("latest.txt?" + Date.now(), { cache: "no-store" })
  .then((r) => r.text())
  .then((b) => location.replace("game-" + b.trim() + ".html" + location.search))
  .catch(() => { document.getElementById("m").textContent = "Couldn't load the game. Please reload the page."; });
</script>
</body></html>
HTML
ls build/web

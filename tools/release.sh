#!/usr/bin/env bash
# Publish a new version of the game so every player gets it automatically.
#
#   tools/release.sh 0.3.0 "What changed, one line"
#
# Writes version.txt, commits, exports the Windows game (MultiplayerGame.exe + MultiplayerGame.pck, zipped) and the
# update pack (game.pck: every script, scene and asset), and publishes them as GitHub release v<version>. Players'
# games see the new release the next time they start, download game.pck (a few MB) and offer "Restart now".
# A release built with a different Godot version can't be patched in; players are sent to the download page instead
# (the release notes carry "godot: <version>" for that check).
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:?usage: tools/release.sh <version> \"notes\"}"
NOTES="${2:-}"
GODOT="${GODOT:-/c/Users/Jacob Maddux/dev/tools/godot-export/Godot_v4.7.2-stable_win64_console.exe}"
GV="$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
[ "$(echo "$GV" | tr -cd '.' | wc -c)" = "1" ] && GV="$GV.0"

printf "%s\n" "$VER" > version.txt
git add -A
git commit -q -m "Release v$VER${NOTES:+: $NOTES}" || true

rm -rf export/windows export/game.pck export/MultiplayerGame-windows.zip
mkdir -p export/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" export/windows/MultiplayerGame.exe >/dev/null 2>&1
"$GODOT" --headless --path . --export-pack "Windows Desktop" export/game.pck >/dev/null 2>&1
[ -f export/windows/MultiplayerGame.exe ] && [ -f export/windows/MultiplayerGame.pck ] && [ -f export/game.pck ] \
  || { echo "export failed"; exit 1; }
powershell -NoProfile -Command "Compress-Archive -Path 'export\\windows\\*' -DestinationPath 'export\\MultiplayerGame-windows.zip' -Force"

git push -q
gh release create "v$VER" export/MultiplayerGame-windows.zip export/game.pck \
  --title "Multiplayer Game $VER" \
  --notes "${NOTES:-Update.}

**Already playing?** Just start the game: it downloads this update and offers **Restart now**.
**New?** Download MultiplayerGame-windows.zip, unzip it and run MultiplayerGame.exe.

godot: $GV"
echo "released v$VER"

#!/bin/zsh
# Builds Nommo.app, installs it into /Applications (replacing any older copy) and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

pkill -x Nommo 2>/dev/null || true
sleep 1
rm -rf /Applications/Nommo.app
ditto dist/Nommo.app /Applications/Nommo.app
echo "Installed /Applications/Nommo.app"
open /Applications/Nommo.app

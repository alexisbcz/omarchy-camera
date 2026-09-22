#!/bin/bash
# Dev install: copy this checkout into Omarchy's user plugin dir (symlinks are
# rejected by the validator, so this copies). Users install with
# `omarchy plugin add <repo-url>` instead.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.config/omarchy/plugins/alex.iris"

omarchy plugin validate "$src"
mkdir -p "$dest"
rsync -a --delete --exclude .git --exclude install.sh --exclude docs "$src/" "$dest/"
echo "Installed to $dest"

case ${1:-} in
  --enable)
    omarchy-shell shell rescanPlugins
    sleep 1 # rescan is async; enable fails if it runs first
    omarchy plugin enable alex.iris
    ;;
  --restart)
    # The panel is keepLoaded, and hot-reload keeps serving the old compiled
    # Panel.qml; only a shell restart picks up changes to it.
    omarchy restart shell
    ;;
esac

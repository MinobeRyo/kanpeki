#!/bin/sh
set -eu
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_DIR"
export PYTHONPATH="$REPO_DIR/backend"
exec python3 -m kanpeki_audio.server "$@"

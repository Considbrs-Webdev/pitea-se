#!/usr/bin/env bash
set -euo pipefail

# Forced SSH command for the GitHub Actions deploy key.
# Install once on Oderland, then lock ONLY that pubkey in authorized_keys:
#
# restrict,command="/bin/bash /home/considbrs/.oderland-demo-deploy/oderland-demo-ssh-wrapper.sh" ssh-ed25519 AAAA... github-oderland-demo
#
# Do not put restrict/command on your personal login key.

if [ "$(id -u)" -eq 0 ]; then
    echo "Error: refusing to run as root" >&2
    exit 1
fi

export PATH=/usr/bin:/bin
umask 077

STAGING="$HOME/.oderland-demo-deploy"
TAR_PATH="$STAGING/release.tar.gz"
SCRIPT_PATH="$STAGING/deploy-oderland-demo.sh"
UPLOAD_COMMAND='cat > "$HOME/.oderland-demo-deploy/release.tar.gz"'

mkdir -p "$STAGING"

case "${SSH_ORIGINAL_COMMAND:-}" in
    "$UPLOAD_COMMAND")
        cat > "$TAR_PATH"
        chmod 600 "$TAR_PATH"
        exit 0
        ;;
    oderland-demo-deploy)
        if [ ! -f "$SCRIPT_PATH" ] || [ -L "$SCRIPT_PATH" ]; then
            echo "Error: $SCRIPT_PATH is missing or a symlink. Install deploy-oderland-demo.sh on the server first." >&2
            exit 1
        fi
        chmod 700 "$SCRIPT_PATH"
        exec bash "$SCRIPT_PATH" "$TAR_PATH"
        ;;
    *)
        echo "Error: command not allowed for this key" >&2
        exit 1
        ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# Extract a Municipio release tarball into the Oderland demo docroot only.
# Docroot is hardcoded. Extra CLI path arguments are ignored.
#
# Usage: deploy-oderland-demo.sh [/path/to/release.tar.gz]

if [ "$(id -u)" -eq 0 ]; then
    echo "Error: refusing to deploy as root" >&2
    exit 1
fi

TAR_PATH="${1:-/home/considbrs/.oderland-demo-deploy/release.tar.gz}"
DOCROOT="/home/considbrs/domains/pitea-new.considbrs.se"

if [ ! -f "$TAR_PATH" ]; then
    echo "Error: tar file not found: $TAR_PATH" >&2
    exit 1
fi

if [ ! -d "$DOCROOT" ]; then
    echo "Error: docroot does not exist (will not create it): $DOCROOT" >&2
    exit 1
fi

if [ -L "$DOCROOT" ]; then
    echo "Error: refusing to deploy to a symlinked docroot: $DOCROOT" >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync is required on the server" >&2
    exit 1
fi

mkdir -p /home/considbrs/.oderland-demo-deploy

resolve_path() {
    local path=$1
    if command -v realpath >/dev/null 2>&1; then
        realpath -e "$path"
        return
    fi
    readlink -f "$path"
}

DOCROOT_RESOLVED=$(resolve_path "$DOCROOT")
if [ "$DOCROOT_RESOLVED" != "/home/considbrs/domains/pitea-new.considbrs.se" ]; then
    echo "Error: refusing to deploy anywhere except /home/considbrs/domains/pitea-new.considbrs.se (got $DOCROOT_RESOLVED)" >&2
    exit 1
fi

if [ ! -d "$DOCROOT_RESOLVED" ] || [ -L "$DOCROOT_RESOLVED" ]; then
    echo "Error: resolved docroot must be a real directory: $DOCROOT_RESOLVED" >&2
    exit 1
fi

DOCROOT="$DOCROOT_RESOLVED"

EXTRACT_DIR=$(mktemp -d /home/considbrs/.oderland-demo-deploy/extract.XXXXXX)
cleanup() {
    rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

echo "Extracting $TAR_PATH"
if tar -tzf "$TAR_PATH" | grep -E '(^/)|(^|/)\.\.(/|$)' >/dev/null; then
    echo "Error: tarball contains absolute paths or '..' entries; refusing to extract" >&2
    exit 1
fi
tar -xzf "$TAR_PATH" -C "$EXTRACT_DIR"

if [ ! -f "$EXTRACT_DIR/wp-config.php" ] || [ ! -d "$EXTRACT_DIR/wp" ]; then
    echo "Error: tarball does not look like a Municipio release (missing wp-config.php or wp/)" >&2
    exit 1
fi

if [ -d "$EXTRACT_DIR/wp-content/plugins/advanced-custom-fields-pro" ]; then
    echo "Moving advanced-custom-fields-pro to mu-plugins"
    mkdir -p "$EXTRACT_DIR/wp-content/mu-plugins"
    rm -rf "$EXTRACT_DIR/wp-content/mu-plugins/advanced-custom-fields-pro"
    mv "$EXTRACT_DIR/wp-content/plugins/advanced-custom-fields-pro" \
        "$EXTRACT_DIR/wp-content/mu-plugins/advanced-custom-fields-pro"
fi

echo "Syncing into $DOCROOT"
rsync -a --delete --safe-links \
    --exclude '/config/' \
    --exclude '/wp-content/uploads/' \
    --exclude '/.htaccess' \
    --exclude '/.well-known/' \
    --exclude '/cgi-bin/' \
    --exclude '/error_log' \
    --exclude '/logs/' \
    --exclude '/stats/' \
    "$EXTRACT_DIR/" "$DOCROOT/"

mkdir -p "$DOCROOT/config" "$DOCROOT/wp-content/uploads"

echo "Setting permissions: directories=755, files=644"
find -P "$DOCROOT" -xdev -type d -exec chmod 755 {} +
find -P "$DOCROOT" -xdev -type f -exec chmod 644 {} +

if [ ! -f "$DOCROOT/config/database.php" ]; then
    echo "Warning: $DOCROOT/config/database.php is missing. Copy config-example/ on the server before the site will boot."
fi

echo "Deployed to $DOCROOT"
exit 0

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

TAR_PATH="${1:-$HOME/.oderland-demo-deploy/release.tar.gz}"
DOCROOT="$HOME/domains/pitea-new.considbrs.se"
ALLOWED_SUFFIX="/domains/pitea-new.considbrs.se"

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

mkdir -p "$HOME/.oderland-demo-deploy"

resolve_path() {
    local path=$1
    if command -v realpath >/dev/null 2>&1; then
        realpath -e "$path"
        return
    fi
    readlink -f "$path"
}

DOCROOT_RESOLVED=$(resolve_path "$DOCROOT")
case "$DOCROOT_RESOLVED" in
    *"$ALLOWED_SUFFIX") ;;
    *)
        echo "Error: resolved docroot is not the pitea-new demo folder: $DOCROOT_RESOLVED" >&2
        exit 1
        ;;
esac

if [ "$DOCROOT_RESOLVED" = "$ALLOWED_SUFFIX" ] || [ "$DOCROOT_RESOLVED" = "/" ]; then
    echo "Error: refusing unsafe resolved docroot: $DOCROOT_RESOLVED" >&2
    exit 1
fi

if [ "$(basename "$DOCROOT_RESOLVED")" != "pitea-new.considbrs.se" ] \
    || [ "$(basename "$(dirname "$DOCROOT_RESOLVED")")" != "domains" ]; then
    echo "Error: refusing docroot that is not .../domains/pitea-new.considbrs.se: $DOCROOT_RESOLVED" >&2
    exit 1
fi

if [ ! -d "$DOCROOT_RESOLVED" ] || [ -L "$DOCROOT_RESOLVED" ]; then
    echo "Error: resolved docroot must be a real directory: $DOCROOT_RESOLVED" >&2
    exit 1
fi

DOCROOT="$DOCROOT_RESOLVED"

EXTRACT_DIR=$(mktemp -d "$HOME/.oderland-demo-deploy/extract.XXXXXX")
cleanup() {
    rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

echo "Extracting $TAR_PATH"
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
    "$EXTRACT_DIR/" "$DOCROOT/"

mkdir -p "$DOCROOT/config" "$DOCROOT/wp-content/uploads"

if [ ! -f "$DOCROOT/.htaccess" ]; then
    echo "Writing default WordPress .htaccess"
    cat > "$DOCROOT/.htaccess" << 'EOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteRule ^index\.php$ - [L]
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF
fi

echo "Setting permissions: directories=755, files=644"
find -P "$DOCROOT" -xdev -type d -exec chmod 755 {} +
find -P "$DOCROOT" -xdev -type f -exec chmod 644 {} +

if [ ! -f "$DOCROOT/config/database.php" ]; then
    echo "Warning: $DOCROOT/config/database.php is missing. Copy config-example/ on the server before the site will boot."
fi

echo "Deployed to $DOCROOT"
exit 0

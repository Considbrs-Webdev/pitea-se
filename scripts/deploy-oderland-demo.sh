#!/usr/bin/env bash
set -euo pipefail

# Extract a Municipio release tarball into an Oderland domain folder in place.
# Preserves server-side config, uploads, Let's Encrypt, and an existing .htaccess.
#
# Usage: deploy-oderland-demo.sh /path/to/release.tar.gz /path/to/docroot

TAR_PATH=${1:-}
DOCROOT=${2:-}

if [ -z "$TAR_PATH" ] || [ -z "$DOCROOT" ]; then
    echo "Usage: $0 /path/to/release.tar.gz /path/to/docroot" >&2
    exit 1
fi

if [ ! -f "$TAR_PATH" ]; then
    echo "Error: tar file not found: $TAR_PATH" >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "Error: rsync is required on the server" >&2
    exit 1
fi

if [[ "$DOCROOT" != /* ]]; then
    DOCROOT="${HOME}/${DOCROOT}"
fi

mkdir -p "$DOCROOT"

EXTRACT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/oderland-demo.XXXXXX")
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
rsync -a --delete \
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
find "$DOCROOT" -type d -exec chmod 755 {} +
find "$DOCROOT" -type f -exec chmod 644 {} +

if [ ! -f "$DOCROOT/config/database.php" ]; then
    echo "Warning: $DOCROOT/config/database.php is missing. Copy config-example/ on the server before the site will boot."
fi

echo "Deployed to $DOCROOT"
exit 0

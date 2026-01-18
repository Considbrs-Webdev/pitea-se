#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/create-release.sh [path/to/release.tar.gz] [releases-dir]
# Defaults: release.tar.gz and releases

TAR_PATH=${1:-release.tar.gz}
RELEASES_DIR_NAME=${2:-releases}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASES_DIR="$ROOT_DIR/$RELEASES_DIR_NAME"

if [ ! -f "$TAR_PATH" ]; then
    echo "Error: tar file not found: $TAR_PATH" >&2
    exit 1
fi

DATE=$(date +%F)

compute_hash() {
    local file=$1
    if [ ! -e "$file" ]; then
        echo ""
        return
    fi

    # Prefer stat variants (portable between GNU and BSD/macOS)
    if stat -c %Y "$file" >/dev/null 2>&1; then
        stat -c %Y "$file"
        return
    fi

    if stat -f %m "$file" >/dev/null 2>&1; then
        stat -f %m "$file"
        return
    fi

    # Fallback to Python to get modification time
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))' "$file"
        return
    fi
    if command -v python >/dev/null 2>&1; then
        python -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))' "$file"
        return
    fi

    # Unable to determine
    echo ""
}

FULL_HASH=$(compute_hash "$TAR_PATH")
if [ -z "$FULL_HASH" ]; then
    echo "Warning: unable to compute hash, using timestamp only" >&2
    SHORT_HASH="ts"
else
    SHORT_HASH=${FULL_HASH:0:8}
fi

TARGET_DIR="$RELEASES_DIR/release-${DATE}-${SHORT_HASH}"

mkdir -p "$RELEASES_DIR"

if [ -e "$TARGET_DIR" ]; then
    echo "Error: target directory already exists: $TARGET_DIR" >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

echo "Extracting $TAR_PATH -> $TARGET_DIR"
tar -xzf "$TAR_PATH" -C "$TARGET_DIR"

# Add a symlink inside the release: config -> ../../config
echo "Adding config symlink inside release"
ln -sfn ../../config "$TARGET_DIR/config"

# Update symlink `current-release` at repository root to point to new release
SYMLINK_PATH="$ROOT_DIR/current-release"

echo "Updating symlink: $SYMLINK_PATH -> $TARGET_DIR"
ln -sfn "$TARGET_DIR" "$SYMLINK_PATH"

# Move ACF Pro plugin from plugins to mu-plugins inside the created release
echo "Moving advanced-custom-fields-pro to mu-plugins inside release"
mv "$TARGET_DIR/wp-content/plugins/advanced-custom-fields-pro" "$TARGET_DIR/wp-content/mu-plugins/advanced-custom-fields-pro"

# Ensure correct permissions: release dir 755, all subdirectories 755, files 644
echo "Setting permissions: directories=755, files=644 in $TARGET_DIR"
chmod 755 "$TARGET_DIR"
find "$TARGET_DIR" -type d -exec chmod 755 {} +
find "$TARGET_DIR" -type f -exec chmod 644 {} +

# Rename the original tarball to match the release folder name
NEW_TAR_NAME="release-${DATE}-${SHORT_HASH}.tar.gz"
NEW_TAR_PATH="$RELEASES_DIR/$NEW_TAR_NAME"
echo "Renaming tarball: $TAR_PATH -> $NEW_TAR_PATH"
mv "$TAR_PATH" "$NEW_TAR_PATH"

# Cleanup: keep only the latest 5 release directories and tarballs
echo "Cleaning up old releases, keeping latest 5..."
shopt -s nullglob

# Remove older release directories (glob with trailing slash matches directories only)
dir_glob=("$RELEASES_DIR"/release-*/)
if [ ${#dir_glob[@]} -gt 0 ]; then
    old_dirs=$(ls -1dt "${dir_glob[@]}" | tail -n +6) || true
    if [ -n "$old_dirs" ]; then
        while IFS= read -r d; do
            echo "Removing old release dir: $d"
            rm -rf "$d"
        done <<< "$old_dirs"
    fi
fi

# Remove older tarballs
tar_glob=("$RELEASES_DIR"/release-*.tar.gz)
if [ ${#tar_glob[@]} -gt 0 ]; then
    old_tars=$(ls -1t "${tar_glob[@]}" | tail -n +6) || true
    if [ -n "$old_tars" ]; then
        while IFS= read -r f; do
            echo "Removing old tarball: $f"
            rm -f "$f"
        done <<< "$old_tars"
    fi
fi
shopt -u nullglob

echo "Created release: $TARGET_DIR"
echo "current-release -> $(readlink "$SYMLINK_PATH")"

exit 0

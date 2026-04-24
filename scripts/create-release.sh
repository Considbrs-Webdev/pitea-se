#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/create-release.sh [path/to/release.tar.gz] [releases-dir]
# Defaults: release.tar.gz and releases

TAR_PATH=${1:-release.tar.gz}
RELEASES_DIR_NAME=${2:-releases}

# Directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If TAR_PATH is a bare filename (no slash), prefer the tarball located
# in the same directory as this script so invoking from another CWD still
# finds the expected release.tar.gz
case "$TAR_PATH" in
    */*) ;;
    *) TAR_PATH="$SCRIPT_DIR/$TAR_PATH" ;;
esac

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$ROOT_DIR/$RELEASES_DIR_NAME"
PRIVATE_PLUGINS_DIR="$ROOT_DIR/plugins"

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
PRIVATE_PLUGIN_DEST_ROOT="$TARGET_DIR/wp-content/plugins"

mkdir -p "$RELEASES_DIR"

if [ -e "$TARGET_DIR" ]; then
    echo "Error: target directory already exists: $TARGET_DIR" >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

echo "Extracting $TAR_PATH -> $TARGET_DIR"
tar -xzf "$TAR_PATH" -C "$TARGET_DIR"

# Extract private plugin ZIPs into normalized plugin folders inside the release.
if [ -d "$PRIVATE_PLUGINS_DIR" ]; then
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Error: unzip is required to extract plugin ZIPs from $PRIVATE_PLUGINS_DIR" >&2
        exit 1
    fi

    shopt -s nullglob
    plugin_archives=("$PRIVATE_PLUGINS_DIR"/*.zip)
    shopt -u nullglob

    if [ ${#plugin_archives[@]} -eq 0 ]; then
        echo "No private plugin ZIPs found, skipping: $PRIVATE_PLUGINS_DIR"
    else
        mkdir -p "$PRIVATE_PLUGIN_DEST_ROOT"

        for plugin_zip in "${plugin_archives[@]}"; do
            plugin_name=$(basename "$plugin_zip" .zip)
            plugin_dest="$PRIVATE_PLUGIN_DEST_ROOT/$plugin_name"
            extract_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/private-plugin.XXXXXX")

            echo "Extracting private plugin ZIP: $(basename "$plugin_zip") -> $plugin_dest"
            unzip -q "$plugin_zip" -d "$extract_tmp_dir"

            rm -rf "$extract_tmp_dir/__MACOSX"
            rm -rf "$plugin_dest"

            if [ -d "$extract_tmp_dir/$plugin_name" ]; then
                mv "$extract_tmp_dir/$plugin_name" "$plugin_dest"
            else
                shopt -s dotglob nullglob
                extracted_entries=("$extract_tmp_dir"/*)
                shopt -u dotglob nullglob

                if [ ${#extracted_entries[@]} -eq 1 ] && [ -d "${extracted_entries[0]}" ]; then
                    mv "${extracted_entries[0]}" "$plugin_dest"
                else
                    mkdir -p "$plugin_dest"
                    shopt -s dotglob nullglob
                    extracted_entries=("$extract_tmp_dir"/*)
                    shopt -u dotglob nullglob

                    if [ ${#extracted_entries[@]} -gt 0 ]; then
                        mv "${extracted_entries[@]}" "$plugin_dest"/
                    fi
                fi
            fi

            rm -rf "$extract_tmp_dir"
        done
    fi
else
    echo "Private plugins directory not found, skipping: $PRIVATE_PLUGINS_DIR"
fi

# Adding config symlink
echo "Adding config symlink inside release"
ln -sfn /webb/municipio/config "$TARGET_DIR/config"

# Adding .htaccess symlink
echo "Adding .htaccess symlink inside release"
ln -sfn /webb/municipio/config/.htaccess "$TARGET_DIR/.htaccess"

# Adding uploads symlink
echo "Adding uploads symlink inside release"
ln -sfn /webb/municipio/uploads "$TARGET_DIR/wp-content/uploads"

# Adding languages symlink
echo "Adding language symlink inside release"
ln -sfn /webb/municipio/languages "$TARGET_DIR/wp-content/languages"

# Adding CICD symlink
echo "Adding CICD symlink inside release"
ln -sfn /webb/municipio/cicd "$TARGET_DIR/cicd"

# Update symlink `current-release` at repository root to point to new release
SYMLINK_PATH="$ROOT_DIR/htdocs"

echo "Updating symlink: $SYMLINK_PATH -> $TARGET_DIR"
ln -sfn "$TARGET_DIR" "$SYMLINK_PATH"

# Move ACF Pro plugin from plugins to mu-plugins inside the created release
echo "Moving advanced-custom-fields-pro to mu-plugins inside release"
mv "$TARGET_DIR/wp-content/plugins/advanced-custom-fields-pro" "$TARGET_DIR/wp-content/mu-plugins/advanced-custom-fields-pro"

# Copy InlayList.php into theme module inside release (overwrite)
echo "Copying InlayList.php into release theme module"
cp /webb/municipio/InlayList.php "$TARGET_DIR/wp-content/themes/municipio/Modularity/source/php/Module/InlayList/InlayList.php"

# Ensure correct permissions: release dir 755, all subdirectories 755, files 644
echo "Setting permissions: directories=755, files=644 in $TARGET_DIR"
chmod 755 "$TARGET_DIR"
find "$TARGET_DIR" -type d -exec chmod 755 {} +
find "$TARGET_DIR" -type f -exec chmod 644 {} +

# Clear blade cache
echo "Clearing /webb/municipio/tmp/blade-cache..."
if [ -d "/webb/municipio/tmp/blade-cache" ]; then
    find "/webb/municipio/tmp/blade-cache" -mindepth 1 -exec rm -rf {} +
fi

# Clear LS Cache
if [ -d "/data/lscache/pitea" ]; then
    find "/data/lscache/pitea" -mindepth 1 -exec rm -rf {} +
fi

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
